import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Web-only injection into the existing SDK. All model protocols, retries,
/// stream parsing and cancellation remain owned by app_ai_client/openai_dart.
final class WebAiHttpClient extends http.BaseClient {
  WebAiHttpClient({http.Client? inner, Uri? site})
    : _inner = inner ?? http.Client(),
      _site = site ?? Uri.base;
  final http.Client _inner;
  final Uri _site;
  static const _headers = {
    'authorization',
    'api-key',
    'x-api-key',
    'content-type',
    'accept',
    'openai-beta',
    'openai-organization',
    'openai-project',
    'idempotency-key',
  };
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('AI transport is closed');
    final upstream = request.url;
    if (upstream.scheme != 'https' ||
        upstream.host.isEmpty ||
        upstream.userInfo.isNotEmpty) {
      throw http.ClientException('Web AI requires an HTTPS provider address');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request.finalize()) {
      if (bytes.length + chunk.length > 16 * 1024 * 1024) {
        throw http.ClientException('AI request exceeds the gateway size limit');
      }
      bytes.add(chunk);
    }
    final forward =
        http.AbortableRequest(
            request.method,
            _site.resolve('/api/ai/request'),
            abortTrigger: request is http.Abortable
                ? request.abortTrigger
                : null,
          )
          ..followRedirects = false
          ..headers.addAll({
            for (final entry in request.headers.entries)
              if (_headers.contains(entry.key.toLowerCase()))
                entry.key: entry.value,
            'X-Board-Game-Request': '1',
            'X-BGA-AI-Target': upstream.toString(),
          })
          ..bodyBytes = bytes.takeBytes();
    return _inner.send(forward);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
  }
}
