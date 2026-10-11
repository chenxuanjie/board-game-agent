import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:webdav_sync/webdav_sync.dart';
import '../../games/models/game_vote_record.dart';
import '../../games/services/remote_game_vote_store.dart';
import 'account_sync_store.dart';

/// Each UID contributes once per game. Device snapshots carry the same causal
/// operations as private sync, so cancellations survive stale/offline devices.
final class AccountPublicReactions {
  AccountPublicReactions(this.files);
  final AccountPublicFiles files;
  String? error;
  bool submissionConfirmed = false;
  String? confirmedFingerprint;
  Set<String>? _confirmedFavorites, _confirmedVotes;
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

  Map<int, Map<String, SyncOperation>> _heads = {};
  int _generation = 0;
  void cancel() {
    _generation++;
    files.cancelRequests();
  }

  Future<void> synchronize(AccountSyncLocalStore local) async {
    final generation = _generation;
    void check() {
      if (generation != _generation) {
        throw const PrivateFileException(PrivateFileFailure.cancelled);
      }
    }

    error = null;
    submissionConfirmed = false;
    try {
      var snapshot = await _readAll(local.deviceId, check);
      for (var round = 0; round < 3; round++) {
        final own = snapshot.heads[files.uid];
        if (own != null && own.isNotEmpty) {
          await local.applyPublicReactions(own.values, check: check);
          check();
        }
        await local.captureReactions(check: check);
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
        if (text != snapshot.published) {
          check();
          final path = 'u${files.uid}/${local.deviceId}.json';
          await files.replaceOwn(path, text);
          check();
          // A successful upload response is not sufficient: read our file back.
          final confirmed = await files.read(path);
          check();
          if (confirmed != text) {
            throw const SyncProtocolException('公共写入核对失败');
          }
          _confirm(operations, fingerprint);
          // Read after publishing so concurrent accounts contribute to totals.
          snapshot = await _readAll(local.deviceId, check);
        } else {
          _confirm(operations, fingerprint);
        }
        check();
        final latestOwn = snapshot.heads[files.uid];
        if (latestOwn != null && latestOwn.isNotEmpty) {
          await local.applyPublicReactions(latestOwn.values, check: check);
          check();
        }
        await local.captureReactions(check: check);
        check();
        if (local.publicFingerprint == fingerprint) {
          _heads = snapshot.heads;
          return;
        }
        // A local click or another device's newer tombstone arrived in flight.
        // Publish the new version before confirming this task, with a bound.
        submissionConfirmed = false;
      }
      throw const SyncProtocolException('收藏或投票仍有新变更待提交');
    } catch (failure) {
      if (generation != _generation) rethrow;
      error = switch (failure) {
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
        PrivateFileException(failure: PrivateFileFailure.session) =>
          '登录已过期，请重新登录。',
        FormatException() || SyncProtocolException() => '公共记录需要检查，已保留上次统计。',
        _ => '公共同步未完成，请检查连接后重试。',
      };
      rethrow;
    }
  }

  Future<({Map<int, Map<String, SyncOperation>> heads, String? published})>
  _readAll(String deviceId, void Function() check) async {
    final next = <int, Map<String, SyncOperation>>{};
    String? published;
    final accounts = await files.entries('');
    check();
    if (accounts.length > 1000) throw const FormatException('公共账号数量超过上限');
    var snapshots = 0;
    for (final account in accounts) {
      if (!account.directory ||
          !RegExp(r'^u[1-9][0-9]*$').hasMatch(account.name)) {
        throw const FormatException('公共账号目录身份不匹配');
      }
      // UID directory names identify the namespace, including folders created
      // by an administrator. Each snapshot must still be owned by that UID.
      final accountUid = int.parse(account.name.substring(1));
      final heads = next.putIfAbsent(accountUid, () => {});
      String? dataset;
      final records = await files.entries(account.name);
      check();
      if (records.length > 128 || (snapshots += records.length) > 2000) {
        throw const FormatException('公共设备数量超过上限');
      }
      for (final record in records) {
        if (record.directory ||
            record.ownerUid != accountUid ||
            !RegExp(r'^d[0-9a-f]{32}\.json$').hasMatch(record.name)) {
          throw const FormatException('公共记录身份不匹配');
        }
        final snapshot = await files.read('${account.name}/${record.name}');
        final data = jsonDecode(snapshot);
        check();
        if (accountUid == files.uid && record.name == '$deviceId.json') {
          published = snapshot;
        }
        if (data is! Map ||
            data['version'] != 1 ||
            data['uid'] != accountUid ||
            '${data['device']}.json' != record.name ||
            data['operations'] is! List ||
            (data['operations'] as List).length > 8192) {
          throw const FormatException('公共记录格式错误');
        }
        for (final raw in data['operations'] as List) {
          final op = SyncOperation.fromJson(
            Map<String, Object?>.from(raw as Map),
          );
          dataset ??= op.datasetId;
          if (op.datasetId != dataset ||
              !{'favorite', 'vote'}.contains(op.entityType) ||
              !GameVoteBallot.slugPattern.hasMatch(op.entityId)) {
            throw const FormatException('公共记录类型错误');
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
            throw const FormatException('公共记录内容错误');
          }
          final key = '${op.entityType}|${op.entityId}';
          if (AccountSyncLocalStore.operationWins(op, heads[key])) {
            heads[key] = op;
          }
        }
      }
    }
    return (heads: next, published: published);
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
    required this.isEnabled,
  });
  @override
  final String scope;
  final String namespace;
  final AccountPublicReactions reactions;
  final Future<void> Function() refresh;
  final bool Function() isEnabled;
  @override
  bool get enabled => isEnabled();
  @override
  Future<void> synchronize() => refresh();
  @override
  Future<void> upload(GameVoteBallot ballot) async {
    if (ballot.namespace != namespace) throw StateError('投票范围不匹配');
    await refresh();
    if (reactions.error != null) throw StateError('公共同步未完成');
  }

  @override
  Future<List<GameVoteBallot>> readBallots() async =>
      reactions.ballots(namespace);
  @override
  void close() {} // Session and cancellation belong to AccountService.
}
