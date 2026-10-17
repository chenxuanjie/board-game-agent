import 'dart:async';
import 'dart:convert';

import 'package:app_identity/app_identity.dart';
import 'package:http/http.dart' as http;

/// File transport only. AccountCloudSync retains journals, merge and retry rules.
final class WebSyncTransport {
  WebSyncTransport({
    required this.client,
    required this.site,
    required this.lane,
    required this.isActive,
    required this.uid,
  });
  final http.Client client;
  final Uri site;
  final String lane;
  final bool Function() isActive;
  final int uid;
  Completer<void> _abort = Completer<void>();
  int _generation = 0;

  void cancel() {
    _generation++;
    if (!_abort.isCompleted) _abort.complete();
    _abort = Completer<void>();
  }

  Future<Map<String, dynamic>> request(
    String action,
    String path, [
    String? content,
  ]) async {
    final generation = _generation;
    void check() {
      if (generation != _generation || !isActive()) {
        throw const PrivateFileException(PrivateFileFailure.cancelled);
      }
    }

    check();
    final request =
        http.AbortableRequest(
            content == null ? 'GET' : 'POST',
            site
                .resolve('/api/sync/$lane/$action')
                .replace(queryParameters: {'path': path}),
            abortTrigger: _abort.future,
          )
          ..headers.addAll({
            'X-Board-Game-Request': '1',
            'X-BGA-Account-UID': '$uid',
          });
    if (content != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'content': content});
    }
    try {
      return await (() async {
        final response = await client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          check();
          // JSON string escaping can expand an 8 MiB operation significantly.
          if (bytes.length + chunk.length > 50 * 1024 * 1024) {
            cancel();
            throw const PrivateFileException(PrivateFileFailure.unavailable);
          }
          bytes.addAll(chunk);
        }
        check();
        if (response.statusCode != 200) {
          throw PrivateFileException(switch (response.statusCode) {
            401 => PrivateFileFailure.session,
            403 => PrivateFileFailure.denied,
            404 => PrivateFileFailure.missing,
            507 => PrivateFileFailure.quota,
            504 => PrivateFileFailure.timeout,
            _ => PrivateFileFailure.unavailable,
          });
        }
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      })().timeout(const Duration(seconds: 35));
    } on TimeoutException {
      cancel();
      throw const PrivateFileException(PrivateFileFailure.timeout);
    } on http.RequestAbortedException {
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    } on http.ClientException {
      throw const PrivateFileException(PrivateFileFailure.network);
    } on FormatException {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    }
  }
}

final class WebPrivateSyncFiles implements AccountPrivateFiles {
  WebPrivateSyncFiles(this.transport);
  final WebSyncTransport transport;
  @override
  void cancelRequests() => transport.cancel();
  @override
  Future<List<({String name, bool directory})>> list(String path) async => [
    for (final raw
        in (await transport.request('entries', path))['entries'] as List)
      (name: raw['name'] as String, directory: raw['directory'] as bool),
  ];
  @override
  Future<String> read(String path) async =>
      (await transport.request('file', path))['content'] as String;
  @override
  Future<void> createImmutable(String path, String content) async {
    await transport.request('file', path, content);
  }
}

final class WebPublicSyncFiles implements AccountPublicFiles {
  WebPublicSyncFiles(this.transport, {required this.uid});
  final WebSyncTransport transport;
  @override
  final int uid;
  @override
  void cancelRequests() => transport.cancel();
  @override
  Future<List<AccountPublicEntry>> entries(String path) async => [
    for (final raw
        in (await transport.request('entries', path))['entries'] as List)
      AccountPublicEntry(
        name: raw['name'] as String,
        directory: raw['directory'] as bool,
        ownerUid: raw['ownerUid'] as int,
      ),
  ];
  @override
  Future<String> read(String path) async =>
      (await transport.request('file', path))['content'] as String;
  @override
  Future<void> replaceOwn(String path, String content) async {
    if (!RegExp('^u$uid/d[0-9a-f]{32}\\.json\$').hasMatch(path)) {
      throw const PrivateFileException(PrivateFileFailure.denied);
    }
    await transport.request('file', path, content);
  }
}
