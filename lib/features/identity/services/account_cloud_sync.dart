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
  Timer? _debounce, _poll, _publicRetry;
  Future<void>? _privateOperation, _publicOperation;
  bool _privateAgain = false, _publicAgain = false;
  int _localBusy = 0, _publicAttempts = 0;
  bool publicSyncing = false;
  bool publicSynced = false;
  bool _disposed = false;
  int _generation = 0;
  bool enabled = true;
  AccountCloudStatus status = AccountCloudStatus.idle;
  String? error, publicError;
  DateTime? lastSuccess;
  String get _enabledKey => 'account_cloud_enabled.$scope';
  bool get _active => !_disposed && enabled && isActive();
  bool get syncing => _privateOperation != null || _publicOperation != null;
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
    // Reactions bypass this debounce through refreshPublic after durable save.
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
    error = publicError = null;
    if (!value) {
      _generation++;
      _debounce?.cancel();
      _publicRetry?.cancel();
      _privateAgain = _publicAgain = false;
      files.cancelRequests();
      publicReactions?.cancel();
      status = AccountCloudStatus.paused;
      controller.gameVotes.pausePublicSync();
      controller.favoriteStatistics.pausePublicSync();
    }
    _notify();
    if (value) {
      await Future.wait([?_privateOperation, ?_publicOperation]);
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

  /// Manual sync and polling join both lanes; a private failure never fails a
  /// ranking request. Completed uploads remain acknowledged in the journal.
  Future<void> synchronize() async {
    if (!_active) return;
    await Future.wait([_refreshPublic(), _syncPrivate()]);
    // A private import may have queued a new public projection after the first
    // public read finished. Include that projection in the same user task.
    await _publicOperation;
  }

  Future<void> retry() async {
    if (!_active) return;
    if (error == null && publicError == null) return synchronize();
    await Future.wait([
      if (error != null) _syncPrivate(),
      if (publicError != null) _refreshPublic(),
    ]);
  }

  /// Called immediately after saving a reaction, and on ranking entry/refresh.
  /// In-flight public requests coalesce; a changed selection gets a follow-up.
  Future<void> refreshPublic() async {
    if (!_active) return;
    _publicAttempts = 0;
    await _refreshPublic();
    if (!_active) return;
    if (publicError != null) throw StateError(publicError!);
  }

  Future<void> _refreshPublic() {
    if (!_active || publicReactions == null) return Future.value();
    if (_publicOperation != null) {
      _publicAgain = true;
      return _publicOperation!;
    }
    _publicRetry?.cancel();
    final done = Completer<void>();
    _publicOperation = done.future;
    publicSyncing = true;
    publicError = null;
    publicReactions!.error = null;
    controller.gameVotes.beginPublicSync();
    controller.favoriteStatistics.beginPublicSync();
    _notify();
    final generation = _generation;
    unawaited(() async {
      try {
        final local = await _local();
        var rounds = 0;
        do {
          _publicAgain = false;
          _check(generation);
          await local.captureReactions(check: () => _check(generation));
          _check(generation);
          if (local.hasPendingOperations) unawaited(_syncPrivate());
          await publicReactions!
              .synchronize(local)
              .timeout(
                const Duration(seconds: 20),
                onTimeout: () {
                  publicReactions!.cancel();
                  throw TimeoutException('公共同步超时');
                },
              );
          _check(generation);
          final voteRevision = controller.gameVotes.selectionRevision;
          final favoriteRevision =
              controller.favoriteStatistics.selectionRevision;
          await controller.gameVotes.acceptPublicCounts(
            'account-public-v1.$scope',
            publicReactions!.counts(GameVoteBallot.campaign),
            check: () => _check(generation),
            revision: voteRevision,
          );
          _check(generation);
          await controller.favoriteStatistics.acceptPublicCounts(
            'account-public-v1.$scope',
            publicReactions!.counts(GameVoteBallot.favoritesNamespace),
            check: () => _check(generation),
            revision: favoriteRevision,
          );
          _check(generation);
          publicSynced = true;
          // Check again after caching, because a click can arrive in either lane.
          await local.captureReactions(check: () => _check(generation));
          _check(generation);
          _publicAgain =
              local.publicFingerprint != publicReactions!.confirmedFingerprint;
          if (++rounds >= 3 && _publicAgain) {
            throw StateError('仍有新变更待同步');
          }
        } while (_publicAgain);
        _publicAttempts = 0;
      } catch (failure) {
        if (_active && generation == _generation) {
          final submitted =
              publicReactions!.confirmedFingerprint != null &&
              publicReactions!.confirmsSelection(
                GameVoteBallot.campaign,
                controller.gameVotes.selectedGames,
              ) &&
              publicReactions!.confirmsSelection(
                GameVoteBallot.favoritesNamespace,
                controller.favoriteStatistics.selectedGames,
              );
          publicError = submitted
              ? '收藏与投票已提交，排行刷新失败，请重试。'
              : publicReactions!.error ??
                    (failure is FormatException ||
                            failure is SyncProtocolException
                        ? '本机或云端统计数据需要检查，本机数据已保留。请重试。'
                        : '已保存在本机，待同步。请重试。');
          controller.gameVotes.markPublicFailure();
          controller.favoriteStatistics.markPublicFailure();
          if (_publicAttempts < 2) {
            _publicRetry = Timer(
              Duration(seconds: _publicAttempts++ == 0 ? 3 : 10),
              () => unawaited(_refreshPublic()),
            );
          }
        }
      } finally {
        publicSyncing = false;
        _publicOperation = null;
        done.complete();
        _notify();
      }
    }());
    return done.future;
  }

  Future<void> _syncPrivate() {
    if (!_active) return Future.value();
    if (!controller.accountCloudIdle && _privateOperation == null) {
      status = AccountCloudStatus.idle;
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
    unawaited(() async {
      try {
        final local = await _local();
        var rounds = 0;
        do {
          _privateAgain = false;
          _check(generation);
          await controller.waitForAccountCloudData(scope);
          _check(generation);
          await local.capture(check: () => _check(generation));
          _check(generation);
          final before = local.publicFingerprint;
          var expired = false;
          void check() {
            _check(generation);
            if (expired) throw const SyncProtocolException('私人同步已超时');
          }

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
          // Only reaction changes imported by private sync need a public run.
          if (local.publicFingerprint != before &&
              local.publicFingerprint !=
                  publicReactions?.confirmedFingerprint) {
            unawaited(_refreshPublic());
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
      } catch (failure) {
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
    _publicRetry?.cancel();
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
