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
    try {
      final next = <int, Map<String, SyncOperation>>{};
      String? published;
      final accounts = await files.entries('');
      check();
      if (accounts.length > 1000) throw const FormatException('公共账号数量超过上限');
      var snapshots = 0;
      for (final account in accounts) {
        if (!account.directory ||
            !RegExp(r'^u[1-9][0-9]*$').hasMatch(account.name) ||
            account.ownerUid.toString() != account.name.substring(1)) {
          throw const FormatException('公共账号目录身份不匹配');
        }
        final heads = next.putIfAbsent(account.ownerUid, () => {});
        String? dataset;
        final records = await files.entries(account.name);
        check();
        if (records.length > 128 || (snapshots += records.length) > 2000) {
          throw const FormatException('公共设备数量超过上限');
        }
        for (final record in records) {
          if (record.directory ||
              record.ownerUid != account.ownerUid ||
              !RegExp(r'^d[0-9a-f]{32}\.json$').hasMatch(record.name)) {
            throw const FormatException('公共记录身份不匹配');
          }
          final snapshot = await files.read('${account.name}/${record.name}');
          final data = jsonDecode(snapshot);
          check();
          if (account.ownerUid == files.uid &&
              record.name == '${local.deviceId}.json') {
            published = snapshot;
          }
          if (data is! Map ||
              data['version'] != 1 ||
              data['uid'] != account.ownerUid ||
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
      final own = next[files.uid];
      check();
      if (own != null && own.isNotEmpty) {
        await local.applyPublicReactions(own.values);
      }
      final text = jsonEncode({
        'version': 1,
        'uid': files.uid,
        'device': local.deviceId,
        'operations': local.publicReactions.map((op) => op.toJson()).toList(),
      });
      if (utf8.encode(text).length > 512 * 1024) {
        throw const FormatException('公共记录超过上限');
      }
      if (text != published) {
        check();
        await files.replaceOwn('u${files.uid}/${local.deviceId}.json', text);
        check();
      }
      _heads = next; // Replace only a complete, validated read and write.
    } catch (failure) {
      if (generation != _generation) rethrow;
      error = switch (failure) {
        PrivateFileException(failure: PrivateFileFailure.missing) =>
          '公共目录尚未配置，请在 NAS 设置共享目录权限。',
        PrivateFileException(failure: PrivateFileFailure.denied) =>
          '公共目录权限不符合要求：所有账号可读，各账号只能修改自己的记录。',
        PrivateFileException(failure: PrivateFileFailure.session) =>
          '登录已过期，请重新登录。',
        FormatException() || SyncProtocolException() => '公共记录需要检查，已保留上次统计。',
        _ => '公共同步未完成，请检查连接后重试。',
      };
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

final class AccountReactionRemote implements RemoteGameVoteStore {
  AccountReactionRemote({
    required this.scope,
    required this.namespace,
    required this.reactions,
    required this.refresh,
  });
  @override
  final String scope;
  final String namespace;
  final AccountPublicReactions reactions;
  final Future<void> Function() refresh;
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
