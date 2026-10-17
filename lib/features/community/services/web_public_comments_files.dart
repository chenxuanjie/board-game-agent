import 'dart:async';
import 'dart:convert';

import 'package:app_identity/app_identity.dart';
import 'package:http/http.dart' as http;

/// Same snapshot protocol as native FileStation; the server owns authentication.
final class WebPublicCommentsFiles implements AccountPublicFiles {
  WebPublicCommentsFiles({required this.uid, http.Client? client, Uri? site})
    : _client = client ?? http.Client(),
      _site = site ?? Uri.base;
  @override
  final int uid;
  final http.Client _client;
  final Uri _site;
  Completer<void> _abort = Completer<void>();
  int _generation = 0;

  @override
  void cancelRequests() {
    _generation++;
    if (!_abort.isCompleted) _abort.complete();
    _abort = Completer<void>();
  }

  Future<Map<String, dynamic>> _request(
    String endpoint,
    String path, [
    String? content,
  ]) async {
    final generation = _generation;
    final request = http.AbortableRequest(
      content == null ? 'GET' : 'POST',
      _site
          .resolve('/api/comments/$endpoint')
          .replace(queryParameters: {'path': path}),
      abortTrigger: _abort.future,
    )..headers['X-Board-Game-Request'] = '1';
    if (content != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'content': content});
    }
    try {
      return await (() async {
        final response = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 4 * 1024 * 1024) {
            throw const PrivateFileException(PrivateFileFailure.unavailable);
          }
          bytes.addAll(chunk);
        }
        if (generation != _generation) {
          throw const PrivateFileException(PrivateFileFailure.cancelled);
        }
        if (response.statusCode != 200) {
          throw PrivateFileException(switch (response.statusCode) {
            401 => PrivateFileFailure.session,
            403 => PrivateFileFailure.denied,
            404 => PrivateFileFailure.missing,
            504 => PrivateFileFailure.timeout,
            _ => PrivateFileFailure.unavailable,
          });
        }
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      })().timeout(const Duration(seconds: 35));
    } on TimeoutException {
      cancelRequests();
      throw const PrivateFileException(PrivateFileFailure.timeout);
    } on http.RequestAbortedException {
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    } on http.ClientException {
      throw const PrivateFileException(PrivateFileFailure.network);
    }
  }

  @override
  Future<List<AccountPublicEntry>> entries(String relativePath) async {
    final value = await _request('entries', relativePath);
    return (value['entries'] as List)
        .map(
          (raw) => AccountPublicEntry(
            name: raw['name'] as String,
            directory: raw['directory'] as bool,
            ownerUid: raw['ownerUid'] as int,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<String> read(String relativePath) async =>
      (await _request('file', relativePath))['content'] as String;

  @override
  Future<void> replaceOwn(String relativePath, String content) async {
    if (uid <= 0 ||
        !RegExp('^u$uid/d[0-9a-f]{32}\\.json\$').hasMatch(relativePath)) {
      throw const PrivateFileException(PrivateFileFailure.denied);
    }
    await _request('file', relativePath, content);
  }
}
