import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_identity/app_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_comment.dart';

/// Independent public namespace; never shares reaction files or sync status.
final class GameCommentsService extends ChangeNotifier {
  GameCommentsService({
    required this.files,
    required this.scope,
    required this.isActive,
    required this.displayName,
  });
  final AccountPublicFiles files;
  final String scope;
  final bool Function() isActive;
  final String Function() displayName;
  final Map<String, CommentOperation> _events = {}, _own = {};
  final Set<String> _pending = {};
  Future<void> _localQueue = Future.value();
  Future<void>? _syncTask;
  Future<void>? _ready;
  SharedPreferences? _prefs;
  String? _device;
  bool _disposed = false, loading = false;
  int _generation = 0;
  Timer? _retry;
  int _attempts = 0;
  String? error;
  late final int uid = files.uid;
  bool get canWrite => !_disposed && isActive();
  bool get pending => _pending.isNotEmpty;
  Set<String> get pendingIds => Set.unmodifiable(_pending);
  bool likePending(String commentId) => _pending.any(
    (id) =>
        _own[id]?.action == CommentAction.like && _own[id]?.target == commentId,
  );
  CommentProjection get projection => CommentProjection(_events.values, uid);
  String get _key => 'game_comments.v1.$scope';
  static String newId([String prefix = 'c']) {
    final random = Random.secure();
    return '$prefix${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<void> initialize() =>
      _ready ??= _initialize().catchError((Object failure) {
        _ready = null;
        throw failure;
      });
  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _device = _prefs!.getString('$_key.device') ?? newId('d');
    if (!RegExp(r'^d[0-9a-f]{32}$').hasMatch(_device!)) {
      throw const FormatException('评论设备标识无效');
    }
    if (!await _prefs!.setString('$_key.device', _device!)) {
      throw StateError('评论存储不可用');
    }
    final text = _prefs!.getString(_key);
    if (text != null) {
      final data = jsonDecode(text) as Map<String, dynamic>;
      for (final raw in data['own'] as List) {
        final op = CommentOperation.fromJson(
          Map<String, dynamic>.from(raw as Map),
          uid,
        );
        _own[op.id] = op;
      }
      for (final raw in data['events'] as List) {
        final map = Map<String, dynamic>.from(raw as Map);
        final op = CommentOperation.fromJson(map, map['uid'] as int);
        _events[op.id] = op;
      }
      _events.addAll(_own);
      _pending.addAll((data['pending'] as List).cast<String>());
      if (!_pending.every(_own.containsKey)) {
        throw const FormatException('待发评论记录无效');
      }
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check(int generation) {
    if (_disposed || generation != _generation || !isActive()) {
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    }
  }

  Future<T> _local<T>(Future<T> Function() work) {
    final task = _localQueue.then((_) => work());
    _localQueue = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> _save() async {
    final content = jsonEncode({
      'own': _own.values.map((v) => v.toJson()).toList(),
      'events': _events.values.map((v) => v.toJson()).toList(),
      'pending': _pending.toList(),
    });
    if (!await _prefs!.setString(_key, content)) throw StateError('评论未保存到本机');
  }

  int get _nextRevision =>
      _events.values.fold(0, (int value, op) => max(value, op.revision)) + 1;
  Future<String> publish({
    required String game,
    required String text,
    int? rating,
    String? parent,
    String? operationId,
  }) async {
    await initialize();
    return _local(() async {
      if (!canWrite) throw StateError('请联网登录后重试');
      final id = operationId ?? newId();
      final existing = _own[id];
      if (existing != null) {
        if (existing.game != game ||
            existing.text != text.trim() ||
            existing.rating != rating ||
            existing.replyTo != parent) {
          throw StateError('待发送内容已保存，请先重试原评论');
        }
        return id;
      }
      final target = parent == null ? null : projection.comments[parent];
      if (parent != null &&
          (target == null ||
              target.game != game ||
              projection.deleted.contains(parent))) {
        throw StateError('该评论已删除，请刷新后重试');
      }
      final op = CommentOperation(
        id: id,
        uid: uid,
        game: game,
        action: CommentAction.publish,
        revision: _nextRevision,
        at: DateTime.now().toUtc(),
        author: displayName().trim(),
        text: text.trim(),
        rating: rating,
        root: target == null ? null : target.root ?? target.id,
        replyTo: parent,
      );
      await _append(op);
      return id;
    });
  }

  Future<void> delete(GameComment comment) async {
    await initialize();
    await _local(() async {
      if (!canWrite || comment.operation.uid != uid) {
        throw StateError('只能删除自己的评论');
      }
      await _append(
        CommentOperation(
          id: newId(),
          uid: uid,
          game: comment.operation.game,
          action: CommentAction.delete,
          revision: _nextRevision,
          at: DateTime.now().toUtc(),
          target: comment.id,
        ),
      );
    });
    await synchronize();
  }

  Future<void> toggleLike(GameComment comment) async {
    await initialize();
    await _local(() async {
      if (!canWrite || projection.deleted.contains(comment.id)) {
        throw StateError('请刷新后重试');
      }
      final current = projection
          .forGame(comment.operation.game, _pending)
          .firstWhere((c) => c.id == comment.id);
      await _append(
        CommentOperation(
          id: newId(),
          uid: uid,
          game: comment.operation.game,
          action: CommentAction.like,
          revision: _nextRevision,
          at: DateTime.now().toUtc(),
          target: comment.id,
          liked: !current.likedByMe,
        ),
      );
    });
    await synchronize();
  }

  Future<void> _append(CommentOperation op) async {
    CommentOperation.fromJson(op.toJson(), uid);
    final candidate = {..._own, op.id: op};
    if (utf8.encode(_snapshot(candidate)).length > 512 * 1024) {
      throw StateError('本机评论记录已满，请联系管理员');
    }
    _own[op.id] = op;
    _events[op.id] = op;
    _pending.add(op.id);
    try {
      await _save();
    } catch (_) {
      _own.remove(op.id);
      _events.remove(op.id);
      _pending.remove(op.id);
      rethrow;
    }
    _notify();
  }

  String _snapshot(Map<String, CommentOperation> events) {
    final list = events.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode({
      'version': 1,
      'uid': uid,
      'device': _device,
      'operations': list.map((v) => v.toJson()).toList(),
    });
  }

  Future<void> synchronize() {
    if (_disposed) return Future.value();
    if (_syncTask != null) return _syncTask!;
    final task = _synchronize().timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _generation++;
        files.cancelRequests();
        loading = false;
        error = pending ? '发送超时，本机内容已保留，请重试' : '评论刷新超时，请重试';
        _notify();
        if (pending) _scheduleRetry();
      },
    );
    _syncTask = task;
    return task.whenComplete(() {
      if (identical(_syncTask, task)) _syncTask = null;
    });
  }

  Future<void> _synchronize() async {
    final generation = _generation;
    loading = true;
    error = null;
    _retry?.cancel();
    _notify();
    try {
      await initialize();
      _check(generation);
      await _readAll(generation);
      // Local clicks during an upload are included before this task completes.
      for (var round = 0; round < 3; round++) {
        final upload = await _local(
          () async => Map<String, CommentOperation>.from(_own),
        );
        if (_pending.isEmpty) break;
        final text = _snapshot(upload);
        final path = 'u$uid/$_device.json';
        _check(generation);
        await files.replaceOwn(path, text);
        _check(generation);
        if (await files.read(path) != text) throw StateError('评论写入核对未完成');
        _check(generation);
        await _local(() async {
          _check(generation);
          _pending.removeAll(upload.keys);
          await _save();
          _notify();
        });
        await _readAll(generation);
      }
      _attempts = 0;
      if (_pending.isNotEmpty) _scheduleRetry();
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = switch (failure) {
        PrivateFileException(failure: PrivateFileFailure.session) =>
          '登录已过期，请重新登录',
        PrivateFileException(failure: PrivateFileFailure.missing) =>
          '评论目录尚未准备，请联系管理员',
        PrivateFileException(failure: PrivateFileFailure.denied) =>
          '无法访问评论，请检查账号权限',
        FormatException() || TypeError() => '评论数据需要检查，已保留本机记录',
        _ => pending ? '发送未完成，本机内容已保留，请重试' : '评论刷新未完成，请重试',
      };
      if (pending) _scheduleRetry();
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void _scheduleRetry() {
    if (_disposed || _attempts >= 3 || !isActive()) return;
    _retry = Timer(
      Duration(seconds: 3 * (1 << _attempts++)),
      () => unawaited(synchronize()),
    );
  }

  Future<void> _readAll(int generation) async {
    final next = <String, CommentOperation>{};
    final remoteOwn = <String, CommentOperation>{};
    final accounts = await files.entries('');
    _check(generation);
    if (accounts.length > 1000) throw const FormatException('评论账号数量超过上限');
    var snapshots = 0;
    for (final account in accounts) {
      if (!account.directory ||
          !RegExp(r'^u[1-9][0-9]*$').hasMatch(account.name)) {
        throw const FormatException('评论目录无效');
      }
      final owner = int.parse(account.name.substring(1));
      final records = await files.entries(account.name);
      _check(generation);
      if (records.length > 128 || (snapshots += records.length) > 2000) {
        throw const FormatException('评论设备数量超过上限');
      }
      for (final record in records) {
        if (record.directory ||
            record.ownerUid != owner ||
            !RegExp(r'^d[0-9a-f]{32}\.json$').hasMatch(record.name)) {
          throw const FormatException('评论文件身份无效');
        }
        final text = await files.read('${account.name}/${record.name}');
        _check(generation);
        if (utf8.encode(text).length > 512 * 1024) {
          throw const FormatException('评论文件过大');
        }
        final data = jsonDecode(text) as Map<String, dynamic>;
        if (data['version'] != 1 ||
            data['uid'] != owner ||
            '${data['device']}.json' != record.name) {
          throw const FormatException('评论文件格式无效');
        }
        final operations = data['operations'] as List;
        for (final raw in operations) {
          final op = CommentOperation.fromJson(
            Map<String, dynamic>.from(raw as Map),
            owner,
          );
          if (next[op.id] != null && !next[op.id]!.sameAs(op)) {
            throw const FormatException('重复评论标识不一致');
          }
          next[op.id] = op;
          if (owner == uid && record.name == '$_device.json') {
            remoteOwn[op.id] = op;
          }
          if (next.length > 20000) throw const FormatException('评论数量超过上限');
        }
      }
    }
    await _local(() async {
      _check(generation);
      // Keep only this device's own journal; other devices have their own files.
      for (final op in remoteOwn.values) {
        if (_own[op.id] != null && !_own[op.id]!.sameAs(op)) {
          throw const FormatException('本机评论标识冲突');
        }
        _own[op.id] = op;
      }
      // Own IDs already retained in the journal are merged with the fresh read.
      for (final op in _own.values) {
        if (next[op.id] != null && !next[op.id]!.sameAs(op)) {
          throw const FormatException('本机评论核对失败');
        }
        next[op.id] = op;
        // Another process on this installation can share the device file.
        // A late/stale upload must not silently remove acknowledged events.
        if (!remoteOwn.containsKey(op.id)) _pending.add(op.id);
      }
      _events
        ..clear()
        ..addAll(next);
      await _save();
      _notify();
    });
  }

  String _draftKey(String game, String? parent) =>
      '$_key.draft.$game.${parent ?? 'root'}';
  Future<Map<String, dynamic>?> readDraft(String game, String? parent) async {
    await initialize();
    final text = _prefs!.getString(_draftKey(game, parent));
    return text == null ? null : jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> saveDraft(
    String game,
    String? parent,
    Map<String, Object?>? draft,
  ) async {
    await initialize();
    await _local(() async {
      final key = _draftKey(game, parent);
      final success = draft == null
          ? await _prefs!.remove(key)
          : await _prefs!.setString(key, jsonEncode(draft));
      if (!success) throw StateError('草稿未保存');
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    files.cancelRequests();
    super.dispose();
  }
}
