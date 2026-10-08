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
  AccountSyncLocalStore? _local;
  int? _localGeneration;
  Timer? _debounce, _poll;
  Future<void>? _operation;
  Completer<void>? _publicReady;
  bool publicSyncing = false;
  bool publicSynced = false;
  bool _publicAttempted = false;
  bool _disposed = false;
  int _generation = 0;
  bool enabled = true;
  AccountCloudStatus status = AccountCloudStatus.idle;
  String? error;
  DateTime? lastSuccess;
  String get _enabledKey => 'account_cloud_enabled.$scope';
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
    notifyListeners();
    unawaited(synchronize());
  }

  void _changed() {
    if (_disposed || _operation != null || !controller.accountCloudIdle) {
      return;
    }
    _debounce?.cancel();
    if (status == AccountCloudStatus.synced) {
      status = AccountCloudStatus.idle;
      notifyListeners();
    }
    _debounce = Timer(
      const Duration(seconds: 4),
      () => unawaited(synchronize()),
    );
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
    error = null;
    if (!value) {
      _generation++;
      _debounce?.cancel();
      files.cancelRequests();
      publicReactions?.cancel();
      status = AccountCloudStatus.paused;
    }
    notifyListeners();
    if (value) {
      await _operation;
      if (enabled && !_disposed) unawaited(synchronize());
    }
  }

  Future<void> synchronize() {
    if (_operation != null) return _operation!;
    final done = Completer<void>();
    _publicReady = Completer<void>();
    _publicAttempted = false;
    // Install the barrier before callbacks in _run can notify listeners.
    _operation = done.future;
    unawaited(() async {
      try {
        await _run();
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        if (!_publicReady!.isCompleted) _publicReady!.complete();
        _operation = null;
      }
    }());
    return done.future;
  }

  Future<void> refreshPublic() async {
    if (_operation != null && _publicReady?.isCompleted == true) {
      throw StateError('账号同步正在进行，请稍后刷新公共统计');
    }
    if (_disposed || !isActive()) throw StateError('账号已切换');
    if (_operation == null) unawaited(synchronize());
    await _publicReady!.future;
    if (!_publicAttempted ||
        publicReactions == null ||
        publicReactions!.error != null ||
        _disposed ||
        !isActive()) {
      throw StateError('公共同步未完成');
    }
  }

  Future<void> _syncPublic(AccountSyncLocalStore local) async {
    final reactions = publicReactions;
    if (reactions == null || _disposed || !isActive()) return;
    _publicAttempted = true;
    publicSyncing = true;
    notifyListeners();
    try {
      await reactions
          .synchronize(local)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              reactions.cancel();
              reactions.error = '公共同步超时，已保留上次统计。';
              throw TimeoutException('公共同步超时');
            },
          );
      if (_disposed || !isActive()) return;
      final publicScope = 'account-public-v1.$scope';
      final votes = controller.gameVotes;
      final favorites = controller.favoriteStatistics;
      await votes.acceptPublicCounts(
        publicScope,
        reactions.counts(GameVoteBallot.campaign),
      );
      if (_disposed || !isActive()) return;
      await favorites.acceptPublicCounts(
        publicScope,
        reactions.counts(GameVoteBallot.favoritesNamespace),
      );
      if (_disposed || !isActive()) return;
      publicSynced = true;
    } catch (_) {
      reactions.error ??= '公共同步未完成，已保留本机数据和上次统计。';
      if (!_disposed && isActive()) {
        controller.gameVotes.markPublicFailure();
        controller.favoriteStatistics.markPublicFailure();
      }
    } finally {
      publicSyncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _run() async {
    if (_disposed || !isActive() || !controller.accountCloudIdle) {
      return;
    }
    _debounce?.cancel();
    status = enabled ? AccountCloudStatus.syncing : AccountCloudStatus.paused;
    error = null;
    notifyListeners();
    try {
      final generation = _generation;
      void check() {
        if (_disposed || !isActive() || generation != _generation) {
          throw const SyncProtocolException('同步已停止');
        }
      }

      if (_localGeneration != generation) _local = null;

      final local =
          _local ??
          AccountSyncLocalStore(
            datasetId: scope,
            transaction: <T>(work) async {
              check();
              return controller.accountCloudTransaction<T>(scope, (
                current,
                project,
              ) async {
                check();
                return work(current, (entities) async {
                  check();
                  await project(entities);
                });
              });
            },
          );
      if (_local == null) {
        await local.initialize();
        check();
        _local = local;
        _localGeneration = generation;
      }
      await local.capture();
      check();
      await _syncPublic(local);
      check();
      if (!_publicReady!.isCompleted) _publicReady!.complete();
      if (!enabled) return;
      final result =
          await IncrementalSyncEngine(
            local: local,
            remote: AccountSyncRemoteStore(files: files, datasetId: scope),
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
              _generation++;
              files.cancelRequests();
              throw TimeoutException('账号云同步超时');
            },
          );
      check();
      if (result.failure != null) throw result.failure!;
      if (!result.completed) {
        status = AccountCloudStatus.pending;
        error = '还有数据待同步，将自动继续。本机数据已保存。';
        return;
      }
      lastSuccess = DateTime.now();
      if (!await (await SharedPreferences.getInstance()).setString(
        'account_cloud_last_success.$scope',
        lastSuccess!.toIso8601String(),
      )) {
        throw StateError('同步状态保存失败');
      }
      status = AccountCloudStatus.synced;
    } catch (failure) {
      if (!_disposed && enabled) {
        status = AccountCloudStatus.pending;
        final cause = failure is WebDavException ? failure.cause : null;
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
                ? '云端或本机同步数据需要检查，本机数据已保留。请重试。'
                : '云同步未完成，本机数据已保留。请检查网络后重试。',
        };
      }
    } finally {
      final local = _local;
      if (!_disposed &&
          isActive() &&
          enabled &&
          status == AccountCloudStatus.synced &&
          local != null &&
          publicReactions != null &&
          publicReactions!.error == null &&
          controller.accountCloudIdle) {
        try {
          await local.capture();
          await _syncPublic(local);
        } catch (_) {
          // Public failure never rolls back durable private data or cached counts.
        }
      }
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    _poll?.cancel();
    controller.removeListener(_changed);
    files.cancelRequests();
    publicReactions?.cancel();
    super.dispose();
  }
}
