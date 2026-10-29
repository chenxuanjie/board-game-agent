import 'dart:async';
import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:crypto/crypto.dart';
import 'package:powersync/powersync.dart';
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import '../../identity/services/board_sync_database.dart';
import 'public_publication.dart';

typedef PublicSyncFactory =
    Future<BoardPublicSync> Function({
      required AppJsonClient client,
      required bool Function() active,
      required Future<void> Function(bool statistics, Set<String> games)
      refresh,
      required Future<void> Function(List<PublicPublication>)
      refreshPublications,
      void Function()? onStatusChanged,
    });

const boardPublicSchema = Schema([
  Table('public_changes', [
    Column.integer('statistics_version'),
    Column.integer('comments_version'),
  ]),
  Table('publication_versions', [
    Column.text('app_id'),
    Column.text('topic'),
    Column.integer('revision'),
    Column.text('channel'),
    Column.text('platform'),
    Column.text('architecture'),
  ]),
]);

/// Public, per-origin versions contain no account data. PowerSync handles
/// reconnect/checkpoints; authoritative snapshots stay in the scoped business API.
class BoardPublicSync {
  BoardPublicSync({
    required this.database,
    required this.client,
    required this.active,
    required this.refresh,
    this.httpClient,
    this.onStatusChanged,
    this.refreshPublications,
  });
  final PowerSyncDatabase database;
  final AppJsonClient client;
  final bool Function() active;
  final Future<void> Function(bool statistics, Set<String> games) refresh;
  final HttpClientFactory? httpClient;
  final void Function()? onStatusChanged;
  final Future<void> Function(List<PublicPublication>)? refreshPublications;
  StreamSubscription<dynamic>? _rows, _status, _publications;
  final _publicationVersions = <String, PublicPublication>{};
  final _dirtyPublications = <String, PublicPublication>{};
  bool _publicationProbe = false;
  final _versions = <String, (int, int)>{};
  final _dirtyGames = <String>{};
  bool _statisticsDirty = false,
      _closed = false,
      _paused = false,
      _running = false;
  bool _connected = false;
  Timer? _timer;
  DateTime? _due;
  int _attempts = 0;
  Future<void>? _connection;
  Future<void>? _closing;
  String? _error;
  String? get error => _error;
  void _setError(String? value) {
    if (_closed || !active() || _error == value) return;
    _error = value;
    onStatusChanged?.call();
  }

  static Future<BoardPublicSync> open({
    required AppJsonClient client,
    required bool Function() active,
    required Future<void> Function(bool statistics, Set<String> games) refresh,
    required Future<void> Function(List<PublicPublication>) refreshPublications,
    void Function()? onStatusChanged,
  }) async {
    final namespace = sha256
        .convert(utf8.encode('board_game_agent|${client.origin.origin}'))
        .toString();
    final db = await openBoardSyncDatabase(
      'board-public-v1-$namespace.sqlite',
      boardPublicSchema,
    );
    return BoardPublicSync(
      database: db,
      client: client,
      active: active,
      refresh: refresh,
      refreshPublications: refreshPublications,
      onStatusChanged: onStatusChanged,
    );
  }

  Future<void> start() async {
    if (_closed || !active()) return;
    _publications = database.watch('SELECT * FROM publication_versions').listen(
      (rows) {
        if (_closed || !active()) return;
        try {
          for (final row in rows) {
            final next = PublicPublication.fromRow(row);
            if (_publicationVersions[next.id]?.revision != next.revision) {
              _dirtyPublications[next.id] = next;
              _publicationVersions[next.id] = next;
            }
          }
          if (_dirtyPublications.isNotEmpty) {
            _attempts = 0;
            _schedule(const Duration(milliseconds: 250));
          }
        } catch (_) {
          _setError('公开发布通知读取失败，请重试');
        }
      },
      onError: (Object _) => _setError('公开发布通知读取失败，请重试'),
    );
    _rows = database
        .watch('SELECT * FROM public_changes')
        .listen(
          (rows) {
            if (_closed || !active()) return;
            var statistics = false;
            final games = <String>{};
            for (final row in rows) {
              final id = row['id'] as String;
              final next = (
                row['statistics_version'] as int,
                row['comments_version'] as int,
              );
              final previous = _versions[id];
              if (previous?.$1 != next.$1) statistics = true;
              if (previous?.$2 != next.$2) games.add(id);
              _versions[id] = next;
            }
            if (statistics || games.isNotEmpty) {
              requestRefresh(statistics: statistics, games: games);
            }
          },
          onError: (Object _) {
            _setError('公共数据实时更新未完成，请重试');
          },
        );
    _status = database.statusStream.listen((state) {
      if (_closed || !active()) return;
      _setError(state.anyError == null ? null : '公共数据实时更新未完成，请重试');
      if (state.connected && !_connected) {
        requestPublicationRefresh();
        requestRefresh(games: _versions.keys);
      }
      _connected = state.connected;
    });
    requestRefresh(games: _versions.keys);
    requestPublicationRefresh();
    await _connect();
  }

  /// Re-read authoritative APIs after startup/reconnect, including an empty DB.
  void requestPublicationRefresh() {
    if (_closed || !active() || refreshPublications == null) return;
    _publicationProbe = true;
    _dirtyPublications.addAll(_publicationVersions);
    _attempts = 0;
    _schedule(const Duration(milliseconds: 250));
  }

  void requestRefresh({
    bool statistics = true,
    Iterable<String> games = const [],
  }) {
    if (_closed || !active()) return;
    _statisticsDirty |= statistics;
    _dirtyGames.addAll(games);
    _attempts = 0;
    _schedule(const Duration(milliseconds: 250));
  }

  void _schedule(Duration delay) {
    if (_closed || _paused || _running || !active()) return;
    final due = DateTime.now().add(delay);
    // A steady stream of changes must not postpone the first refresh forever.
    // New changes may shorten a retry delay, but cannot defer an earlier batch.
    if (_timer?.isActive == true && !_due!.isAfter(due)) return;
    _timer?.cancel();
    _due = due;
    _timer = Timer(delay, () {
      _due = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (_closed || _paused || _running || !active()) return;
    final statistics = _statisticsDirty, games = Set<String>.of(_dirtyGames);
    final publications = Map<String, PublicPublication>.of(_dirtyPublications);
    final probe = _publicationProbe;
    if (!statistics && games.isEmpty && publications.isEmpty && !probe) return;
    _statisticsDirty = false;
    _dirtyGames.clear();
    _dirtyPublications.clear();
    _publicationProbe = false;
    _running = true;
    var failed = false;
    try {
      // Independent domains: a comment failure must not starve release notices.
      final work = <Future<void>>[];
      if (statistics || games.isNotEmpty) {
        work.add(() async {
          try {
            await refresh(statistics, games);
          } catch (_) {
            failed = true;
            _statisticsDirty |= statistics;
            _dirtyGames.addAll(games);
          }
        }());
      }
      if ((probe || publications.isNotEmpty) && refreshPublications != null) {
        work.add(() async {
          try {
            await refreshPublications!(publications.values.toList());
          } catch (_) {
            failed = true;
            _publicationProbe |= probe;
            for (final entry in publications.entries) {
              final latest = _dirtyPublications[entry.key];
              if (latest == null || latest.revision < entry.value.revision) {
                _dirtyPublications[entry.key] = entry.value;
              }
            }
          }
        }());
      }
      await Future.wait(work);
      if (!_closed && active()) {
        _setError(failed ? '公共数据更新未完成，已保留上次结果' : null);
        if (!failed) _attempts = 0;
      }
    } finally {
      _running = false;
      if (!_closed &&
          active() &&
          (_statisticsDirty ||
              _dirtyGames.isNotEmpty ||
              _publicationProbe ||
              _dirtyPublications.isNotEmpty)) {
        if (!failed) {
          _schedule(const Duration(milliseconds: 250));
        } else if (_attempts < 5) {
          _schedule(Duration(seconds: 1 << _attempts++));
        }
      }
    }
  }

  Future<void> _connect() => _connection = (_connection ?? Future<void>.value())
      .catchError((Object _) {})
      .then((_) async {
        if (_closed || !active()) return;
        if (_paused) {
          await database.disconnect().timeout(const Duration(seconds: 5));
          return;
        }
        await database
            .connect(
              connector: _PublicConnector(client, () => !_closed && active()),
              options: SyncOptions(
                httpClient: httpClient ?? createDefaultAiHttpClient,
              ),
            )
            .timeout(const Duration(seconds: 15));
      });

  Future<void> setForeground(bool foreground) async {
    if (_closed) return;
    _paused = !foreground;
    if (_paused) {
      _timer?.cancel();
    } else {
      requestPublicationRefresh();
      requestRefresh(games: _versions.keys);
    }
    await _connect();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _timer?.cancel();
    await _rows?.cancel();
    await _status?.cancel();
    await _publications?.cancel();
    await _connection?.catchError((Object _) {});
    await database.close().timeout(const Duration(seconds: 5));
  }
}

class _PublicConnector extends PowerSyncBackendConnector {
  _PublicConnector(this.client, this.active);
  final AppJsonClient client;
  final bool Function() active;
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    if (!active()) throw StateError('Public service changed');
    final data = await client.request(
      '/v1/community/sync-credentials',
      body: {},
    );
    if (!active()) throw StateError('Public service changed');
    return boardSyncCredentials(
      client,
      data,
      userId: 'public:board_game_agent',
      syncScope: 'public',
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    if (await database.getCrudBatch(limit: 1) != null) {
      throw StateError('Public sync is read-only');
    }
  }
}
