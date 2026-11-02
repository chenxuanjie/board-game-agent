import 'dart:async';
import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'board_sync_database.dart';

const _fields = <String, List<String>>{
  'favorites': ['game_slug', 'created_at'],
  'recent_games': ['game_slug', 'visited_at'],
  'preferences': [
    'nickname',
    'voice_reply_enabled',
    'assistant_mode',
    'game_answer_mode',
    'global_answer_mode',
    'use_game_knowledge',
  ],
  'conversations': [
    'title',
    'scope',
    'game_id',
    'created_at',
    'modified_at',
    'opened',
  ],
  'messages': [
    'conversation_id',
    'role',
    'content',
    'created_at',
    'state',
    'source',
    'citations',
    'evidence',
    'can_retry',
    'retry_prompt',
  ],
  'votes': ['campaign', 'game_slug'],
};
const _booleans = {
  'voice_reply_enabled',
  'use_game_knowledge',
  'opened',
  'can_retry',
};
const _jsonFields = {'citations', 'evidence'};
const _dates = {'created_at', 'modified_at', 'visited_at'};
String _utc(Object? value) =>
    DateTime.parse(value as String).toUtc().toIso8601String();
final boardPersonalSchema = Schema([
  for (final entry in _fields.entries)
    Table(
      entry.key,
      [
        const Column.text('dataset_id'),
        for (final field in entry.value)
          if (_booleans.contains(field))
            Column.integer(field)
          else
            Column.text(field),
        const Column.integer('row_version'),
        const Column.text('updated_at'),
        const Column.text('deleted_at'),
      ],
      trackMetadata: true,
      indexes: entry.key == 'messages'
          ? [
              Index('conversation_created', [
                IndexedColumn('conversation_id'),
                IndexedColumn('created_at'),
              ]),
            ]
          : [],
    ),
  const Table.localOnly('run_checkpoints', [
    Column.text('payload'),
    Column.text('modified_at'),
  ]),
]);

/// One immutable application/origin/account database. PowerSync owns its only
/// upload queue. Nothing is imported from the retired NAS or preference stores.
class BoardPersonalStore extends ChangeNotifier {
  BoardPersonalStore({required this.database, required this.datasetId});
  final PowerSyncDatabase database;
  final String datasetId;
  final _baselines = <String, Map<String, Map<String, dynamic>>>{};
  StreamSubscription<dynamic>? _status;
  bool _closed = false;
  String? syncError;

  static Future<BoardPersonalStore> open(String scope, String datasetId) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)) {
      throw ArgumentError('Invalid account scope');
    }
    final workspace = sha256
        .convert(utf8.encode('$scope|$datasetId'))
        .toString();
    final filename = 'board-personal-v1-$workspace.sqlite';
    final db = await openBoardSyncDatabase(filename, boardPersonalSchema);
    return BoardPersonalStore(database: db, datasetId: datasetId);
  }

  Future<void> connect(
    BoardSyncConnector connector, {
    HttpClientFactory? httpClient,
  }) async {
    if (_closed) throw StateError('Personal store closed');
    await _status?.cancel();
    _status = database.statusStream.listen((status) {
      if (_closed) return;
      syncError = status.anyError == null ? null : '个人数据已保存在本机，同步未完成';
      notifyListeners();
    });
    await database.connect(
      connector: connector,
      options: SyncOptions(httpClient: httpClient ?? createDefaultAiHttpClient),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _status?.cancel();
    await database.disconnect();
    await database.close();
    dispose();
  }

  Map<String, dynamic> _record(String table, Map<String, dynamic> row) => {
    'id': row['id'],
    for (final key in _fields[table]!)
      key: _booleans.contains(key)
          ? row[key] == 1
          : _jsonFields.contains(key)
          ? jsonDecode(row[key] as String? ?? '[]')
          : _dates.contains(key) && row[key] != null
          ? _utc(row[key])
          : row[key],
  };

  Future<List<Map<String, dynamic>>> records(String table) async {
    if (!_fields.containsKey(table) || _closed) {
      throw StateError('Personal store unavailable');
    }
    return (await database.getAll(
      'SELECT * FROM $table WHERE deleted_at IS NULL',
    )).map((row) => _record(table, row)).toList();
  }

  Future<List<Map<String, dynamic>>> loadCollection(String table) async {
    final rows = await records(table);
    _baselines[table] = {for (final r in rows) r['id'] as String: r};
    return rows;
  }

  /// Only change rows the UI actually changed. A stale snapshot must never
  /// delete an unseen row arriving from another device.
  Future<void> saveCollection(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (!_fields.containsKey(table) || _closed) {
      throw StateError('Personal store unavailable');
    }
    final before = _baselines[table];
    if (before == null) {
      throw StateError('Read personal data before editing it');
    }
    final next = {for (final r in rows) r['id'] as String: r};
    await database.writeTransaction((tx) async {
      for (final r in rows) {
        if (!_same(r, before[r['id']])) await _put(tx, table, r);
      }
      for (final id in before.keys.where((id) => !next.containsKey(id))) {
        await _put(tx, table, before[id]!, delete: true);
      }
    });
    _baselines[table] = next;
  }

  static bool _same(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
    }
    return a == b;
  }

  Future<void> _put(
    SqliteWriteContext tx,
    String table,
    Map<String, dynamic> r, {
    bool delete = false,
    List<String>? changedFields,
  }) async {
    final fields = _fields[table]!;
    void validateJson(Object? value, [int depth = 0]) {
      if (depth > 20 || value is String && value.contains('\u0000')) {
        throw const FormatException('个人数据包含不可保存的字符或结构');
      }
      if (value is Map) {
        for (final entry in value.entries) {
          validateJson(entry.key, depth + 1);
          validateJson(entry.value, depth + 1);
        }
      } else if (value is List) {
        for (final entry in value) {
          validateJson(entry, depth + 1);
        }
      }
    }

    validateJson(r);
    if ((r['id'] as String).length > 200 ||
        table == 'conversations' && (r['title'] as String).length > 200 ||
        table == 'preferences' && (r['nickname'] as String).length > 80 ||
        table == 'messages' &&
            ((r['citations'] as List).length > 200 ||
                (r['evidence'] as List).length > 200)) {
      throw const FormatException('个人数据超过单条记录限制');
    }
    final metadata = {
      'id': const Uuid().v4(),
      'entity': table,
      'record_id': r['id'],
      'record': delete ? null : r,
      'changed_fields': ?changedFields,
    };
    // Keep uploads inside the service's bounded request size, measured in UTF-8.
    if (utf8.encode(jsonEncode(metadata)).length > 480 * 1024) {
      throw StateError('单条个人数据过大，尚未保存');
    }
    await tx.execute(
      'INSERT OR REPLACE INTO $table('
      'id,dataset_id,${fields.join(',')},deleted_at,_metadata) '
      'VALUES(${List.filled(fields.length + 4, '?').join(',')})',
      [
        r['id'],
        datasetId,
        for (final field in fields)
          _booleans.contains(field)
              ? (r[field] == true ? 1 : 0)
              : _jsonFields.contains(field)
              ? jsonEncode(r[field] ?? [])
              : r[field],
        delete ? DateTime.now().toUtc().toIso8601String() : null,
        jsonEncode(metadata),
      ],
    );
  }

  static const preferenceDefaults = <String, dynamic>{
    'id': 'profile',
    'nickname': '',
    'voice_reply_enabled': false,
    'assistant_mode': 'text_and_dictation',
    'game_answer_mode': 'knowledge_only',
    'global_answer_mode': 'knowledge_then_direct',
    'use_game_knowledge': false,
  };
  Future<Map<String, dynamic>> preferences() async => {
    ...preferenceDefaults,
    ...(await records('preferences')).firstOrNull ?? {},
  };
  Future<void> setPreference(String key, Object value) async {
    if (!_fields['preferences']!.contains(key)) {
      throw ArgumentError('Not a cloud preference');
    }
    await database.writeTransaction((tx) async {
      final old = await tx.getOptional(
        "SELECT * FROM preferences WHERE id='profile' AND deleted_at IS NULL",
      );
      final r = {
        ...preferenceDefaults,
        if (old != null) ..._record('preferences', old),
        key: value,
      };
      await _put(tx, 'preferences', r, changedFields: [key]);
    });
  }

  Future<List<String>> loadVotes(String campaign) async => [
    for (final r in await loadCollection('votes'))
      if (r['campaign'] == campaign) r['game_slug'] as String,
  ];
  Future<void> saveVotes(String campaign, Iterable<String> games) async {
    final baseline = _baselines['votes'];
    if (baseline == null) throw StateError('Read votes before editing');
    await saveCollection('votes', [
      ...baseline.values.where((r) => r['campaign'] != campaign),
      for (final game in games)
        {'id': '$campaign|$game', 'campaign': campaign, 'game_slug': game},
    ]);
  }

  Future<void> waitForUpload() async {
    await database
        .watch('SELECT count(*) n FROM ps_crud')
        .firstWhere((rows) => rows.single['n'] == 0)
        .timeout(const Duration(seconds: 20));
  }

  Map<String, String> _conversationHeaders = {},
      _messageHeaders = {},
      _checkpointHeaders = {};
  Map<String, String> _messageParents = {};
  final Map<String, dynamic> _conversationViews = {};

  /// Read small version headers first, then materialize only changed sessions.
  /// Message-only changes and tombstones count even when the parent is unchanged.
  Future<({Map<String, dynamic> updated, Set<String> deleted})>
  loadConversationChanges() async {
    final result = await database.readTransaction((tx) async {
      final conversations = await tx.getAll(
        'SELECT id,row_version,updated_at,deleted_at FROM conversations',
      );
      final messages = await tx.getAll(
        'SELECT id,conversation_id,row_version,updated_at,deleted_at FROM messages',
      );
      final checkpoints = await tx.getAll(
        'SELECT id,modified_at FROM run_checkpoints',
      );
      String signature(Map<String, dynamic> r) =>
          '${r['row_version']}|${r['updated_at']}|${r['deleted_at']}';
      final cHeaders = {
        for (final r in conversations) r['id'] as String: signature(r),
      };
      final mHeaders = {
        for (final r in messages) r['id'] as String: signature(r),
      };
      final parents = {
        for (final r in messages)
          r['id'] as String: r['conversation_id'] as String,
      };
      final pHeaders = {
        for (final r in checkpoints) r['id'] as String: '${r['modified_at']}',
      };
      final changed = <String>{
        for (final id in {...cHeaders.keys, ..._conversationHeaders.keys})
          if (cHeaders[id] != _conversationHeaders[id]) id,
        for (final id in {...mHeaders.keys, ..._messageHeaders.keys})
          if (mHeaders[id] != _messageHeaders[id]) ...[
            if (parents[id] != null) parents[id]!,
            if (_messageParents[id] != null) _messageParents[id]!,
          ],
        for (final id in {...pHeaders.keys, ..._checkpointHeaders.keys})
          if (pHeaders[id] != _checkpointHeaders[id]) id,
      };
      final updated = <String, dynamic>{};
      final deleted = <String>{};
      final cRows = <String, Map<String, dynamic>>{};
      final mRows = <String, Map<String, dynamic>>{};
      for (final id in changed) {
        final row = await tx.getOptional(
          'SELECT * FROM conversations WHERE id=? AND deleted_at IS NULL',
          [id],
        );
        if (row == null) {
          deleted.add(id);
          continue;
        }
        final c = _record('conversations', row);
        cRows[id] = c;
        final rows = await tx.getAll(
          'SELECT * FROM messages WHERE conversation_id=? AND deleted_at IS NULL ORDER BY created_at,id',
          [id],
        );
        final checkpoint = await tx.getOptional(
          'SELECT * FROM run_checkpoints WHERE id=?',
          [id],
        );
        final localRun =
            checkpoint != null &&
            DateTime.parse(c['modified_at'] as String).isAtSameMomentAs(
              DateTime.parse(checkpoint['modified_at'] as String),
            );
        updated[id] = {
          'id': id,
          'title': c['title'],
          'scope': c['scope'],
          'gameId': c['game_id'],
          'createdAt': c['created_at'],
          'updatedAt': c['modified_at'],
          'opened': c['opened'],
          if (localRun) 'lastRun': jsonDecode(checkpoint['payload'] as String),
          'messages': [
            for (final row in rows)
              (() {
                final m = _record('messages', row);
                mRows[m['id'] as String] = m;
                return {
                  'id': (m['id'] as String).substring('$id|'.length),
                  'role': m['role'],
                  'text': m['content'],
                  'timestamp': m['created_at'],
                  'source': m['source'],
                  'state': m['state'],
                  'citations': m['citations'],
                  'evidence': m['evidence'],
                  'canRetry': m['can_retry'],
                  'retryPrompt': m['retry_prompt'],
                };
              })(),
          ],
        };
      }
      return (
        updated: updated,
        deleted: deleted,
        changed: changed,
        c: cRows,
        m: mRows,
        cHeaders: cHeaders,
        mHeaders: mHeaders,
        parents: parents,
        pHeaders: pHeaders,
      );
    });
    final cBaseline = _baselines.putIfAbsent('conversations', () => {});
    final mBaseline = _baselines.putIfAbsent('messages', () => {});
    cBaseline.removeWhere((id, _) => result.changed.contains(id));
    mBaseline.removeWhere(
      (_, row) => result.changed.contains(row['conversation_id']),
    );
    cBaseline.addAll(result.c);
    mBaseline.addAll(result.m);
    _conversationHeaders = result.cHeaders;
    _messageHeaders = result.mHeaders;
    _messageParents = result.parents;
    _checkpointHeaders = result.pHeaders;
    for (final id in result.deleted) {
      _conversationViews.remove(id);
    }
    _conversationViews.addAll(result.updated);
    return (updated: result.updated, deleted: result.deleted);
  }

  Future<String> loadConversations() async {
    await loadConversationChanges();
    return jsonEncode({'version': 4, 'conversations': _conversationViews});
  }

  Future<void> saveConversationChanges(
    Map<String, dynamic> updated,
    Set<String> deleted,
  ) => _saveConversations(
    {'conversations': updated},
    onlyIds: {...updated.keys, ...deleted},
  );

  Future<void> saveConversations(String payload) =>
      _saveConversations(jsonDecode(payload) as Map<String, dynamic>);

  Future<void> _saveConversations(
    Map<String, dynamic> envelope, {
    Set<String>? onlyIds,
  }) async {
    final sessions = (envelope['conversations'] as Map).values
        .cast<Map<String, dynamic>>();
    final c = <Map<String, dynamic>>[], m = <Map<String, dynamic>>[];
    for (final s in sessions) {
      c.add({
        'id': s['id'],
        'title': s['title'],
        'scope': s['scope'],
        'game_id': s['gameId'],
        'created_at': _utc(s['createdAt']),
        'modified_at': _utc(s['updatedAt']),
        'opened': s['opened'] == true,
      });
      for (final message
          in (s['messages'] as List).cast<Map<String, dynamic>>()) {
        m.add({
          'id': '${s['id']}|${message['id']}',
          'conversation_id': s['id'],
          'role': message['role'],
          'content': message['text'],
          'created_at': _utc(message['timestamp']),
          'state': message['state'] == 'failed' ? 'failed' : 'complete',
          'source': message['source'],
          'citations': message['citations'] ?? [],
          'evidence': message['evidence'] ?? [],
          'can_retry': message['canRetry'] == true,
          'retry_prompt': message['retryPrompt'],
        });
      }
    }
    // Parent rows are queued before children. Each upload is independently
    // replayable; a failure cannot acknowledge the remaining local mutations.
    final beforeConversations = _baselines['conversations'];
    final beforeMessages = _baselines['messages'];
    if (beforeConversations == null || beforeMessages == null) {
      throw StateError('Read conversations before editing');
    }
    final nextC = {for (final row in c) row['id'] as String: row};
    final nextM = {for (final row in m) row['id'] as String: row};
    final removedM = beforeMessages.keys
        .where(
          (id) =>
              !nextM.containsKey(id) &&
              (onlyIds == null ||
                  onlyIds.contains(beforeMessages[id]!['conversation_id'])),
        )
        .toList();
    final removedC = beforeConversations.keys
        .where(
          (id) =>
              !nextC.containsKey(id) &&
              (onlyIds == null || onlyIds.contains(id)),
        )
        .toList();
    await database.writeTransaction((tx) async {
      for (final r in c) {
        if (!_same(r, beforeConversations[r['id']])) {
          await _put(tx, 'conversations', r);
        }
      }
      for (final r in m) {
        if (!_same(r, beforeMessages[r['id']])) await _put(tx, 'messages', r);
      }
      for (final id in removedM) {
        await _put(tx, 'messages', beforeMessages[id]!, delete: true);
      }
      for (final id in removedC) {
        await _put(tx, 'conversations', beforeConversations[id]!, delete: true);
        await tx.execute('DELETE FROM run_checkpoints WHERE id=?', [id]);
      }
      for (final s in sessions) {
        if (s['lastRun'] != null) {
          await tx.execute(
            'INSERT OR REPLACE INTO run_checkpoints(id,payload,modified_at) VALUES(?,?,?)',
            [s['id'], jsonEncode(s['lastRun']), s['updatedAt']],
          );
        } else {
          await tx.execute('DELETE FROM run_checkpoints WHERE id=?', [s['id']]);
        }
      }
    });
    for (final id in removedC) {
      beforeConversations.remove(id);
    }
    for (final id in removedM) {
      beforeMessages.remove(id);
    }
    beforeConversations.addAll(nextC);
    beforeMessages.addAll(nextM);
    // Local edits can have the same null SDK version header before upload.
    // Invalidate only affected parents so a subsequent read observes the write.
    for (final id in {...nextC.keys, ...removedC}) {
      _conversationHeaders.remove(id);
    }
  }
}

class BoardSyncConnector extends PowerSyncBackendConnector {
  BoardSyncConnector({
    required this.client,
    required this.store,
    required this.token,
    required this.active,
    required this.userId,
  });
  final AppJsonClient client;
  final BoardPersonalStore store;
  final Future<String> Function() token;
  final bool Function() active;
  final String userId;
  void _guard() {
    if (!active()) throw StateError('Account scope changed');
  }

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    _guard();
    final data = await client.request(
      '/v1/sync/credentials',
      body: {},
      token: await token(),
    );
    _guard();
    return boardSyncCredentials(client, data, userId: userId);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    _guard();
    final batch = await database.getCrudBatch(limit: 1);
    if (batch == null) return;
    final entry = batch.crud.single;
    if (!_fields.containsKey(entry.table) || entry.metadata == null) {
      throw StateError('Unmapped mutation retained');
    }
    final mutation = jsonDecode(entry.metadata!) as Map<String, dynamic>;
    if (mutation['record_id'] != entry.id ||
        mutation['entity'] != entry.table) {
      throw StateError('Mutation identity mismatch');
    }
    final data = await client.request(
      '/v1/sync/upload',
      token: await token(),
      body: {
        'dataset_id': store.datasetId,
        'mutations': [mutation],
      },
    );
    _guard();
    final results = data['results'] as List;
    if (results.length != 1 ||
        results.single['id'] != mutation['id'] ||
        results.single['status'] != 'applied') {
      throw StateError('Invalid upload acknowledgement');
    }
    await batch.complete();
  }
}
