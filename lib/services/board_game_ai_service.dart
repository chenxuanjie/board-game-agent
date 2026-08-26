import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/foundation.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/answer_source.dart';
import '../models/app_language.dart';
import '../models/asset_source_config.dart';
import '../models/board_game_ai_answer.dart';
import '../models/chat_message.dart';
import '../models/evidence_chunk.dart';
import '../models/game_info.dart';
import 'ai_service.dart';
import 'board_game_prompt_builder.dart';
import 'knowledge_answer_parser.dart';
import 'remote_asset_service.dart';
import 'rule_knowledge_retriever.dart';
import 'responses_rules_workflow.dart';

/// Application-level AI service for board-game questions.
///
/// Provider transport is delegated to [AiClient]. This service owns only the
/// board-game workflow: retrieve local rules, answer from evidence first, and
/// optionally fall back to general advice.
class BoardGameAiService implements AiService {
  static const int _maxKnowledgeCharsForDirectFallback = 12000;
  static const int _maxConversationMessages = 12;

  BoardGameAiService({
    required AiClient aiClient,
    RuleKnowledgeRetriever? knowledgeRetriever,
    BoardGamePromptBuilder? promptBuilder,
    KnowledgeAnswerParser? answerParser,
    ResponsesRulesWorkflow? responsesWorkflow,
  }) : _aiClient = aiClient,
       _knowledgeRetriever =
           knowledgeRetriever ?? const RuleKnowledgeRetriever(),
       _promptBuilder = promptBuilder ?? BoardGamePromptBuilder(),
       _answerParser = answerParser ?? KnowledgeAnswerParser(),
       _responsesWorkflow = responsesWorkflow;

  final AiClient _aiClient;
  final RuleKnowledgeRetriever _knowledgeRetriever;
  final BoardGamePromptBuilder _promptBuilder;
  final KnowledgeAnswerParser _answerParser;
  final ResponsesRulesWorkflow? _responsesWorkflow;

  @override
  Future<BoardGameAiAnswer> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
  }) async {
    if (_responsesEnabled(config)) {
      return _responsesWorkflow!.generateReply(
        prompt: prompt,
        language: language,
        game: game,
        answerMode: answerMode,
        useGlobalMode: useGlobalMode,
        config: config,
        assetSourceConfigs: assetSourceConfigs,
        remoteAssetService: remoteAssetService,
        conversationHistory: conversationHistory,
      );
    }
    final List<EvidenceChunk> evidence = await _knowledgeRetriever.retrieve(
      game: game,
      assetSourceConfigs: assetSourceConfigs,
      remoteAssetService: remoteAssetService,
    );
    final String knowledgeContext = _knowledgeRetriever.formatForPrompt(
      evidence,
    );
    final List<AiMessage> conversation = _buildConversationMessages(
      conversationHistory,
      prompt,
    );

    debugPrint(
      '[ai] generateReply game=${game.slug} global=$useGlobalMode mode=${answerMode.code} evidence=${evidence.length} knowledgeChars=${knowledgeContext.length}',
    );

    if (evidence.isEmpty) {
      debugPrint('[ai] no local knowledge loaded for ${game.slug}');
      if (answerMode == AiAnswerMode.knowledgeOnly) {
        return _unknownAnswer(language);
      }
      return _answerDirectlyWithGameContext(
        language: language,
        game: game,
        config: config,
        useGlobalMode: useGlobalMode,
        knowledgeContext: '',
        evidence: const <EvidenceChunk>[],
        conversation: conversation,
      );
    }

    final BoardGameAiAnswer knowledgeAnswer = await _answerFromKnowledgeOnly(
      language: language,
      game: game,
      config: config,
      knowledgeContext: knowledgeContext,
      evidence: evidence,
      conversation: conversation,
    );

    if (knowledgeAnswer.source == AnswerSource.rulebook) {
      debugPrint('[ai] answered from local knowledge for ${game.slug}');
      return knowledgeAnswer;
    }

    debugPrint('[ai] local knowledge insufficient for ${game.slug}');
    if (answerMode == AiAnswerMode.knowledgeOnly) {
      return knowledgeAnswer;
    }

    return _answerDirectlyWithGameContext(
      language: language,
      game: game,
      config: config,
      useGlobalMode: useGlobalMode,
      knowledgeContext: _knowledgeRetriever.formatForPrompt(
        evidence,
        maxChars: _maxKnowledgeCharsForDirectFallback,
      ),
      evidence: evidence,
      conversation: conversation,
    );
  }

  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    Future<void>? abortTrigger,
  }) async* {
    if (_responsesEnabled(config)) {
      yield* _responsesWorkflow!.streamReply(
        prompt: prompt,
        language: language,
        game: game,
        answerMode: answerMode,
        useGlobalMode: useGlobalMode,
        config: config,
        assetSourceConfigs: assetSourceConfigs,
        remoteAssetService: remoteAssetService,
        conversationHistory: conversationHistory,
        abortTrigger: abortTrigger,
      );
      return;
    }
    final List<EvidenceChunk> evidence = await _knowledgeRetriever.retrieve(
      game: game,
      assetSourceConfigs: assetSourceConfigs,
      remoteAssetService: remoteAssetService,
    );
    final String knowledgeContext = _knowledgeRetriever.formatForPrompt(
      evidence,
    );
    final List<AiMessage> conversation = _buildConversationMessages(
      conversationHistory,
      prompt,
    );

    if (evidence.isNotEmpty) {
      final String systemPrompt = _promptBuilder.buildKnowledgeOnlySystemPrompt(
        language: language,
        game: game,
        knowledgeContext: knowledgeContext,
      );
      final StringBuffer rawKnowledge = StringBuffer();
      String emittedKnowledgeAnswer = '';

      await for (final AiStreamEvent event in _aiClient.stream(
        AiRequest(
          endpoint: _endpointFor(config),
          messages: <AiMessage>[
            AiMessage.system(systemPrompt),
            ...conversation,
          ],
          options: _generationOptions(
            config,
            temperature: 0.1,
            topP: 0.95,
            maxCompletionTokens: 900,
            frequencyPenalty: 0,
            presencePenalty: 0,
          ),
        ),
        abortTrigger: abortTrigger,
      )) {
        rawKnowledge.write(event.delta);
        final String partial = _partialKnowledgeAnswer(rawKnowledge.toString());
        if (partial.length > emittedKnowledgeAnswer.length) {
          final String delta = partial.substring(emittedKnowledgeAnswer.length);
          emittedKnowledgeAnswer = partial;
          yield BoardGameAiStreamEvent(delta: delta);
        }
      }

      final BoardGameAiAnswer knowledgeAnswer = _answerParser.parse(
        rawKnowledge.toString(),
        language: language,
        availableEvidence: evidence,
      );
      if (knowledgeAnswer.source == AnswerSource.rulebook) {
        final String remaining =
            knowledgeAnswer.text.length > emittedKnowledgeAnswer.length
            ? knowledgeAnswer.text.substring(emittedKnowledgeAnswer.length)
            : '';
        yield BoardGameAiStreamEvent(
          delta: remaining,
          answer: knowledgeAnswer,
          isDone: true,
        );
        return;
      }

      if (answerMode == AiAnswerMode.knowledgeOnly) {
        yield BoardGameAiStreamEvent(
          delta: knowledgeAnswer.text,
          answer: knowledgeAnswer,
          isDone: true,
        );
        return;
      }
    } else if (answerMode == AiAnswerMode.knowledgeOnly) {
      final BoardGameAiAnswer answer = _unknownAnswer(language);
      yield BoardGameAiStreamEvent(
        delta: answer.text,
        answer: answer,
        isDone: true,
      );
      return;
    }

    yield* _streamDirectAnswer(
      language: language,
      game: game,
      config: config,
      useGlobalMode: useGlobalMode,
      knowledgeContext: evidence.isEmpty
          ? ''
          : _knowledgeRetriever.formatForPrompt(
              evidence,
              maxChars: _maxKnowledgeCharsForDirectFallback,
            ),
      evidence: evidence,
      conversation: conversation,
      abortTrigger: abortTrigger,
    );
  }

  @override
  Future<List<AiModel>> listModels(AiApiConfig config) {
    return _aiClient.listModels(_endpointFor(config));
  }

  @override
  Future<AiHealthResult> checkConnection(AiApiConfig config) {
    return _aiClient.check(_endpointFor(config));
  }

  @override
  void dispose() {
    _responsesWorkflow?.close();
    _aiClient.close();
  }

  bool _responsesEnabled(AiApiConfig config) {
    return _responsesWorkflow != null &&
        config.model.trim().isNotEmpty &&
        (config.providerPreset == AiProviderPreset.openAi ||
            config.providerPreset == AiProviderPreset.custom);
  }

  Future<BoardGameAiAnswer> _answerFromKnowledgeOnly({
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
    required String knowledgeContext,
    required List<EvidenceChunk> evidence,
    required List<AiMessage> conversation,
  }) async {
    final String systemPrompt = _promptBuilder.buildKnowledgeOnlySystemPrompt(
      language: language,
      game: game,
      knowledgeContext: knowledgeContext,
    );
    final String raw = await _complete(
      config: config,
      systemPrompt: systemPrompt,
      conversation: conversation,
      options: _generationOptions(
        config,
        temperature: 0.1,
        topP: 0.95,
        maxCompletionTokens: 900,
        frequencyPenalty: 0,
        presencePenalty: 0,
      ),
    );
    final BoardGameAiAnswer parsed = _answerParser.parse(
      raw,
      language: language,
      availableEvidence: evidence,
    );
    debugPrint(
      '[ai] knowledge pass source=${parsed.source.code} evidence=${parsed.evidence.length} answerLen=${parsed.text.length} game=${game.slug}',
    );
    return parsed;
  }

  Future<BoardGameAiAnswer> _answerDirectlyWithGameContext({
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
    required bool useGlobalMode,
    required String knowledgeContext,
    required List<EvidenceChunk> evidence,
    required List<AiMessage> conversation,
  }) async {
    debugPrint('[ai] using direct fallback for ${game.slug}');
    final String systemPrompt = _promptBuilder.buildDirectFallbackSystemPrompt(
      language: language,
      game: game,
      useGlobalMode: useGlobalMode,
      knowledgeContext: knowledgeContext,
    );
    final String answer = await _complete(
      config: config,
      systemPrompt: systemPrompt,
      conversation: conversation,
      options: _generationOptions(
        config,
        temperature: 0.7,
        topP: 0.95,
        maxCompletionTokens: 1024,
        frequencyPenalty: 0,
        presencePenalty: 0,
      ),
    );
    return BoardGameAiAnswer(
      text: answer.trim(),
      source: AnswerSource.generalAdvice,
      evidence: evidence,
    );
  }

  Future<String> _complete({
    required AiApiConfig config,
    required String systemPrompt,
    required List<AiMessage> conversation,
    required AiGenerationOptions options,
  }) async {
    final AiResponse response = await _aiClient.complete(
      AiRequest(
        endpoint: _endpointFor(config),
        messages: <AiMessage>[AiMessage.system(systemPrompt), ...conversation],
        options: options,
      ),
    );
    return response.text;
  }

  Stream<BoardGameAiStreamEvent> _streamDirectAnswer({
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
    required bool useGlobalMode,
    required String knowledgeContext,
    required List<EvidenceChunk> evidence,
    required List<AiMessage> conversation,
    Future<void>? abortTrigger,
  }) async* {
    final String systemPrompt = _promptBuilder.buildDirectFallbackSystemPrompt(
      language: language,
      game: game,
      useGlobalMode: useGlobalMode,
      knowledgeContext: knowledgeContext,
    );
    final StringBuffer answerText = StringBuffer();
    await for (final AiStreamEvent event in _aiClient.stream(
      AiRequest(
        endpoint: _endpointFor(config),
        messages: <AiMessage>[AiMessage.system(systemPrompt), ...conversation],
        options: _generationOptions(
          config,
          temperature: 0.7,
          topP: 0.95,
          maxCompletionTokens: 1024,
          frequencyPenalty: 0,
          presencePenalty: 0,
        ),
      ),
      abortTrigger: abortTrigger,
    )) {
      if (event.delta.isEmpty) {
        continue;
      }
      answerText.write(event.delta);
      yield BoardGameAiStreamEvent(delta: event.delta);
    }

    final String text = answerText.toString().trim();
    if (text.isEmpty) {
      throw StateError('The AI streaming response was empty.');
    }
    yield BoardGameAiStreamEvent(
      answer: BoardGameAiAnswer(
        text: text,
        source: AnswerSource.generalAdvice,
        evidence: evidence,
      ),
      isDone: true,
    );
  }

  String _partialKnowledgeAnswer(String raw) {
    final RegExpMatch? statusMatch = RegExp(
      r'"status"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(raw);
    if (statusMatch?.group(1)?.toLowerCase() != 'answered') {
      return '';
    }

    final RegExpMatch? answerMatch = RegExp(
      r'"answer"\s*:\s*"',
      caseSensitive: false,
    ).firstMatch(raw);
    if (answerMatch == null) {
      return '';
    }

    final int start = answerMatch.end;
    final StringBuffer encoded = StringBuffer();
    bool escaped = false;
    for (int index = start; index < raw.length; index += 1) {
      final String character = raw[index];
      if (escaped) {
        encoded.write(character);
        escaped = false;
        continue;
      }
      if (character == r'\') {
        encoded.write(character);
        escaped = true;
        continue;
      }
      if (character == '"') {
        break;
      }
      encoded.write(character);
    }

    final String value = encoded.toString();
    if (value.isEmpty) {
      return '';
    }
    try {
      return (jsonDecode('"$value"') as String);
    } catch (_) {
      return value
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
    }
  }

  AiEndpointConfig _endpointFor(AiApiConfig config) {
    return AiEndpointConfig(
      name: config.name,
      baseUrl: config.baseUrl,
      apiKey: config.apiKey,
      model: config.model,
      apiKeyHeader: 'Authorization',
      chatPath: '/chat/completions',
    );
  }

  AiGenerationOptions _generationOptions(
    AiApiConfig config, {
    required double temperature,
    required double topP,
    required int maxCompletionTokens,
    required double frequencyPenalty,
    required double presencePenalty,
  }) {
    return AiGenerationOptions(
      temperature: temperature,
      topP: topP,
      maxCompletionTokens: maxCompletionTokens,
      frequencyPenalty: frequencyPenalty,
      presencePenalty: presencePenalty,
      reasoningEffort: config.reasoningEffort.requestValue,
      serviceTier: config.responseSpeed.serviceTier,
    );
  }

  List<AiMessage> _buildConversationMessages(
    List<ChatMessage> history,
    String prompt,
  ) {
    final List<AiMessage> messages = history
        .where((ChatMessage message) => message.text.trim().isNotEmpty)
        .map((ChatMessage message) {
          return message.role == ChatRole.user
              ? AiMessage.user(message.text.trim())
              : AiMessage.assistant(message.text.trim());
        })
        .toList();

    if (messages.isEmpty ||
        messages.last.role != AiMessageRole.user ||
        messages.last.content != prompt) {
      messages.add(AiMessage.user(prompt));
    }

    final int firstIndex = messages.length > _maxConversationMessages
        ? messages.length - _maxConversationMessages
        : 0;
    return List<AiMessage>.unmodifiable(messages.sublist(firstIndex));
  }

  BoardGameAiAnswer _unknownAnswer(AppLanguage language) {
    return BoardGameAiAnswer(
      text: language == AppLanguage.zhHans
          ? '当前知识库没有足够信息回答这个问题。'
          : 'The current knowledge base does not contain enough information to answer this question.',
      source: AnswerSource.insufficient,
    );
  }
}
