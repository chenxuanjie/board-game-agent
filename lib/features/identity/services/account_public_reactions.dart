import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:webdav_sync/webdav_sync.dart';
import '../../games/models/game_vote_record.dart';
import '../../games/services/remote_game_vote_store.dart';
import 'account_sync_store.dart';
import 'reaction_sync_diagnostics.dart';

/// A bounded diagnostic, never a dump of account payloads or credentials.
final class PublicRecordFailure implements Exception {
  const PublicRecordFailure(this.path, this.reason);
  final String path, reason;
  @override
  String toString() => 'PublicRecordFailure($path, $reason)';
}

/// Publication depends only on this UID. Global reads have their own transport,
/// cancellation generation and cache, and never gate an upload acknowledgement.
final class AccountPublicReactions {
  AccountPublicReactions(
    this.files, {
    AccountPublicFiles? rankingFiles,
    DateTime Function()? now,
  }) : rankingFiles = rankingFiles ?? files,
       _now = now ?? DateTime.now;
  final AccountPublicFiles files, rankingFiles;
  final DateTime Function() _now;
  String? error;
  PublicRecordFailure? diagnostic;
  bool submissionConfirmed = false;
  String? confirmedFingerprint;
  Set<String>? _confirmedFavorites, _confirmedVotes;
  Map<int, Map<String, SyncOperation>> _heads = {};
  final _cache =
      <String, ({String revision, String text, DateTime checkedAt})>{};
  int _cacheBytes = 0;
  static const _maxCacheBytes = 8 * 1024 * 1024;
  void _dropCached(String path) {
    final previous = _cache.remove(path);
    if (previous != null) _cacheBytes -= previous.text.length * 2;
  }

  void _remember(String path, String revision, String text) {
    _dropCached(path);
    final bytes = text.length * 2;
    while (_cache.isNotEmpty && _cacheBytes + bytes > _maxCacheBytes) {
      _dropCached(_cache.keys.first);
    }
    if (bytes <= _maxCacheBytes) {
      _cache[path] = (revision: revision, text: text, checkedAt: _now());
      _cacheBytes += bytes;
    }
  }

  int _publishGeneration = 0, _readGeneration = 0;

  bool confirmsSelection(String namespace, Iterable<String> selection) {
    final confirmed = namespace == GameVoteBallot.campaign
        ? _confirmedVotes
        : _confirmedFavorites;
    final current = selection.toSet();
    return confirmed != null &&
        confirmed.length == current.length &&
        confirmed.containsAll(current);
  }

  void _confirm(List<SyncOperation> operations, String fingerprint) {
    confirmedFingerprint = fingerprint;
    submissionConfirmed = true;
    _confirmedFavorites = {
      for (final op in operations)
        if (op.entityType == 'favorite' &&
            op.operation == SyncOperationType.upsert)
          op.entityId,
    };
    _confirmedVotes = {
      for (final op in operations)
        if (op.entityType == 'vote' && op.operation == SyncOperationType.upsert)
          op.entityId,
    };
  }

  void cancelPublication() {
    _publishGeneration++;
    files.cancelRequests();
  }

  void cancelRankings() {
    _readGeneration++;
    rankingFiles.cancelRequests();
  }

  void cancel() {
    cancelPublication();
    cancelRankings();
  }

  /// No root listing or foreign UID read occurs on this path. Own records are
  /// always read fresh, so a metadata cache cannot resurrect a cancellation.
  Future<void> publish(
    AccountSyncLocalStore local, {
    ReactionTrace? trace,
  }) async {
    final generation = _publishGeneration;
    void check() {
      if (generation != _publishGeneration) {
        throw const PrivateFileException(PrivateFileFailure.cancelled);
      }
    }

    submissionConfirmed = false;
    for (var round = 0; round < 3; round++) {
      check();
      final own = await _readAccount(
        files,
        files.uid,
        check,
        ownMissing: true,
        trace: trace,
      );
      check();
      _observeSelection(trace, own.heads.values, '发布前远端状态');
      if (own.heads.isNotEmpty) {
        await _step(
          trace,
          '合并自己账号的远端版本',
          () => local.applyPublicReactions(own.heads.values, check: check),
        );
      }
      await _step(
        trace,
        '持久化待发布版本',
        () => local.captureReactions(check: check),
      );
      check();
      final fingerprint = local.publicFingerprint;
      final operations = local.publicReactions;
      final text = jsonEncode({
        'version': 1,
        'uid': files.uid,
        'device': local.deviceId,
        'operations': operations.map((op) => op.toJson()).toList(),
      });
      if (utf8.encode(text).length > 512 * 1024) {
        throw const FormatException('公共记录超过上限');
      }
      final path = 'u${files.uid}/${local.deviceId}.json';
      if (own.texts['${local.deviceId}.json'] != text) {
        final verified = files is VerifiedAccountPublicFiles;
        await _step(
          trace,
          verified ? '上传并读回核对' : '上传公共快照',
          () => files.replaceOwn(path, text),
          detail: '$path · ${utf8.encode(text).length} B',
        );
        check();
        if (!verified) {
          final confirmed = await _step(
            trace,
            '读回核对上传内容',
            () => files.read(path),
            detail: path,
          );
          check();
          if (confirmed != text) throw const SyncProtocolException('公共写入核对失败');
        }
        _dropCached(path);
      } else {
        trace?.event('远端已是当前版本，无须重复上传');
      }
      _observeSelection(trace, operations, '远端已核对状态');
      _confirm(operations, fingerprint);
      await local.captureReactions(check: check);
      check();
      if (local.publicFingerprint == fingerprint) return;
      submissionConfirmed = false;
    }
    throw const SyncProtocolException('收藏或投票仍有新变更待提交');
  }

  /// Atomic complete totals: a bad snapshot preserves previous totals. Cache
  /// only versioned foreign records; force bypasses it for manual refresh.
  Future<void> refresh(
    AccountSyncLocalStore local, {
    bool force = false,
    ReactionTrace? trace,
  }) async {
    final generation = _readGeneration;
    void check() {
      if (generation != _readGeneration) {
        throw const PrivateFileException(PrivateFileFailure.cancelled);
      }
    }

    diagnostic = null;
    final next = <int, Map<String, SyncOperation>>{};
    final seenPaths = <String>{};
    final accounts = await _step(
      trace,
      '枚举公共账号目录',
      () => rankingFiles.entries(''),
    );
    trace?.event(
      '公共目录返回',
      detail: '${accounts.length} 个账号 · ${force ? '强制重读' : '允许版本缓存'}',
    );
    check();
    if (accounts.length > 1000) throw const FormatException('公共账号数量超过上限');
    var snapshots = 0;
    for (final account in accounts) {
      if (!account.directory ||
          !RegExp(r'^u[1-9][0-9]*$').hasMatch(account.name)) {
        throw PublicRecordFailure(account.name, 'invalid-account-directory');
      }
      final uid = int.parse(account.name.substring(1));
      final result = await _readAccount(
        rankingFiles,
        uid,
        check,
        cached: uid != files.uid && !force,
        seenPaths: seenPaths,
        remaining: 2000 - snapshots,
        trace: trace,
      );
      snapshots += result.texts.length;
      if (snapshots > 2000) throw const FormatException('公共设备数量超过上限');
      next[uid] = result.heads;
    }
    check();
    final own = next[files.uid];
    if (own != null) _observeSelection(trace, own.values, '本轮读到的自己账号状态');
    if (own != null && own.isNotEmpty) {
      await local.applyPublicReactions(own.values, check: check);
    }
    await local.captureReactions(check: check);
    check();
    _heads = next;
    trace?.event(
      '全部公共记录校验通过',
      status: ReactionTraceStatus.success,
      detail: '${next.length} 个账号 · $snapshots 个快照',
    );
    for (final path
        in _cache.keys.where((path) => !seenPaths.contains(path)).toList()) {
      _dropCached(path);
    }
  }

  Future<({Map<String, SyncOperation> heads, Map<String, String> texts})>
  _readAccount(
    AccountPublicFiles source,
    int uid,
    void Function() check, {
    bool ownMissing = false,
    bool cached = false,
    Set<String>? seenPaths,
    int remaining = 2000,
    ReactionTrace? trace,
  }) async {
    final folder = 'u$uid';
    List<AccountPublicEntry> records;
    try {
      records = await _step(
        trace,
        '枚举账号设备记录',
        () => source.entries(folder),
        detail: folder,
      );
    } on PrivateFileException catch (failure) {
      if (!ownMissing || failure.failure != PrivateFileFailure.missing) rethrow;
      check();
      trace?.event('自己账号尚无公共目录', detail: folder);
      return (heads: <String, SyncOperation>{}, texts: <String, String>{});
    }
    check();
    if (records.length > 128 || records.length > remaining) {
      throw PublicRecordFailure(folder, 'device-limit');
    }
    final heads = <String, SyncOperation>{}, texts = <String, String>{};
    String? dataset;
    // Bounded IO batches. Deterministic merging happens after each batch; errors
    // never install a partial account or partial global totals.
    for (var offset = 0; offset < records.length; offset += 4) {
      final batch = records.skip(offset).take(4).toList();
      final loaded = await Future.wait(
        batch.map((record) async {
          final path = '$folder/${record.name}';
          if (record.directory ||
              record.ownerUid != uid ||
              !RegExp(r'^d[0-9a-f]{32}\.json$').hasMatch(record.name)) {
            throw PublicRecordFailure(path, 'invalid-owner-or-name');
          }
          seenPaths?.add(path);
          final previous = _cache[path];
          final reuse =
              cached &&
              record.revision != null &&
              previous?.revision == record.revision &&
              _now().difference(previous!.checkedAt) <
                  const Duration(seconds: 60);
          if (reuse) trace?.event('复用已校验快照缓存', detail: path);
          final text = reuse
              ? previous.text
              : await _step(
                  trace,
                  '读取并校验快照所有者',
                  () => source.read(path),
                  detail: path,
                );
          check();
          return (record: record, path: path, text: text, reuse: reuse);
        }),
      );
      check();
      for (final item in loaded) {
        try {
          if (utf8.encode(item.text).length > 512 * 1024) {
            throw const FormatException('size');
          }
          final data = jsonDecode(item.text);
          if (data is! Map ||
              data['version'] != 1 ||
              data['uid'] != uid ||
              '${data['device']}.json' != item.record.name ||
              data['operations'] is! List ||
              (data['operations'] as List).length > 8192) {
            throw const FormatException('snapshot');
          }
          for (final raw in data['operations'] as List) {
            final op = SyncOperation.fromJson(
              Map<String, Object?>.from(raw as Map),
            );
            dataset ??= op.datasetId;
            if (op.datasetId != dataset ||
                !{'favorite', 'vote'}.contains(op.entityType) ||
                !GameVoteBallot.slugPattern.hasMatch(op.entityId)) {
              throw const FormatException('operation');
            }
            if (op.payload != null &&
                (op.entityType == 'favorite'
                    ? op.payload!.keys.any(
                            (key) => key != 'gameSlug' && key != 'createdAt',
                          ) ||
                          op.payload!['gameSlug'] != op.entityId ||
                          DateTime.tryParse(
                                op.payload!['createdAt'] as String? ?? '',
                              ) ==
                              null
                    : op.payload!.length != 2 ||
                          op.payload!['slug'] != op.entityId ||
                          op.payload!['campaign'] != GameVoteBallot.campaign)) {
              throw const FormatException('payload');
            }
            final key = '${op.entityType}|${op.entityId}';
            if (AccountSyncLocalStore.operationWins(op, heads[key])) {
              heads[key] = op;
            }
          }
          texts[item.record.name] = item.text;
          if (cached && item.record.revision != null && !item.reuse) {
            _remember(item.path, item.record.revision!, item.text);
          }
        } catch (_) {
          diagnostic = PublicRecordFailure(item.path, 'invalid-snapshot');
          throw diagnostic!;
        }
      }
    }
    return (heads: heads, texts: texts);
  }

  Future<T> _step<T>(
    ReactionTrace? trace,
    String label,
    Future<T> Function() work, {
    String detail = '',
  }) => trace == null ? work() : trace.measure(label, work, detail: detail);

  void _observeSelection(
    ReactionTrace? trace,
    Iterable<SyncOperation> operations,
    String label,
  ) {
    if (trace == null) return;
    final favorites = {
      for (final op in operations)
        if (op.entityType == 'favorite') op.entityId: op,
    };
    trace.event(
      label,
      detail:
          '${favorites.values.where((op) => op.operation == SyncOperationType.upsert).length} 款喜欢；取消标记 ${favorites.values.where((op) => op.operation == SyncOperationType.delete).length} 项',
    );
    for (final slug in trace.owner.watchedSlugs) {
      final op = favorites[slug];
      trace.event(
        label,
        detail:
            '$slug：${op == null
                ? '无远端记录'
                : op.operation == SyncOperationType.upsert
                ? '喜欢'
                : '已取消（删除标记）'}${op == null ? '' : ' · 版本 ${op.logicalClock}'}',
      );
    }
  }

  static String describe(Object failure) => switch (failure) {
    PrivateFileException(failure: PrivateFileFailure.missing) =>
      '公共目录不存在，请由管理员创建后重试。',
    PrivateFileException(
      failure: PrivateFileFailure.denied,
      operation: 'directory-create',
    ) =>
      '无法创建账号公共目录，请检查创建权限。',
    PrivateFileException(
      failure: PrivateFileFailure.denied,
      operation: 'public-metadata',
    ) =>
      'NAS 返回的公共记录身份信息不完整。',
    PrivateFileException(
      failure: PrivateFileFailure.denied,
      operation: 'public-owner',
    ) =>
      '公共记录的所有者与账号不匹配。',
    PrivateFileException(failure: PrivateFileFailure.denied) =>
      'NAS 拒绝读写公共数据，请检查当前账号的访问权限。',
    PrivateFileException(failure: PrivateFileFailure.session) => '登录已过期，请重新登录。',
    FormatException() ||
    SyncProtocolException() ||
    PublicRecordFailure() => '公共记录需要检查，已保留上次统计。',
    _ => '公共同步未完成，请检查连接后重试。',
  };

  /// Compatibility composition; the app coordinator uses the two lanes directly.
  Future<void> synchronize(AccountSyncLocalStore local) async {
    error = null;
    try {
      await publish(local);
      await refresh(local);
    } catch (failure) {
      error = describe(failure);
      rethrow;
    }
  }

  List<GameVoteBallot> ballots(String namespace) => [
    for (final account in _heads.entries)
      if (account.key != files.uid)
        GameVoteBallot(
          deviceId: sha256Json(account.key).substring(0, 32),
          namespace: namespace,
          games: [
            for (final op in account.value.values)
              if (op.entityType ==
                      (namespace == GameVoteBallot.campaign
                          ? 'vote'
                          : 'favorite') &&
                  op.operation == SyncOperationType.upsert)
                op.entityId,
          ],
        ),
  ];
}

extension AccountPublicCounts on AccountPublicReactions {
  /// What the completed scan actually observed, including our UID. This is
  /// distinct from UI totals, which overlay a saved, possibly unpublished intent.
  int observedRemoteCount(String namespace, String slug) => _heads.values
      .where(
        (heads) =>
            heads['${namespace == GameVoteBallot.campaign ? 'vote' : 'favorite'}|$slug']
                ?.operation ==
            SyncOperationType.upsert,
      )
      .length;

  Map<String, int> counts(String namespace) {
    final result = <String, int>{};
    for (final ballot in ballots(namespace)) {
      for (final slug in ballot.games) {
        result[slug] = (result[slug] ?? 0) + 1;
      }
    }
    return result;
  }
}

final class AccountReactionRemote implements CoordinatedGameVoteStore {
  AccountReactionRemote({
    required this.scope,
    required this.namespace,
    required this.reactions,
    required this.refresh,
    required this.publish,
    required this.isEnabled,
  });
  @override
  final String scope;
  final String namespace;
  final AccountPublicReactions reactions;
  final Future<void> Function() refresh, publish;
  final bool Function() isEnabled;
  @override
  bool get enabled => isEnabled();
  @override
  Future<void> synchronize() => refresh();
  @override
  Future<void> upload(GameVoteBallot ballot) async {
    if (ballot.namespace != namespace) throw StateError('投票范围不匹配');
    await publish();
  }

  @override
  Future<List<GameVoteBallot>> readBallots() async =>
      reactions.ballots(namespace);
  @override
  void close() {}
}
