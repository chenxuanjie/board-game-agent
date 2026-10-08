import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../settings/services/preferences_service.dart';
import '../models/game_vote_record.dart';
import 'remote_game_vote_store.dart';

enum GameVoteSyncStatus { localOnly, syncing, synced, pending }

/// Durable local votes are independent from favorites and remote availability.
class GameVoteService extends ChangeNotifier {
  GameVoteService({
    required this.preferences,
    this.remoteProvider,
    this.namespace = GameVoteBallot.campaign,
    this.externalGames,
    this.scopeProvider,
    this.cacheLoader,
    this.cacheSaver,
  });
  final PreferencesService preferences;
  final RemoteGameVoteStore? Function()? remoteProvider;
  final String namespace;

  /// Favorites use the controller's durable collection as their source of truth.
  /// Null means that collection failed to load and must not be uploaded empty.
  final Iterable<String>? Function()? externalGames;
  final String? Function()? scopeProvider;
  final Future<String?> Function()? cacheLoader;
  final Future<void> Function(String value)? cacheSaver;
  Future<String?> _readCache() =>
      (cacheLoader ?? preferences.loadGameVoteCache)();
  Future<void> _saveCache(String value) =>
      (cacheSaver ?? preferences.saveGameVoteCache)(value);
  GameVoteCache? _cache;
  Future<void>? _loadFuture;
  Future<void>? _syncFuture;
  Future<void> _writes = Future.value();
  RemoteGameVoteStore? _activeRemote;
  Timer? _retry;
  bool _disposed = false;
  bool saving = false;
  bool Function()? canMutate;
  VoidCallback? onSaved;
  String? loadError;
  String? Function()? accountSyncError;
  bool Function()? cachedCountVisibility;
  String? get syncError => accountSyncError?.call();
  String? _scope;
  int _revision = 0;
  int _retryCount = 0;
  GameVoteSyncStatus status = GameVoteSyncStatus.localOnly;
  bool get ready => _cache != null && loadError == null;
  bool get hasCachedRemoteCounts =>
      cachedCountVisibility?.call() != false &&
      (_cache?.remoteCounts.containsKey(
            accountScopeProvider?.call() ?? scopeProvider?.call() ?? _scope,
          ) ??
          false);
  bool hasVoted(String slug) =>
      (externalGames?.call() ?? _cache?.ballot.games)?.contains(slug) ?? false;
  int count(String slug) =>
      (cachedCountVisibility?.call() == false
          ? 0
          : (_cache?.remoteCounts[accountScopeProvider?.call() ??
                    scopeProvider?.call() ??
                    _scope]?[slug] ??
                0)) +
      (hasVoted(slug) ? 1 : 0);

  void externalSelectionChanged() {
    if (_disposed || externalGames == null) return;
    _revision++;
    _retryCount = 0;
    _notify();
    unawaited(sync());
  }

  Future<void> load() => _loadFuture ??= _load();

  Future<void> reload() async {
    if (_disposed || saving) throw StateError('投票数据暂忙');
    _loadFuture = null;
    await load();
  }

  Future<void> acceptPublicCounts(String scope, Map<String, int> counts) async {
    await load();
    await _serialize(() async {
      if (_disposed || !ready) return;
      final next = GameVoteCache(
        ballot: _cache!.ballot,
        remoteCounts: {..._cache!.remoteCounts, scope: Map.of(counts)},
        lastScope: scope,
      );
      await _saveCache(next.encode());
      if (_disposed) return;
      _cache = next;
      _scope = scope;
      status = GameVoteSyncStatus.synced;
      _notify();
    });
  }

  void configureRemote(
    RemoteGameVoteStore? Function()? provider,
    String? Function()? scope,
  ) {
    accountRemoteProvider = provider;
    accountScopeProvider = scope;
  }

  RemoteGameVoteStore? Function()? accountRemoteProvider;
  String? Function()? accountScopeProvider;

  Future<void> _load() async {
    try {
      final raw = await _readCache();
      if (_disposed) return;
      if (raw != null) {
        _cache = GameVoteCache.decode(raw, namespace: namespace);
      } else {
        final random = Random.secure();
        final id = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        final initial = GameVoteCache(
          ballot: GameVoteBallot(deviceId: id, games: [], namespace: namespace),
        );
        await _saveCache(initial.encode());
        if (_disposed) return;
        _cache = initial;
      }
      loadError = null;
      _scope =
          accountScopeProvider?.call() ??
          scopeProvider?.call() ??
          _cache?.lastScope;
    } catch (_) {
      loadError = '投票读取失败，请重试';
      _loadFuture = null;
    }
    _notify();
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// The pressed state changes only after the local write succeeds.
  Future<bool> toggle(String slug) async {
    if (_disposed ||
        canMutate?.call() == false ||
        externalGames != null ||
        saving ||
        !ready ||
        !GameVoteBallot.slugPattern.hasMatch(slug)) {
      return false;
    }
    saving = true;
    _notify();
    var saved = false;
    try {
      await _serialize(() async {
        final current = _cache!;
        final games = {...current.ballot.games};
        games.contains(slug) ? games.remove(slug) : games.add(slug);
        if (games.length > 256) throw StateError('Ballot limit exceeded');
        final next = GameVoteCache(
          ballot: GameVoteBallot(
            deviceId: current.ballot.deviceId,
            games: games,
            namespace: namespace,
          ),
          remoteCounts: current.remoteCounts,
          lastScope: current.lastScope,
        );
        await _saveCache(next.encode());
        if (_disposed) return;
        _cache = next;
        _revision++;
        saved = true;
      });
    } catch (_) {
      saved = false;
    } finally {
      saving = false;
      _notify();
    }
    if (saved) {
      onSaved?.call();
      _retryCount = 0;
      unawaited(sync());
    }
    return saved;
  }

  /// Coalesce refreshes; a newer local vote gets another upload after this run.
  Future<void> sync() {
    if (_disposed) return Future.value();
    _retry?.cancel();
    if (_syncFuture != null) return _syncFuture!;
    final future = _sync();
    _syncFuture = future;
    return future.whenComplete(() {
      _syncFuture = null;
    });
  }

  void markPublicFailure() {
    if (_disposed) return;
    status = GameVoteSyncStatus.pending;
    _notify();
  }

  Future<void> _sync() async {
    await load();
    if (_disposed || !ready) return;
    RemoteGameVoteStore? remote;
    final revision = _revision;
    var changedEndpoint = false;
    try {
      final selection = externalGames?.call();
      if (externalGames != null && selection == null) {
        status = GameVoteSyncStatus.pending;
        _notify();
        return;
      }
      remote = accountRemoteProvider?.call() ?? remoteProvider?.call();
      _scope =
          remote?.scope ??
          accountScopeProvider?.call() ??
          scopeProvider?.call() ??
          (externalGames != null ? _cache?.lastScope : null);
      final own = externalGames == null
          ? _cache!.ballot
          : GameVoteBallot(
              deviceId: _cache!.ballot.deviceId,
              games: selection!,
              namespace: namespace,
            );
      if (own.games.any((slug) => !GameVoteBallot.slugPattern.hasMatch(slug)) ||
          own.games.length >
              (namespace == GameVoteBallot.favoritesNamespace ? 2048 : 256)) {
        throw const FormatException('Invalid reaction selection');
      }
      if (externalGames != null) {
        await _serialize(() async {
          if (_disposed) return;
          final next = GameVoteCache(
            ballot: own,
            remoteCounts: _cache!.remoteCounts,
            lastScope: _scope,
          );
          await _saveCache(next.encode());
          if (!_disposed) _cache = next;
        });
        if (_disposed) return;
      }
      if (remote == null) {
        status = GameVoteSyncStatus.localOnly;
        _notify();
        return;
      }
      _activeRemote = remote;
      status = GameVoteSyncStatus.syncing;
      _notify();
      final ballots = await (() async {
        await remote!.upload(own);
        return remote.readBallots();
      })().timeout(const Duration(seconds: 25));
      if (_disposed) return;
      final currentRemote =
          accountRemoteProvider?.call() ?? remoteProvider?.call();
      changedEndpoint = currentRemote?.scope != remote.scope;
      currentRemote?.close();
      if (changedEndpoint) return;
      final totals = <String, int>{};
      final seen = <String>{};
      for (final ballot in ballots) {
        if (ballot.namespace != namespace ||
            ballot.deviceId == own.deviceId ||
            !seen.add(ballot.deviceId)) {
          continue;
        }
        for (final slug in ballot.games) {
          totals[slug] = (totals[slug] ?? 0) + 1;
          if (totals.length > 32768) {
            throw StateError('Reaction count limit exceeded');
          }
        }
      }
      final scope = remote.scope;
      await _serialize(() async {
        if (_disposed) return;
        final next = GameVoteCache(
          ballot: _cache!.ballot,
          remoteCounts: {..._cache!.remoteCounts, scope: totals},
          lastScope: scope,
        );
        await _saveCache(next.encode());
        if (!_disposed) _cache = next;
      });
      if (_disposed) return;
      status = revision == _revision
          ? GameVoteSyncStatus.synced
          : GameVoteSyncStatus.pending;
      _retryCount = 0;
    } catch (_) {
      if (_disposed) return;
      status = GameVoteSyncStatus.pending;
      if (_retryCount < 2) {
        _retry = Timer(
          Duration(seconds: _retryCount++ == 0 ? 3 : 10),
          () => unawaited(sync()),
        );
      }
    } finally {
      remote?.close();
      _activeRemote = null;
      _notify();
      if (!_disposed && (revision != _revision || changedEndpoint)) {
        // Run only after the coalescing future has cleared.
        _retry?.cancel();
        _retry = Timer(Duration.zero, () => unawaited(sync()));
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retry?.cancel();
    _activeRemote?.close();
    super.dispose();
  }
}
