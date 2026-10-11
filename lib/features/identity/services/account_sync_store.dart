import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_sync/webdav_sync.dart';

typedef AccountEntities = Map<String, Map<String, Object?>>;
typedef AccountDataTransaction =
    Future<T> Function<T>(
      Future<T> Function(
        AccountEntities current,
        Future<void> Function(AccountEntities) project,
      )
      work,
    );

/// One committed journal contains entity versions, outbox, cursors and a durable
/// projection intent. A failed multi-store projection is replayed before capture.
final class AccountSyncLocalStore implements SyncLocalStore {
  AccountSyncLocalStore({
    required this.datasetId,
    required this.transaction,
    this.reactionTransaction,
    this.readJournal,
    this.writeJournal,
  });
  final String datasetId;
  final AccountDataTransaction transaction;
  final AccountDataTransaction? reactionTransaction;
  final Future<String?> Function()? readJournal;
  final Future<void> Function(String)? writeJournal;
  Map<String, dynamic>? _state;
  Future<void> _writes = Future<void>.value();
  Future<T> _serialize<T>(Future<T> Function() work) {
    final result = _writes.then((_) => work());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  String get _key => 'account_cloud_v1.$datasetId';
  @override
  String get deviceId => _state!['device'] as String;
  Future<void> initialize() async {
    final raw = readJournal == null
        ? (await SharedPreferences.getInstance()).getString(_key)
        : await readJournal!();
    if (raw == null) {
      final random = Random.secure();
      _state = {
        'version': 1,
        'dataset': datasetId,
        'device':
            'd${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
        'sequence': 0,
        'clock': 0,
        'heads': <String, dynamic>{},
        'outbox': <dynamic>[],
        'checkpoint': SyncCheckpoint.empty().toJson(),
        'projectionPending': false,
      };
      await _save();
    } else {
      if (utf8.encode(raw).length > 32 * 1024 * 1024) {
        throw const SyncProtocolException('本机同步日志过大');
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1 ||
          data['dataset'] != datasetId ||
          data['device'] is! String ||
          !RegExp(r'^d[0-9a-f]{32}$').hasMatch(data['device']) ||
          data['heads'] is! Map ||
          data['outbox'] is! List ||
          data['sequence'] is! int ||
          data['clock'] is! int) {
        throw const SyncProtocolException('本机同步日志损坏');
      }
      _state = data;
      for (final value in _heads.values) {
        _operation(value);
      }
      for (final value in _outbox) {
        _operation(value);
      }
      await loadCheckpoint();
    }
  }

  Map<String, dynamic> get _heads => _state!['heads'] as Map<String, dynamic>;
  List<dynamic> get _outbox => _state!['outbox'] as List<dynamic>;
  SyncOperation _operation(dynamic raw) {
    final op = SyncOperation.fromJson(Map<String, Object?>.from(raw as Map));
    if (op.datasetId != datasetId ||
        !const {
          'favorite',
          'recent',
          'conversation',
          'preference',
          'nickname',
          'vote',
          'seasonalList',
          'search',
          'recommendation',
        }.contains(op.entityType) ||
        op.entityId.length > 512) {
      throw const SyncProtocolException('同步数据范围不匹配');
    }
    return op;
  }

  AccountEntities _entities() => {
    for (final entry in _heads.entries)
      if (_operation(entry.value).operation == SyncOperationType.upsert)
        entry.key: Map<String, Object?>.from(_operation(entry.value).payload!),
  };

  /// Public projection contains only reactions, including cancellation tombstones.
  List<SyncOperation> get publicReactions => _heads.values
      .map(_operation)
      .where((op) => op.entityType == 'favorite' || op.entityType == 'vote')
      .toList(growable: false);

  String get publicFingerprint => canonicalJson({
    for (final op in publicReactions)
      '${op.entityType}|${op.entityId}': op.toJson(),
  });

  bool get hasPendingOperations => _outbox.isNotEmpty;

  static bool operationWins(SyncOperation incoming, SyncOperation? previous) =>
      previous == null ||
      incoming.logicalClock > previous.logicalClock ||
      incoming.logicalClock == previous.logicalClock &&
          incoming.operationId.compareTo(previous.operationId) > 0;

  /// Import sparse public heads without advancing the private download cursor.
  Future<void> applyPublicReactions(
    Iterable<SyncOperation> operations, {
    void Function()? check,
  }) => _serialize(() async {
    check?.call();
    if (_state!['projectionPending'] == true) {
      await transaction<void>((current, project) async {
        check?.call();
        await _recover(current, project);
      });
    }
    return (reactionTransaction ?? transaction)<void>((current, project) async {
      check?.call();
      _capture(current, reactionsOnly: reactionTransaction != null);
      var changed = false;
      for (final op in operations) {
        if (op.datasetId != datasetId ||
            !{'favorite', 'vote'}.contains(op.entityType)) {
          throw const SyncProtocolException('公共账号范围不匹配');
        }
        _operation(op.toJson());
        final key = '${op.entityType}|${op.entityId}';
        final old = _heads[key] == null ? null : _operation(_heads[key]);
        _state!['clock'] = max(_state!['clock'] as int, op.logicalClock);
        if (operationWins(op, old)) {
          _heads[key] = op.toJson();
          changed = true;
        }
      }
      if (!changed) {
        await _save();
        return;
      }
      _state!['projectionPending'] = true;
      _state!['projectionBase'] = current;
      await _save();
      await project(_entities());
      _state!['projectionPending'] = false;
      _state!.remove('projectionBase');
      await _save();
    });
  });

  Future<void> _save() async {
    final json = jsonEncode(_state);
    if (utf8.encode(json).length > 32 * 1024 * 1024) {
      throw StateError('同步日志保存失败');
    }
    if (writeJournal != null) {
      await writeJournal!(json);
    } else if (!await (await SharedPreferences.getInstance()).setString(
      _key,
      json,
    )) {
      throw StateError('同步日志保存失败');
    }
  }

  void _change(String key, Map<String, Object?>? payload) {
    final old = _heads[key] == null ? null : _operation(_heads[key]);
    final split = key.indexOf('|');
    if (split < 1) throw const SyncProtocolException('非法同步实体');
    final sequence = (_state!['sequence'] as int) + 1;
    final clock = (_state!['clock'] as int) + 1;
    final op = SyncOperation(
      protocolVersion: 1,
      datasetId: datasetId,
      operationId: '${deviceId}_$sequence',
      deviceId: deviceId,
      sequence: sequence,
      logicalClock: clock,
      entityType: key.substring(0, split),
      entityId: key.substring(split + 1),
      operation: payload == null
          ? SyncOperationType.delete
          : SyncOperationType.upsert,
      payload: payload,
      parents: old == null ? [] : [old.operationId],
      entityParents: old == null ? [] : [old.operationId],
      seen: SyncCheckpoint.fromJson(
        Map<String, Object?>.from(_state!['checkpoint'] as Map),
      ).pullCursor.positions,
      changedAt: DateTime.now().toUtc(),
    );
    if (utf8.encode(op.canonicalJson).length > 8 * 1024 * 1024) {
      throw const SyncProtocolException('单条同步数据超过上限');
    }
    _state!['sequence'] = sequence;
    _state!['clock'] = clock;
    _heads[key] = op.toJson();
    _outbox.add(op.toJson());
  }

  void _capture(AccountEntities current, {bool reactionsOnly = false}) {
    final before = _entities();
    for (final key in {...before.keys, ...current.keys}) {
      if (reactionsOnly &&
          !key.startsWith('favorite|') &&
          !key.startsWith('vote|')) {
        continue;
      }
      if (canonicalJson(before[key]) != canonicalJson(current[key])) {
        _change(key, current[key]);
      }
    }
  }

  Future<void> _recover(
    AccountEntities current,
    Future<void> Function(AccountEntities) project,
  ) async {
    final target = _entities();
    final base = Map<String, dynamic>.from(
      _state!['projectionBase'] as Map? ?? {},
    );
    // A partial projection contains either the pre-commit value or the target.
    // Preserve subsequent edits that differ from both, before replaying intent.
    for (final key in {...base.keys, ...current.keys, ...target.keys}) {
      if (canonicalJson(current[key]) != canonicalJson(base[key]) &&
          canonicalJson(current[key]) != canonicalJson(target[key])) {
        _change(key, current[key]);
      }
    }
    await _save();
    await project(_entities());
    _state!['projectionPending'] = false;
    _state!.remove('projectionBase');
    await _save();
  }

  Future<void> capture({void Function()? check}) => _serialize(
    () => transaction<void>((current, project) async {
      check?.call();
      if (_state!['projectionPending'] == true) {
        await _recover(current, project);
      } else {
        _capture(current);
      }
      await _save();
    }),
  );
  Future<void> captureReactions({void Function()? check}) =>
      _serialize(() async {
        check?.call();
        if (_state!['projectionPending'] == true) {
          await transaction<void>((current, project) async {
            check?.call();
            await _recover(current, project);
          });
        }
        await (reactionTransaction ?? transaction)<void>((current, _) async {
          check?.call();
          _capture(current, reactionsOnly: reactionTransaction != null);
          await _save();
        });
      });

  @override
  Future<SyncCheckpoint> loadCheckpoint() async => SyncCheckpoint.fromJson(
    Map<String, Object?>.from(_state!['checkpoint'] as Map),
  );
  @override
  Future<void> saveCheckpoint(
    SyncCheckpoint checkpoint, {
    void Function()? check,
  }) => _serialize(() async {
    check?.call();
    _state!['checkpoint'] = checkpoint.toJson();
    // Uploaded immutable operations remain on NAS; prune acknowledged outbox.
    _outbox.removeWhere(
      (value) => _operation(value).sequence <= checkpoint.uploadSequence,
    );
    await _save();
  });

  @override
  Future<List<SyncOperation>> pendingOperations({
    required int afterSequence,
    int limit = 500,
  }) async => _outbox
      .map(_operation)
      .where((op) => op.sequence > afterSequence)
      .take(limit)
      .toList();
  @override
  Future<SyncApplyResult> applyRemoteOperations({
    required Iterable<SyncOperation> operations,
    required SyncCursor currentCursor,
    void Function()? check,
  }) => _serialize(
    () => transaction<SyncApplyResult>((current, project) async {
      check?.call();
      if (_state!['projectionPending'] == true) {
        await _recover(current, project);
      } else {
        _capture(current);
      }
      var cursor = currentCursor, applied = 0, duplicates = 0;
      final ordered = operations.toList()
        ..sort(
          (a, b) => a.logicalClock != b.logicalClock
              ? a.logicalClock.compareTo(b.logicalClock)
              : a.operationId.compareTo(b.operationId),
        );
      for (final raw in ordered) {
        final op = _operation(raw.toJson());
        if (op.sequence <= cursor.forDevice(op.deviceId)) {
          duplicates++;
          continue;
        }
        final key = '${op.entityType}|${op.entityId}';
        final old = _heads[key] == null ? null : _operation(_heads[key]);
        _state!['clock'] = max(_state!['clock'] as int, op.logicalClock);
        final concurrent =
            old != null &&
            old.operationId != op.operationId &&
            !(op.entityParents ?? op.parents).contains(old.operationId) &&
            (op.seen[old.deviceId] ?? 0) < old.sequence &&
            !(old.entityParents ?? old.parents).contains(op.operationId) &&
            (old.seen[op.deviceId] ?? 0) < op.sequence;
        var wins = operationWins(op, old);
        if ((op.entityType == 'recent' || op.entityType == 'search') &&
            op.payload != null &&
            old?.payload != null) {
          final incoming = DateTime.tryParse(
            op.payload![op.entityType == 'recent' ? 'viewedAt' : 'searchedAt']
                    as String? ??
                '',
          );
          final previous = DateTime.tryParse(
            old!.payload![op.entityType == 'recent' ? 'viewedAt' : 'searchedAt']
                    as String? ??
                '',
          );
          if (incoming != null && previous != null && incoming != previous) {
            wins = incoming.isAfter(previous);
          }
        }
        if (concurrent &&
            op.entityType == 'conversation' &&
            old.payloadHash != op.payloadHash) {
          final loser = wins ? old : op;
          if (loser.payload != null) {
            final id =
                'conversation:conflict_${sha256Json([op.entityId, loser.operationId])}';
            final copy = {
              ...loser.payload!,
              'id': id,
              'title': '${loser.payload!['title'] ?? 'AI 对话'}（冲突副本）',
            };
            if (!_heads.containsKey('conversation|$id')) {
              _change('conversation|$id', copy);
            }
          }
        }
        if (wins) {
          _heads[key] = op.toJson();
          applied++;
        }
        cursor = cursor.advance(op.deviceId, op.sequence);
      }
      final checkpoint = await loadCheckpoint();
      _state!['checkpoint'] = checkpoint.copyWith(pullCursor: cursor).toJson();
      _state!['projectionPending'] = true;
      _state!['projectionBase'] = current;
      await _save(); // Journal/cursor first; projection can safely replay after a crash.
      await project(_entities());
      _state!['projectionPending'] = false;
      _state!.remove('projectionBase');
      await _save();
      return SyncApplyResult(
        cursor: cursor,
        applied: applied,
        duplicates: duplicates,
      );
    }),
  );
}
