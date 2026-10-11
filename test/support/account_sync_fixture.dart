import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:webdav_sync/webdav_sync.dart';
import 'package:board_game_agent/features/identity/services/account_sync_store.dart';
import 'package:board_game_agent/features/identity/services/account_sync_remote.dart';

AccountEntities cloneEntities(AccountEntities value) => {
  for (final entry in value.entries)
    entry.key: Map<String, Object?>.from(
      jsonDecode(jsonEncode(entry.value)) as Map,
    ),
};

class SyncDeviceFixture {
  SyncDeviceFixture({this.scope = 'account-a'});
  final String scope;
  AccountEntities entities = {};
  String? journal;
  bool failProjection = false;
  late AccountSyncLocalStore local;
  Future<void> start() async {
    local = AccountSyncLocalStore(
      datasetId: scope,
      readJournal: () async => journal,
      writeJournal: (value) async => journal = value,
      transaction: <T>(work) async =>
          work(cloneEntities(entities), (value) async {
            if (failProjection) throw StateError('injected projection failure');
            entities = cloneEntities(value);
          }),
    );
    await local.initialize();
  }

  Future<SyncResult> sync(AccountPrivateFiles files) async {
    await local.capture();
    return IncrementalSyncEngine(
      local: local,
      remote: AccountSyncRemoteStore(files: files, datasetId: scope),
      retryPolicy: const SyncRetryPolicy(maxAttempts: 2),
      sleep: (_) async {},
    ).synchronize();
  }
}

class MemoryPrivateFiles implements AccountPrivateFiles {
  final objects = <String, String>{};
  PrivateFileFailure? failure;
  // Opt in to an administrator-provisioned fixed folder with no device folders.
  bool fixedDirectoryOnly = false;
  int calls = 0;
  void check() {
    calls++;
    if (failure != null) throw PrivateFileException(failure!);
  }

  @override
  void cancelRequests() {}
  @override
  Future<List<({String name, bool directory})>> list(
    String relativePath,
  ) async {
    check();
    final entries = <String, bool>{};
    for (final path in objects.keys.where(
      (key) => key.startsWith('$relativePath/'),
    )) {
      final tail = path.substring(relativePath.length + 1);
      final slash = tail.indexOf('/');
      entries[slash < 0 ? tail : tail.substring(0, slash)] = slash >= 0;
    }
    return [
      for (final entry in entries.entries)
        (name: entry.key, directory: entry.value),
    ];
  }

  @override
  Future<String> read(String relativePath) async {
    check();
    return objects[relativePath] ??
        (throw const PrivateFileException(PrivateFileFailure.missing));
  }

  @override
  Future<void> createImmutable(String relativePath, String content) async {
    check();
    if (fixedDirectoryOnly &&
        relativePath.substring(0, relativePath.lastIndexOf('/')) !=
            'operations') {
      throw const PrivateFileException(PrivateFileFailure.missing);
    }
    objects.putIfAbsent(relativePath, () => content);
    if (objects[relativePath] != content) {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    }
  }
}
