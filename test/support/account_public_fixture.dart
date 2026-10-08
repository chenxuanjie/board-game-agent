import 'dart:async';
import 'package:app_identity/app_identity.dart';

class PublicFixtureHub {
  final objects = <String, ({int owner, String text})>{};
  final directoryOwners = <String, int>{};
  PrivateFileFailure? failure;
  Completer<void>? readGate;
  int writes = 0;
}

class MemoryPublicFiles implements AccountPublicFiles {
  MemoryPublicFiles(this.hub, this.uid);
  final PublicFixtureHub hub;
  @override
  final int uid;
  @override
  void cancelRequests() {}
  void check() {
    if (hub.failure != null) throw PrivateFileException(hub.failure!);
  }

  @override
  Future<List<AccountPublicEntry>> entries(String relativePath) async {
    check();
    final result = <String, AccountPublicEntry>{};
    for (final entry in hub.objects.entries) {
      final prefix = relativePath.isEmpty ? '' : '$relativePath/';
      if (!entry.key.startsWith(prefix)) continue;
      final tail = entry.key.substring(prefix.length);
      final pieces = tail.split('/');
      result[pieces.first] = AccountPublicEntry(
        name: pieces.first,
        directory: pieces.length > 1,
        ownerUid: pieces.length > 1
            ? hub.directoryOwners[pieces.first] ?? entry.value.owner
            : entry.value.owner,
      );
    }
    return result.values.toList();
  }

  @override
  Future<String> read(String relativePath) async {
    check();
    await hub.readGate?.future;
    return hub.objects[relativePath]!.text;
  }

  @override
  Future<void> replaceOwn(String relativePath, String content) async {
    check();
    if (!relativePath.startsWith('u$uid/')) throw StateError('wrong owner');
    hub.writes++;
    hub.objects[relativePath] = (owner: uid, text: content);
  }
}
