import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../settings/services/preferences_service.dart';
import '../models/game_vote_record.dart';
import 'webdav_game_vote_store.dart';

enum GameVoteSyncStatus { localOnly, syncing, synced, pending }

/// Durable local votes are independent from favorites and remote availability.
class GameVoteService extends ChangeNotifier {
  GameVoteService({required this.preferences, this.remoteProvider});
  final PreferencesService preferences;
  final RemoteGameVoteStore? Function()? remoteProvider;
  GameVoteCache? _cache;
  Future<void>? _loadFuture;
  Future<void>? _syncFuture;
  Future<void> _writes = Future.value();
  RemoteGameVoteStore? _activeRemote;
  Timer? _retry;
  bool _disposed = false;
  bool saving = false;
  String? loadError;
  String? _scope;
  int _revision = 0;
  int _retryCount = 0;
  GameVoteSyncStatus status = GameVoteSyncStatus.localOnly;
  bool get ready => _cache != null && loadError == null;
  bool hasVoted(String slug) => _cache?.ballot.games.contains(slug) ?? false;
  int count(String slug) =>
      (_cache?.remoteCounts[_scope]?[slug] ?? 0) + (hasVoted(slug) ? 1 : 0);

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final raw = await preferences.loadGameVoteCache();
      if (_disposed) return;
      if (raw != null) {
        _cache = GameVoteCache.decode(raw);
      } else {
        final random = Random.secure();
        final id = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        final initial = GameVoteCache(
          ballot: GameVoteBallot(deviceId: id, games: []),
        );
        await preferences.saveGameVoteCache(initial.encode());
        if (_disposed) return;
        _cache = initial;
      }
      loadError = null;
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
          ),
          remoteCounts: current.remoteCounts,
        );
        await preferences.saveGameVoteCache(next.encode());
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

  Future<void> _sync() async {
    await load();
    if (_disposed || !ready) return;
    RemoteGameVoteStore? remote;
    final revision = _revision;
    var changedEndpoint = false;
    try {
      remote = remoteProvider?.call();
      _scope = remote?.scope;
      if (remote == null) {
        status = GameVoteSyncStatus.localOnly;
        _notify();
        return;
      }
      _activeRemote = remote;
      status = GameVoteSyncStatus.syncing;
      _notify();
      final own = _cache!.ballot;
      final ballots = await (() async {
        await remote!.upload(own);
        return remote.readBallots();
      })().timeout(const Duration(seconds: 25));
      if (_disposed) return;
      final currentRemote = remoteProvider?.call();
      changedEndpoint = currentRemote?.scope != remote.scope;
      currentRemote?.close();
      if (changedEndpoint) return;
      final totals = <String, int>{};
      final seen = <String>{};
      for (final ballot in ballots) {
        if (ballot.deviceId == own.deviceId || !seen.add(ballot.deviceId)) {
          continue;
        }
        for (final slug in ballot.games) {
          totals[slug] = (totals[slug] ?? 0) + 1;
        }
      }
      final scope = remote.scope;
      await _serialize(() async {
        if (_disposed) return;
        final next = GameVoteCache(
          ballot: _cache!.ballot,
          remoteCounts: {..._cache!.remoteCounts, scope: totals},
        );
        await preferences.saveGameVoteCache(next.encode());
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
