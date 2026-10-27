import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import '../../identity/services/account_service.dart';
import '../models/ai_api_config.dart';

/// Account requests use the application API; BYOK keeps its existing transport.
/// SDK parsing, retries and aborts remain in app_ai_client/openai_dart.
final class AccountAiHttpClient extends http.BaseClient {
  AccountAiHttpClient({required this.account, required http.Client byok})
    : _byok = byok;
  final AccountService Function() account;
  final http.Client _byok;
  final _cancel = <void Function()>{};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('AI transport is closed');
    if (request.url.origin != AiApiConfig.accountTransportOrigin) {
      return _byok.send(request);
    }
    final service = account();
    final scope = service.currentAccountScope;
    final origin = service.serviceConfiguration?.origin;
    if (scope == null ||
        origin == null ||
        !service.dataScopeReady ||
        !service.isSignedIn) {
      throw http.ClientException('请先登录后使用 Loomex');
    }
    final operation = request.url.path.replaceFirst(RegExp(r'^/v1/'), '');
    if (!{
          'models',
          'responses',
          'responses/compact',
          'chat/completions',
        }.contains(operation) ||
        request.url.hasQuery ||
        !{'GET', 'POST'}.contains(request.method)) {
      throw http.ClientException('Loomex operation is unavailable');
    }
    bool valid() =>
        !_closed &&
        identical(account(), service) &&
        service.currentAccountScope == scope &&
        service.dataScopeReady &&
        service.isSignedIn;
    final transport = createDefaultAiHttpClient();
    final abort = Completer<void>();
    void Function()? release;
    void cancel() {
      if (!abort.isCompleted) abort.complete();
      release?.call();
    }

    void changed() {
      if (!valid()) cancel();
    }

    _cancel.add(cancel);
    service.addListener(changed);
    var cleaned = false;
    void cleanup() {
      if (cleaned) return;
      cleaned = true;
      service.removeListener(changed);
      _cancel.remove(cancel);
      transport.close();
    }

    release = cleanup;

    try {
      final sourceAbort = request is http.Abortable
          ? request.abortTrigger
          : null;
      if (sourceAbort != null) unawaited(sourceAbort.then((_) => cancel()));
      final token = await service.aiAccessToken();
      if (!valid() || abort.isCompleted) {
        throw http.ClientException('Loomex request cancelled');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in request.finalize()) {
        if (!valid() || abort.isCompleted) {
          throw http.ClientException('Loomex request cancelled');
        }
        if (bytes.length + chunk.length > 512 * 1024) {
          throw http.ClientException('AI request exceeds its size limit');
        }
        bytes.add(chunk);
      }
      final prefix = service.usesWebAccount ? '/api' : '';
      final target = origin.resolve(
        '$prefix/v1/apps/board_game_agent/ai/loomex/v1/$operation',
      );
      final forward =
          http.AbortableRequest(
              request.method,
              target,
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers.addAll({
              for (final entry in request.headers.entries)
                if ({
                  'content-type',
                  'accept',
                  'openai-beta',
                  'idempotency-key',
                }.contains(entry.key.toLowerCase()))
                  entry.key: entry.value,
              'Authorization': 'Bearer $token',
              'X-App-ID': 'board_game_agent',
            })
            ..bodyBytes = bytes.takeBytes();
      final response = await transport.send(forward);
      if (response.statusCode == 401 || response.statusCode == 403) {
        cleanup();
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'error': {
                  'message': 'loomex_session_expired',
                  'type': 'authentication_error',
                  'code': 'loomex_session_expired',
                },
              }),
            ),
          ),
          response.statusCode,
          headers: {'content-type': 'application/json'},
        );
      }
      Stream<List<int>> content() async* {
        try {
          await for (final chunk in response.stream) {
            if (!valid() || abort.isCompleted) {
              throw http.ClientException('Loomex request cancelled');
            }
            yield chunk;
          }
        } finally {
          cleanup();
        }
      }

      return http.StreamedResponse(
        content(),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
        contentLength: response.contentLength,
        isRedirect: response.isRedirect,
      );
    } catch (_) {
      cleanup();
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final cancel in _cancel.toList()) {
      cancel();
    }
    _byok.close();
  }
}
