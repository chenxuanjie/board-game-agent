import 'dart:async';
import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/game_comment.dart';

/// Public reads and authenticated, durable idempotent commands are independent.
/// Each instance is pinned to its service/account; late work cannot cross it.
final class GameCommentsService extends ChangeNotifier {
  GameCommentsService({
    required this.client,
    required this.scope,
    required this.isActive,
    required this.displayName,
    this.token,
    this.uid = '',
  });
  final AppJsonClient client;
  final String scope, uid;
  final bool Function() isActive;
  final String Function() displayName;
  final Future<String> Function()? token;
  bool get readOnly => token == null;
  bool get canWrite => !readOnly && !_disposed && isActive();
  final _games = <String>{};
  final _watchCounts = <String, int>{};
  final _requestedGames = <String>{};
  final _rows = <String, Map<String, dynamic>>{};
  final _commands = <Map<String, dynamic>>[];
  final _optimistic = <String, Map<String, dynamic>>{};
  final _likes = <String, bool>{};
  Future<void>? _ready, _sync;
  Future<void>? _writes;
  final _pendingDrafts = <String, String?>{};
  bool _stateDirty = false;
  SharedPreferences? _prefs;
  bool _disposed = false, loading = false;
  String? error;
  Timer? _retry;
  int _attempts = 0;
  String get _key => 'board.community.api.v1.$scope';
  bool get pending => _commands.isNotEmpty;
  Set<String> get pendingIds => {
    for (final c in _commands)
      if (c['action'] == 'publish') c['comment_id'] as String,
  };
  bool get onlyLikesPending =>
      pending && _commands.every((c) => c['action'] == 'like');
  bool likePending(String id) =>
      _commands.any((c) => c['action'] == 'like' && c['comment_id'] == id);
  bool? optimisticLike(String id) => _likes[id];
  bool likeInFlight(String id) => loading && likePending(id);
  CommentProjection get projection =>
      CommentProjection({..._rows, ..._optimistic}.values);
  static String newId([String prefix = 'c']) =>
      '$prefix${const Uuid().v4().replaceAll('-', '')}';
  void watchGame(String slug) {
    if (!CommentOperation.gamePattern.hasMatch(slug)) return;
    _watchCounts[slug] = (_watchCounts[slug] ?? 0) + 1;
    _games.add(slug);
  }

  void unwatchGame(String slug) {
    final count = _watchCounts[slug] ?? 0;
    if (count > 1) {
      _watchCounts[slug] = count - 1;
      return;
    }
    _watchCounts.remove(slug);
    if (!_commands.any((command) => command['game_slug'] == slug)) {
      _games.remove(slug);
      _requestedGames.remove(slug);
    }
  }

  Set<String> get watchedGames => Set.unmodifiable(_watchCounts.keys);

  Future<void> refreshGames(Iterable<String> changed) {
    _requestedGames.addAll(changed.where(_watchCounts.containsKey));
    return _requestedGames.isEmpty ? Future.value() : _startSync();
  }

  void _check() {
    if (_disposed || !isActive()) throw StateError('账号已切换');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _ready ??= (() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    _commands.addAll((data['commands'] as List).cast<Map<String, dynamic>>());
    _games.addAll(_commands.map((command) => command['game_slug'] as String));
    for (final r in (data['optimistic'] as List).cast<Map<String, dynamic>>()) {
      _optimistic[r['id'] as String] = r;
    }
  })();
  Future<void> _local(Future<void> Function() work) {
    final next = (_writes ?? Future<void>.value()).then((_) async {
      if (_disposed) throw StateError('评论服务已关闭');
      await work();
    });
    // The scheduler stays usable; callers still receive their own failure.
    // Pending payloads, rather than a rejected Future, govern handoff safety.
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _writes = tail;
    tail.then((_) {
      if (identical(_writes, tail)) _writes = null;
    });
    return next;
  }

  Future<void> _save() async {
    _stateDirty = true;
    final raw = jsonEncode({
      'commands': _commands,
      'optimistic': _optimistic.values.toList(),
    });
    if (utf8.encode(raw).length > 512 * 1024 ||
        !await _prefs!.setString(_key, raw)) {
      throw StateError('待发送内容未保存，请重试');
    }
    _stateDirty = false;
  }

  Future<void> _enqueue(
    Map<String, dynamic> command, {
    Map<String, dynamic>? optimistic,
  }) async {
    await initialize();
    await _local(() async {
      if (!canWrite) throw StateError('请先登录');
      final old = _commands.where((c) => c['id'] == command['id']).firstOrNull;
      if (old != null) {
        if (jsonEncode(old) != jsonEncode(command)) throw StateError('请先重试原内容');
        return;
      }
      _commands.add(command);
      if (optimistic != null) {
        _optimistic[optimistic['id'] as String] = optimistic;
      }
      try {
        await _save();
      } catch (_) {
        _commands.remove(command);
        if (optimistic != null) _optimistic.remove(optimistic['id']);
        rethrow;
      }
      _games.add(command['game_slug'] as String);
      _notify();
    });
  }

  Future<String> publish({
    required String game,
    required String text,
    int? rating,
    String? parent,
    String? operationId,
  }) async {
    final id = operationId ?? newId();
    if (!CommentOperation.gamePattern.hasMatch(game) ||
        !CommentOperation.idPattern.hasMatch(id) ||
        text.trim().isEmpty ||
        text.contains('\u0000') ||
        text.length > 1000 ||
        (rating != null && (rating < 1 || rating > 10))) {
      throw StateError('评论内容无效');
    }
    final root = parent == null ? null : projection.comments[parent];
    await _enqueue(
      {
        'id': id,
        'action': 'publish',
        'game_slug': game,
        'comment_id': id,
        'body': text.trim(),
        'rating': rating,
        'parent_id': parent,
      },
      optimistic: {
        'id': id,
        'author_id': uid,
        'game_slug': game,
        'author': displayName(),
        'text': text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'parent_id': parent,
        'root_id': root == null ? null : root.root ?? root.id,
        'rating': rating,
        'deleted': false,
        'likes': 0,
        'liked_by_me': false,
      },
    );
    return id;
  }

  Future<void> delete(GameComment comment) async {
    if (comment.operation.uid != uid) throw StateError('只能删除自己的评论');
    await _enqueue({
      'id': const Uuid().v4(),
      'action': 'delete',
      'game_slug': comment.operation.game,
      'comment_id': comment.id,
    });
    await synchronize();
  }

  Future<void> toggleLike(GameComment comment) async {
    if (likeInFlight(comment.id)) return;
    final desired = !(_likes[comment.id] ?? comment.likedByMe);
    _likes[comment.id] = desired;
    try {
      await _enqueue({
        'id': const Uuid().v4(),
        'action': 'like',
        'game_slug': comment.operation.game,
        'comment_id': comment.id,
        'active': desired,
      });
      await synchronize();
    } finally {
      _likes.remove(comment.id);
      _notify();
    }
  }

  Future<void> synchronize() {
    _requestedGames.addAll(_games);
    return _startSync();
  }

  Future<void> _startSync() {
    if (_disposed) return Future.value();
    return _sync ??=
        (() async {
          // Drain changes received during a read as a fresh follow-up snapshot.
          // Keep one in-flight request set, bounded even for a continuously busy feed.
          for (var pass = 0; pass < 8; pass++) {
            final games = Set<String>.of(_requestedGames);
            _requestedGames.clear();
            await _synchronize(games);
            if (error != null ||
                _disposed ||
                !isActive() ||
                _requestedGames.isEmpty) {
              break;
            }
          }
        })().whenComplete(() {
          _sync = null;
          if (!_disposed &&
              isActive() &&
              error == null &&
              _requestedGames.isNotEmpty) {
            _retry = Timer(
              const Duration(milliseconds: 250),
              () => unawaited(_startSync()),
            );
          }
        });
  }

  Future<void> _synchronize(Set<String> games) async {
    loading = true;
    error = null;
    _retry?.cancel();
    _notify();
    try {
      await initialize();
      _check();
      for (var n = 0; n < 100 && _commands.isNotEmpty; n++) {
        final command = _commands.first;
        final response = await client.request(
          '/v1/community/commands',
          token: await token!(),
          body: command,
        );
        _check();
        if (response['id'] != command['id'] ||
            response['status'] != 'applied') {
          throw StateError('Invalid acknowledgement');
        }
        await _local(() async {
          _check();
          _commands.removeAt(0);
          try {
            await _save();
          } catch (_) {
            _commands.insert(0, command);
            rethrow;
          }
        });
      }
      for (final game in games) {
        final next = <String, Map<String, dynamic>>{};
        String? cursor;
        for (var page = 0; page < 100; page++) {
          final response = await client.request(
            '/v1/community/comments/$game?limit=200${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
            get: true,
            token: token == null ? null : await token!(),
          );
          _check();
          for (final r
              in (response['comments'] as List).cast<Map<String, dynamic>>()) {
            next[r['id'] as String] = r;
          }
          cursor = response['next_cursor'] as String?;
          if (cursor == null) break;
          if (page == 99) throw StateError('评论数量超过单次刷新上限');
        }
        _rows.removeWhere((_, r) => r['game_slug'] == game);
        _rows.addAll(next);
        _optimistic.removeWhere(
          (id, r) => r['game_slug'] == game && !pendingIds.contains(id),
        );
      }
      await _local(_save);
      _games.removeWhere(
        (game) =>
            !_watchCounts.containsKey(game) &&
            !_commands.any((command) => command['game_slug'] == game),
      );
      _attempts = 0;
    } catch (_) {
      if (!_disposed && isActive()) {
        error = pending ? '发送未完成，本机内容已保留，请重试' : '评论刷新未完成，请重试';
        if (pending && _attempts < 4) {
          _retry = Timer(
            Duration(seconds: 2 << _attempts++),
            () => unawaited(synchronize()),
          );
        }
      }
    } finally {
      loading = false;
      _notify();
    }
  }

  String _draft(String game, String? parent) =>
      '$_key.draft.$game.${parent ?? 'root'}';
  Future<Map<String, dynamic>?> readDraft(String game, String? parent) async {
    await initialize();
    _check();
    final key = _draft(game, parent);
    final value = _pendingDrafts.containsKey(key)
        ? _pendingDrafts[key]
        : _prefs!.getString(key);
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<void> saveDraft(
    String game,
    String? parent,
    Map<String, Object?>? draft,
  ) async {
    await initialize();
    _check();
    final key = _draft(game, parent);
    // Freeze accepted input before queueing; retain it through failed writes
    // and identity invalidation. Only this instance's namespace is retried.
    final value = draft == null ? null : jsonEncode(draft);
    _pendingDrafts[key] = value;
    await _local(() => _saveDraftValue(key, value));
  }

  Future<void> _saveDraftValue(String key, String? value) async {
    final saved = value == null
        ? await _prefs!.remove(key)
        : await _prefs!.setString(key, value);
    if (!saved) throw StateError('草稿未保存，请重试');
    if (_pendingDrafts.containsKey(key) && _pendingDrafts[key] == value) {
      _pendingDrafts.remove(key);
    }
  }

  /// Local durability only: retry accepted content even after sign-out has
  /// invalidated network permissions. A real storage failure still blocks.
  Future<void> drain() {
    if (_writes == null && !_stateDirty && _pendingDrafts.isEmpty) {
      return Future<void>.value();
    }
    return _local(() async {
      if (_stateDirty) await _save();
      for (final entry in _pendingDrafts.entries.toList()) {
        await _saveDraftValue(entry.key, entry.value);
      }
    }).timeout(const Duration(seconds: 15));
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    super.dispose();
  }
}
