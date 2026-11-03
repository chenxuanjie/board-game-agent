import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';

/// Conservative preflight bound; the existing HTTP transports remain the
/// authority on actual encoded bytes. No request serialization is replaced.
class ResponsesRequestBudget {
  static const accountBytes = 512 * 1024;
  static const byokBytes = 16 * 1024 * 1024;
  // SDK-generated field names, optional controls, stream flags and tool config.
  static const envelopeReserve = 8 * 1024;

  static int upperBound(ResponsesRequest request) =>
      envelopeReserve +
      utf8
          .encode(
            jsonEncode({
              'model': request.endpoint.model,
              'instructions': request.instructions,
              'input': request.input.map((item) => item.toJson()).toList(),
              'schema': request.structuredOutput?.schema,
              'schema_name': request.structuredOutput?.name,
              'schema_description': request.structuredOutput?.description,
              'reasoning': request.reasoningEffort,
              'service_tier': request.serviceTier,
              'tools': request.tools
                  .map((tool) => tool.searchContextSize)
                  .toList(),
              'context_management': request.contextManagement
                  .map(
                    (item) => {
                      'type': item.type,
                      'compact_threshold': item.compactThreshold,
                    },
                  )
                  .toList(),
            }),
          )
          .length;

  static bool fits(ResponsesRequest request, int limit) =>
      upperBound(request) <= limit;
}

class ResponsesRequestTooLarge implements Exception {
  const ResponsesRequestTooLarge();
  @override
  String toString() => 'request_too_large';
}
