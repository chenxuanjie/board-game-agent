import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';

import '../models/app_language.dart';
import '../models/game_info.dart';
import 'board_game_prompt_builder.dart';
import 'board_game_question_router.dart';

/// Resolves only the questions the local router could not classify safely.
///
/// The classifier is intentionally tiny and non-streaming. Its output is a
/// routing decision, never user-visible answer text. If the provider rejects
/// structured output or returns invalid JSON, callers receive their supplied
/// deterministic fallback instead of failing the chat request.
class BoardGameQuestionClassifier {
  static const Duration _classificationTimeout = Duration(seconds: 8);

  BoardGameQuestionClassifier({BoardGamePromptBuilder? promptBuilder})
    : _promptBuilder = promptBuilder ?? BoardGamePromptBuilder();

  final BoardGamePromptBuilder _promptBuilder;

  Future<BoardGameQuestionRoutingDecision> classifyResponses({
    required ResponsesAiClient client,
    required AiEndpointConfig endpoint,
    required AppLanguage language,
    required GameInfo game,
    required bool useGlobalMode,
    bool useCurrentGameKnowledge = false,
    required String prompt,
    required BoardGameQuestionRoutingDecision fallback,
    String? reasoningEffort,
    String? serviceTier,
    Future<void>? abortTrigger,
  }) async {
    final ResponsesRequest request = ResponsesRequest(
      endpoint: endpoint,
      instructions: _promptBuilder.buildQuestionClassificationSystemPrompt(
        language: language,
        game: game,
        useGlobalMode: useGlobalMode,
        useCurrentGameKnowledge: useCurrentGameKnowledge,
      ),
      input: <ResponsesInputItem>[ResponsesTextInput(prompt)],
      maxOutputTokens: 160,
      reasoningEffort: reasoningEffort,
      serviceTier: serviceTier,
      structuredOutput: const ResponsesStructuredOutput.jsonSchema(
        name: 'question_route',
        description: 'Route for the current user question.',
        schema: <String, dynamic>{
          'type': 'object',
          'additionalProperties': false,
          'properties': <String, dynamic>{
            'route': <String, dynamic>{
              'type': 'string',
              'enum': <String>['general', 'game_knowledge'],
            },
            'confidence': <String, dynamic>{
              'type': 'string',
              'enum': <String>['high', 'low'],
            },
          },
          'required': <String>['route', 'confidence'],
        },
      ),
    );

    ResponsesResponse response;
    try {
      response = await client
          .complete(request, abortTrigger: abortTrigger)
          .timeout(_classificationTimeout);
    } catch (_) {
      return fallback;
    }
    final BoardGameQuestionRoutingDecision? parsed = _parse(response.text);
    return parsed ?? fallback;
  }

  Future<BoardGameQuestionRoutingDecision> classifyChat({
    required AiClient client,
    required AiEndpointConfig endpoint,
    required AppLanguage language,
    required GameInfo game,
    required bool useGlobalMode,
    bool useCurrentGameKnowledge = false,
    required String prompt,
    required BoardGameQuestionRoutingDecision fallback,
  }) async {
    final AiResponse response;
    try {
      response = await client
          .complete(
            AiRequest(
              endpoint: endpoint,
              messages: <AiMessage>[
                AiMessage.system(
                  _promptBuilder.buildQuestionClassificationSystemPrompt(
                    language: language,
                    game: game,
                    useGlobalMode: useGlobalMode,
                    useCurrentGameKnowledge: useCurrentGameKnowledge,
                  ),
                ),
                AiMessage.user(prompt),
              ],
              options: const AiGenerationOptions(
                temperature: 0,
                maxCompletionTokens: 160,
              ),
            ),
          )
          .timeout(_classificationTimeout);
    } catch (_) {
      return fallback;
    }
    return _parse(response.text) ?? fallback;
  }

  BoardGameQuestionRoutingDecision? _parse(String raw) {
    final Map<String, dynamic>? object = _decodeObject(raw);
    if (object == null) return null;
    final String route = '${object['route'] ?? ''}'.trim().toLowerCase();
    final BoardGameQuestionRoute? parsedRoute = switch (route) {
      'general' || 'ordinary' || 'chat' => BoardGameQuestionRoute.general,
      'game_knowledge' ||
      'game-knowledge' ||
      'game' ||
      'knowledge' => BoardGameQuestionRoute.gameKnowledge,
      _ => null,
    };
    if (parsedRoute == null) return null;
    final String confidence = '${object['confidence'] ?? 'low'}'
        .trim()
        .toLowerCase();
    return BoardGameQuestionRoutingDecision(
      route: parsedRoute,
      confidence: confidence == 'high'
          ? BoardGameQuestionConfidence.high
          : BoardGameQuestionConfidence.low,
      reason: 'model_classification',
      source: BoardGameQuestionDecisionSource.model,
    );
  }

  Map<String, dynamic>? _decodeObject(String raw) {
    final String cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    final dynamic direct = _tryDecode(cleaned);
    if (direct is Map) return Map<String, dynamic>.from(direct);

    final int start = cleaned.indexOf('{');
    final int end = cleaned.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    final dynamic embedded = _tryDecode(cleaned.substring(start, end + 1));
    if (embedded is Map) return Map<String, dynamic>.from(embedded);
    return null;
  }

  dynamic _tryDecode(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }
}
