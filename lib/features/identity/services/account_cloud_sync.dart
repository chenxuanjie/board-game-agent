import 'dart:async';
import 'package:app_identity/app_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_storage/webdav_storage.dart';
import 'package:webdav_sync/webdav_sync.dart';
import '../../../app/state/app_controller.dart';
import 'account_sync_remote.dart';
import 'account_sync_store.dart';
import 'account_public_reactions.dart';
import 'reaction_sync_diagnostics.dart';
import '../../games/models/game_vote_record.dart';

enum AccountCloudStatus { idle, syncing, synced, pending, paused }

/// One user task with independent network lanes and a serialized local journal.
final class AccountCloudSync extends ChangeNotifier {
  AccountCloudSync({
    required this.controller,
    required this.scope,
    required this.files,
    required this.isActive,
    this.publicReactions,
  });
  final AppController controller;
  final String scope;
  final AccountPrivateFiles files;
  final bool Function() isActive;
  final AccountPublicReactions? publicReactions;
  Future<AccountSyncLocalStore>? _localReady;
  AccountSyncLocalStore? _journal;
  Timer? _debounce, _poll, _publicationRetry, _rankingRetry;
  Future<void>? _privateOperation, _publicationOperation, _rankingOperation;
  ReactionTrace? _publicationTrace, _rankingTrace;
  bool _privateAgain = false, _rankingAgain = false, _forceRankingAgain = false;
  int _localBusy = 0, _publicationAttempts = 0, _rankingAttempts = 0;
  bool _rankingsConfirmed = false;
  int _rankingVersion = 0;
  bool get publishing => _publicationOperation != null;
  bool get refreshingRankings => _rankingOperation != null;
  bool get publicSyncing => publishing || refreshingRankings;
  bool get publicPublished =>
      publicReactions?.confirmedFingerprint != null &&
      _journal?.publicFingerprint == publicReactions!.confirmedFingerprint &&
      publicReactions!.confirmsSelection(
        GameVoteBallot.campaign,
        controller.gameVotes.selectedGames,
      ) &&
      publicReactions!.confirmsSelection(
        GameVoteBallot.favoritesNamespace,
        controller.favoriteStatistics.selectedGames,
      );
  bool get publicSynced => _rankingsConfirmed && publicPublished;
  bool get rankingsAvailable => _rankingsConfirmed;
  String? publicationError, rankingError;
  String? get publicError =>
      publicationError ??
      (rankingError == null
          ? null
          : publicPublished
          ? '收藏与投票已提交，排行刷新失败，请重试。$rankingError'
          : rankingError);
  bool _disposed = false;
  int _generation = 0;
  bool enabled = true;
  AccountCloudStatus status = AccountCloudStatus.idle;
  String? error;
  DateTime? lastSuccess;
  String get _enabledKey => 'account_cloud_enabled.$scope';
  bool get _active => !_disposed && enabled && isActive();
  bool get syncing => _privateOperation != null || publicSyncing;
  AccountCloudStatus get overallStatus {
    if (!enabled) return AccountCloudStatus.paused;
    if (syncing) return AccountCloudStatus.syncing;
    if (error != null || publicError != null) return AccountCloudStatus.pending;
    if (status == AccountCloudStatus.synced &&
        (publicReactions == null || publicSynced)) {
      return AccountCloudStatus.synced;
    }
    return AccountCloudStatus.idle;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    enabled = prefs.getBool(_enabledKey) ?? true;
    lastSuccess = DateTime.tryParse(
      prefs.getString('account_cloud_last_success.$scope') ?? '',
    );
    controller.addListener(_changed);
    _poll = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(synchronize()),
    );
    status = enabled ? AccountCloudStatus.idle : AccountCloudStatus.paused;
    _notify();
    unawaited(synchronize());
  }

  void _changed() {
    if (!_active || _localBusy > 0 || !controller.accountCloudIdle) return;
    // Reactions bypass this debounce through publishReactions after durable save.
    // Other personal edits share a short debounce, including edits in flight.
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () {
      if (_privateOperation != null) {
        _privateAgain = true;
      } else {
        unawaited(_syncPrivate());
      }
    });
  }

  Future<void> setEnabled(bool value) async {
    if (!await (await SharedPreferences.getInstance()).setBool(
      _enabledKey,
      value,
    )) {
      throw StateError('同步设置保存失败');
    }
    if (_disposed) return;
    enabled = value;
    error = publicationError = rankingError = null;
    if (!value) {
      _generation++;
      _debounce?.cancel();
      _publicationRetry?.cancel();
      _rankingRetry?.cancel();
      _privateAgain = _rankingAgain = _forceRankingAgain = false;
      files.cancelRequests();
      publicReactions?.cancel();
      status = AccountCloudStatus.paused;
      controller.gameVotes.pausePublicSync();
      controller.favoriteStatistics.pausePublicSync();
    }
    _notify();
    if (value) {
      await Future.wait([
        ?_privateOperation,
        ?_publicationOperation,
        ?_rankingOperation,
      ]);
      if (_active) unawaited(synchronize());
    }
  }

  void _check(int generation) {
    if (!_active || generation != _generation) {
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    }
  }

  Future<AccountSyncLocalStore> _local() => _localReady ??=
      (() async {
        final local = AccountSyncLocalStore(
          datasetId: scope,
          transaction: <T>(work) => _transaction<T>(work, reactionsOnly: false),
          reactionTransaction: <T>(work) =>
              _transaction<T>(work, reactionsOnly: true),
        );
        await local.initialize();
        _journal = local;
        return local;
      })().catchError((Object failure, StackTrace stack) {
        _localReady = null;
        Error.throwWithStackTrace(failure, stack);
      });

  Future<T> _transaction<T>(
    Future<T> Function(
      AccountEntities current,
      Future<void> Function(AccountEntities) project,
    )
    work, {
    required bool reactionsOnly,
  }) async {
    final generation = _generation;
    _check(generation);
    _localBusy++;
    try {
      final transaction = reactionsOnly
          ? controller.accountCloudReactionTransaction<T>
          : controller.accountCloudTransaction<T>;
      return await transaction(scope, (current, project) async {
        _check(generation);
        return work(current, (entities) async {
          _check(generation);
          await project(entities);
          _check(generation);
        });
      });
    } finally {
      _localBusy--;
    }
  }

  /// One user entry, three independent lanes. A ranking refresh never starts
  /// publication or waits for private network work.
  Future<void> synchronize() async {
    if (!_active) return;
    final observed = _rankingVersion;
    final publication = _publishReactions();
    final private = _syncPrivate();
    await publication;
    // Publication already requests a read when its version changes. Join that
    // read without queuing another, and never postpone it behind private uploads.
    if (_rankingOperation != null) {
      await _rankingOperation;
    } else if (_rankingVersion == observed) {
      await _readRankings();
    }
    await private;
    await _publicationOperation;
    await _rankingOperation;
  }

  Future<void> retry() async {
    if (!_active) return;
    if (error == null && publicError == null) return synchronize();
    await Future.wait([
      if (error != null) _syncPrivate(),
      if (publicationError != null) _publishReactions(),
      if (rankingError != null) _readRankings(force: true),
    ]);
  }

  /// Called after a durable favorite/vote mutation. Acknowledges only our UID;
  /// a foreign record failure cannot turn this into a publication failure.
  Future<void> publishReactions() async {
    if (!_active) {
      if (!_disposed && enabled) {
        publicationError = '账号暂不可用，收藏已保存在本机，待发布。';
        _notify();
      }
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    }
    _publicationAttempts = 0;
    await _publishReactions();
    if (!_active) {
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    }
    if (publicationError != null) {
      throw StateError(publicationError!);
    }
  }

  /// User ranking refresh bypasses metadata cache, but does not rewrite a ballot.
  Future<void> refreshPublic() async {
    if (!_active) {
      if (!_disposed && enabled) {
        rankingError = '账号暂不可用，已保留上次统计。';
        _notify();
      }
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    }
    _rankingAttempts = 0;
    await _readRankings(force: true);
    if (!_active) {
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    }
    if (rankingError != null) throw StateError(rankingError!);
  }

  Future<void> _publishReactions() {
    if (!_active || publicReactions == null) return Future.value();
    if (_publicationOperation != null) {
      _publicationTrace?.event('合并新发布请求，当前轮后核对最新本机版本');
      return _publicationOperation!;
    }
    _publicationRetry?.cancel();
    final done = Completer<void>();
    _publicationOperation = done.future;
    publicationError = null;
    controller.gameVotes.beginPublication();
    controller.favoriteStatistics.beginPublication();
    _notify();
    final generation = _generation;
    final trace = _publicationTrace = controller.reactionDiagnostics.start(
      '发布自己的喜欢与投票',
    );
    unawaited(() async {
      try {
        final local = await trace.measure('准备本机同步日志', _local);
        for (var round = 0; round < 3; round++) {
          _check(generation);
          await trace.measure(
            '记录本机选择与取消版本',
            () => local.captureReactions(check: () => _check(generation)),
          );
          _check(generation);
          if (local.hasPendingOperations) unawaited(_syncPrivate());
          final before = publicReactions!.confirmedFingerprint;
          await publicReactions!
              .publish(local, trace: trace)
              .timeout(
                const Duration(seconds: 20),
                onTimeout: () {
                  publicReactions!.cancelPublication();
                  throw TimeoutException('公共发布超时');
                },
              );
          _check(generation);
          if (publicReactions!.confirmsSelection(
            GameVoteBallot.campaign,
            controller.gameVotes.selectedGames,
          )) {
            controller.gameVotes.confirmPublication();
          }
          if (publicReactions!.confirmsSelection(
            GameVoteBallot.favoritesNamespace,
            controller.favoriteStatistics.selectedGames,
          )) {
            controller.favoriteStatistics.confirmPublication();
          }
          // Counts refresh is a different task. Never await it here.
          if (before != publicReactions!.confirmedFingerprint ||
              !_rankingsConfirmed) {
            unawaited(_readRankings());
          }
          await local.captureReactions(check: () => _check(generation));
          _check(generation);
          if (local.publicFingerprint ==
              publicReactions!.confirmedFingerprint) {
            break;
          }
          if (round == 2) throw StateError('仍有新变更待发布');
        }
        _publicationAttempts = 0;
        trace.finish(detail: '自己的公共版本已读回核对；排行榜另行读取');
      } catch (failure) {
        trace.finish(
          failed: true,
          detail: ReactionSyncDiagnostics.failureLabel(failure),
        );
        if (_active && generation == _generation) {
          publicationError = AccountPublicReactions.describe(failure);
          controller.gameVotes.failPublication();
          controller.favoriteStatistics.failPublication();
          if (_publicationAttempts < 2) {
            _publicationRetry = Timer(
              Duration(seconds: _publicationAttempts++ == 0 ? 3 : 10),
              () => unawaited(_publishReactions()),
            );
          }
        }
      } finally {
        _publicationTrace = null;
        _publicationOperation = null;
        done.complete();
        _notify();
      }
    }());
    return done.future;
  }

  Future<void> _readRankings({bool force = false}) {
    if (!_active || publicReactions == null) return Future.value();
    if (_rankingOperation != null) {
      _rankingAgain = true;
      _forceRankingAgain |= force;
      _rankingTrace?.event(force ? '收到新刷新请求，本轮结束后强制重读' : '发布完成，本轮结束后再读统计');
      return _rankingOperation!;
    }
    _rankingRetry?.cancel();
    final done = Completer<void>();
    _rankingOperation = done.future;
    rankingError = null;
    publicReactions!.error = null;
    controller.gameVotes.beginPublicSync();
    controller.favoriteStatistics.beginPublicSync();
    _notify();
    final generation = _generation;
    final trace = _rankingTrace = controller.reactionDiagnostics.start(
      '读取公共排行榜',
    );
    unawaited(() async {
      try {
        final local = await trace.measure('准备本机同步日志', _local);
        var forceRead = force;
        for (var round = 0; round < 3; round++) {
          forceRead |= _forceRankingAgain;
          _rankingAgain = false;
          _forceRankingAgain = false;
          _check(generation);
          await publicReactions!
              .refresh(local, force: forceRead, trace: trace)
              .timeout(
                const Duration(seconds: 20),
                onTimeout: () {
                  publicReactions!.cancelRankings();
                  throw TimeoutException('排行刷新超时');
                },
              );
          _check(generation);
          await controller.gameVotes.acceptPublicCounts(
            'account-public-v1.$scope',
            publicReactions!.counts(GameVoteBallot.campaign),
            check: () => _check(generation),
            revision: controller.gameVotes.selectionRevision,
          );
          await controller.favoriteStatistics.acceptPublicCounts(
            'account-public-v1.$scope',
            publicReactions!.counts(GameVoteBallot.favoritesNamespace),
            check: () => _check(generation),
            revision: controller.favoriteStatistics.selectionRevision,
          );
          _check(generation);
          _rankingsConfirmed = true;
          _rankingVersion++;
          final observedSlugs = {
            ...controller.reactionDiagnostics.watchedSlugs,
            ...controller.favoriteRankings
                .take(5)
                .map((entry) => entry.game.slug),
          };
          for (final slug in observedSlugs) {
            trace.event(
              '本轮排行榜结果',
              detail:
                  '$slug：NAS 本轮 ${publicReactions!.observedRemoteCount(GameVoteBallot.favoritesNamespace, slug)} 人；界面 ${controller.favoriteStatistics.count(slug)} 人（含本机已保存选择）',
            );
          }
          // A query may merge our other device's confirmed records locally,
          // but never starts a server write. Publication/polling handles echoes.
          if (!_rankingAgain) break;
          forceRead = _forceRankingAgain;
          if (round == 2) throw StateError('排行仍有更新待读取');
        }
        _rankingAttempts = 0;
        trace.finish(detail: '本轮完整远端统计已保存；此任务未上传文件');
      } catch (failure) {
        trace.finish(
          failed: true,
          detail: '${ReactionSyncDiagnostics.failureLabel(failure)}；保留上次完整统计',
        );
        if (_active && generation == _generation) {
          rankingError = AccountPublicReactions.describe(failure);
          if (failure is PublicRecordFailure) {
            publicReactions!.diagnostic = failure;
          }
          publicReactions!.error = rankingError;
          controller.gameVotes.markPublicFailure();
          controller.favoriteStatistics.markPublicFailure();
          if (_rankingAttempts < 2) {
            _rankingRetry = Timer(
              Duration(seconds: _rankingAttempts++ == 0 ? 3 : 10),
              () => unawaited(_readRankings(force: true)),
            );
          }
        }
      } finally {
        _rankingTrace = null;
        _rankingOperation = null;
        done.complete();
        _notify();
      }
    }());
    return done.future;
  }

  Future<void> _syncPrivate() {
    if (!_active) return Future.value();
    if (!controller.canStartPrivateCloudSync && _privateOperation == null) {
      if (controller.reactionDiagnostics.visible) {
        controller.reactionDiagnostics
            .start('私人备份暂缓')
            .finish(detail: '本机正忙，待后续同步；自己的公共喜欢发布独立执行');
      }
      _notify();
      return Future.value();
    }
    if (_privateOperation != null) return _privateOperation!;
    _debounce?.cancel();
    final done = Completer<void>();
    _privateOperation = done.future;
    status = AccountCloudStatus.syncing;
    error = null;
    _notify();
    final generation = _generation;
    final trace = controller.reactionDiagnostics.start('私人账号备份');
    unawaited(() async {
      try {
        final local = await _local();
        var rounds = 0;
        do {
          _privateAgain = false;
          _check(generation);
          await trace.measure(
            '等待本机私人数据稳定',
            () => controller.waitForAccountCloudData(scope),
          );
          _check(generation);
          await trace.measure(
            '记录私人增量日志',
            () => local.capture(check: () => _check(generation)),
          );
          _check(generation);
          final before = local.publicFingerprint;
          var expired = false;
          void check() {
            _check(generation);
            if (expired) throw const SyncProtocolException('私人同步已超时');
          }

          await trace.measure('私人增量上传与拉取', () async {
            final result =
                await IncrementalSyncEngine(
                  local: _CheckedLocalStore(
                    local,
                    check,
                    () => controller.waitForAccountCloudData(scope),
                  ),
                  remote: AccountSyncRemoteStore(
                    files: _CheckedPrivateFiles(files, check),
                    datasetId: scope,
                  ),
                  batchSize: 100,
                  maxRounds: 8,
                  retryPolicy: const SyncRetryPolicy(maxAttempts: 2),
                  onProgress: (progress) => trace.event(
                    switch (progress.phase) {
                      SyncPhase.preparing => '准备私人增量传输',
                      SyncPhase.checking => '查询私人远端增量',
                      SyncPhase.downloading => '私人增量已返回',
                      SyncPhase.merging => '提交私人增量到本机',
                      SyncPhase.uploading => '上传私人待办记录',
                      SyncPhase.completed => '私人引擎返回，待核对完成状态',
                      SyncPhase.conflict => '私人合并存在冲突',
                      SyncPhase.failed => '私人增量传输未完成',
                    },
                    status: progress.isActive
                        ? ReactionTraceStatus.running
                        : ReactionTraceStatus.info,
                    detail: '第 ${progress.round} 轮 · ${progress.itemCount} 项',
                  ),
                  sleep: (delay) async {
                    await Future<void>.delayed(delay);
                    check();
                  },
                ).synchronize().timeout(
                  const Duration(minutes: 2),
                  onTimeout: () {
                    expired = true;
                    files.cancelRequests();
                    throw TimeoutException('账号云同步超时');
                  },
                );
            check();
            if (result.failure != null) throw result.failure!;
            if (!result.completed) throw StateError('还有私人数据待同步');
          });
          check();
          // Only reaction changes imported by private sync need a public run.
          if (local.publicFingerprint != before &&
              local.publicFingerprint !=
                  publicReactions?.confirmedFingerprint) {
            unawaited(_publishReactions());
          }
          await controller.waitForAccountCloudData(scope);
          _check(generation);
          await local.capture(check: () => _check(generation));
          check();
          _privateAgain = _privateAgain || local.hasPendingOperations;
          if (++rounds >= 3 && _privateAgain) {
            throw StateError('还有私人数据待同步');
          }
        } while (_privateAgain);
        lastSuccess = DateTime.now();
        if (!await (await SharedPreferences.getInstance()).setString(
          'account_cloud_last_success.$scope',
          lastSuccess!.toIso8601String(),
        )) {
          throw StateError('同步状态保存失败');
        }
        _check(generation);
        status = AccountCloudStatus.synced;
        trace.finish(detail: '私人增量日志已确认，包含本轮捕获的收藏变更');
      } catch (failure) {
        trace.finish(
          failed: true,
          detail: ReactionSyncDiagnostics.failureLabel(failure),
        );
        if (_active && generation == _generation) {
          status = AccountCloudStatus.pending;
          final cause = failure is WebDavException ? failure.cause : failure;
          error = switch (cause) {
            PrivateFileException(failure: PrivateFileFailure.missing) =>
              '私人目录初始化未完成，请检查 home 后重试。本机数据已保留。',
            PrivateFileException(failure: PrivateFileFailure.denied) =>
              '群晖私有目录无访问权限，本机数据已保留。请检查 home 权限后重试。',
            PrivateFileException(failure: PrivateFileFailure.session) =>
              '登录已过期，本机数据已保留。请重新登录后同步。',
            PrivateFileException(failure: PrivateFileFailure.quota) =>
              '群晖存储空间不足，本机数据已保留。请腾出空间后重试。',
            _ =>
              failure is SyncProtocolException || failure is FormatException
                  ? '私人同步数据需要检查，本机数据已保留。请重试。'
                  : '私人资料未同步，本机数据已保留。请重试。',
          };
        }
      } finally {
        _privateOperation = null;
        done.complete();
        _notify();
      }
    }());
    return done.future;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    _poll?.cancel();
    _publicationRetry?.cancel();
    _rankingRetry?.cancel();
    controller.removeListener(_changed);
    files.cancelRequests();
    publicReactions?.cancel();
    super.dispose();
  }
}

/// Reject callbacks from timed-out/stopped private runs before touching a store.
final class _CheckedLocalStore implements SyncLocalStore {
  _CheckedLocalStore(this.local, this.check, this.waitForIdle);
  final AccountSyncLocalStore local;
  final void Function() check;
  final Future<void> Function() waitForIdle;
  @override
  String get deviceId {
    check();
    return local.deviceId;
  }

  @override
  Future<SyncCheckpoint> loadCheckpoint() async {
    check();
    final result = await local.loadCheckpoint();
    check();
    return result;
  }

  @override
  Future<void> saveCheckpoint(SyncCheckpoint checkpoint) async {
    check();
    await local.saveCheckpoint(checkpoint, check: check);
    check();
  }

  @override
  Future<List<SyncOperation>> pendingOperations({
    required int afterSequence,
    int limit = 500,
  }) async {
    check();
    final result = await local.pendingOperations(
      afterSequence: afterSequence,
      limit: limit,
    );
    check();
    return result;
  }

  @override
  Future<SyncApplyResult> applyRemoteOperations({
    required Iterable<SyncOperation> operations,
    required SyncCursor currentCursor,
  }) async {
    check();
    await waitForIdle();
    check();
    final result = await local.applyRemoteOperations(
      operations: operations,
      currentCursor: currentCursor,
      check: check,
    );
    check();
    return result;
  }
}

/// Check each transport boundary as well as local journal callbacks. Cancelling
/// a request must not allow a late listing to start more reads or uploads.
final class _CheckedPrivateFiles implements AccountPrivateFiles {
  _CheckedPrivateFiles(this.files, this.check);
  final AccountPrivateFiles files;
  final void Function() check;
  Future<T> _call<T>(Future<T> Function() work) async {
    check();
    final result = await work();
    check();
    return result;
  }

  @override
  void cancelRequests() => files.cancelRequests();
  @override
  Future<List<({String name, bool directory})>> list(String path) =>
      _call(() => files.list(path));
  @override
  Future<String> read(String path) => _call(() => files.read(path));
  @override
  Future<void> createImmutable(String path, String content) =>
      _call(() => files.createImmutable(path, content));
}
