import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/app_language.dart';
import '../models/asset_source_config.dart';
import '../models/game_info.dart';
import 'ai_service.dart';
import 'remote_asset_service.dart';

class MimoAiService implements AiService {
  static const int _maxKnowledgeCharsPerAsset = 6000;
  static const int _maxKnowledgeCharsTotal = 24000;
  static const int _maxKnowledgeCharsForDirectFallback = 12000;
  static const String _statusAnswered = 'answered';
  static const String _statusUnknown = 'unknown';

  final http.Client _client;

  MimoAiService({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<String> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
  }) async {
    final Uri uri = _buildChatUri(config);
    final String knowledgeContext = await _buildKnowledgeContext(
      game,
      assetSourceConfigs,
      remoteAssetService,
    );

    debugPrint(
      '[ai] generateReply game=${game.slug} global=$useGlobalMode mode=${answerMode.code} knowledgeChars=${knowledgeContext.length}',
    );

    if (knowledgeContext.isEmpty) {
      debugPrint('[ai] no local knowledge loaded for ${game.slug}');
      if (answerMode == AiAnswerMode.knowledgeOnly) {
        return _unknownReply(language);
      }
      return _answerDirectlyWithGameContext(
        uri: uri,
        prompt: prompt,
        language: language,
        game: game,
        config: config,
        useGlobalMode: useGlobalMode,
        knowledgeContext: '',
      );
    }

    final _KnowledgeReply knowledgeReply = await _answerFromKnowledgeOnly(
      uri: uri,
      prompt: prompt,
      language: language,
      game: game,
      config: config,
      knowledgeContext: knowledgeContext,
    );

    if (knowledgeReply.status == _statusAnswered) {
      debugPrint('[ai] answered from local knowledge for ${game.slug}');
      return knowledgeReply.answer;
    }

    debugPrint('[ai] local knowledge insufficient for ${game.slug}');
    if (answerMode == AiAnswerMode.knowledgeOnly) {
      return knowledgeReply.answer;
    }

    return _answerDirectlyWithGameContext(
      uri: uri,
      prompt: prompt,
      language: language,
      game: game,
      config: config,
      useGlobalMode: useGlobalMode,
      knowledgeContext: _truncateKnowledgeForDirectFallback(knowledgeContext),
    );
  }

  Uri _buildChatUri(AiApiConfig config) {
    final String normalizedBaseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final String normalizedChatPath = config.chatPath.startsWith('/')
        ? config.chatPath
        : '/${config.chatPath}';
    return Uri.parse('$normalizedBaseUrl$normalizedChatPath');
  }

  Future<_KnowledgeReply> _answerFromKnowledgeOnly({
    required Uri uri,
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
    required String knowledgeContext,
  }) async {
    final String systemPrompt = _buildKnowledgeOnlySystemPrompt(
      language: language,
      game: game,
      knowledgeContext: knowledgeContext,
    );
    final String raw = await _postChat(
      uri: uri,
      config: config,
      messages: <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': prompt},
      ],
      temperature: 0.1,
      maxCompletionTokens: 900,
    );
    final _KnowledgeReply parsed = _parseKnowledgeReply(
      raw,
      language: language,
    );
    debugPrint(
      '[ai] knowledge pass status=${parsed.status} game=${game.slug} answerLen=${parsed.answer.length}',
    );
    return parsed;
  }

  Future<String> _answerDirectlyWithGameContext({
    required Uri uri,
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
    required bool useGlobalMode,
    required String knowledgeContext,
  }) async {
    debugPrint('[ai] using direct fallback for ${game.slug}');
    final String systemPrompt = _buildDirectFallbackSystemPrompt(
      language: language,
      game: game,
      useGlobalMode: useGlobalMode,
      knowledgeContext: knowledgeContext,
    );
    return _postChat(
      uri: uri,
      config: config,
      messages: <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': prompt},
      ],
      temperature: 0.7,
      maxCompletionTokens: 1024,
    );
  }

  Future<String> _postChat({
    required Uri uri,
    required AiApiConfig config,
    required List<Map<String, String>> messages,
    required double temperature,
    required int maxCompletionTokens,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'max_completion_tokens': maxCompletionTokens,
      'temperature': temperature,
      'top_p': 0.95,
      'stream': false,
      'frequency_penalty': 0,
      'presence_penalty': 0,
    };

    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        config.apiKeyHeader: config.apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('MiMo 接口请求失败：${response.statusCode} ${response.body}');
    }

    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic>? choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('MiMo 接口没有返回可用回答。');
    }

    final Map<String, dynamic>? message =
        choices.first['message'] as Map<String, dynamic>?;
    final String? content = message?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw Exception('MiMo 接口返回内容为空。');
    }

    return content.trim();
  }

  String _buildKnowledgeOnlySystemPrompt({
    required AppLanguage language,
    required GameInfo game,
    required String knowledgeContext,
  }) {
    final String todayLabel = language == AppLanguage.zhHans
        ? _chineseTodayString()
        : _englishTodayString();

    if (language == AppLanguage.zhHans) {
      return '''
你是 MiMo，是小米公司研发的 AI 智能助手。
今天的日期：$todayLabel。你的知识截止日期是 2024 年 12 月。
你当前正在担任《${game.title}》的桌游助手。
你现在处于“仅知识库回答”模式。
你只能依据下面提供的当前桌游本地知识库内容回答。
禁止使用你自己的泛化记忆、常识、猜测或推断来补全未明确写出的规则。
如果知识库没有明确给出答案，或者证据不足，必须返回 unknown。
如果用户问题超出当前桌游知识库范围，也必须返回 unknown。
请只返回 JSON，不要添加代码块，不要添加额外说明。

可用返回格式只有二选一：
{"status":"answered","answer":"你的回答"}
{"status":"unknown","answer":"当前知识库没有足够信息回答这个问题。"}

当前桌游本地知识库如下：
$knowledgeContext
''';
    }

    return '''
You are MiMo, an AI assistant developed by Xiaomi.
Today's date: $todayLabel. Your knowledge cutoff is December 2024.
You are currently acting as the board game assistant for ${game.title}.
You are now in knowledge-only mode.
You may answer only from the local knowledge base content provided below.
Do not use your own general memory, common sense, guesses, or inference to fill gaps in missing rules.
If the knowledge base does not explicitly support the answer, you must return unknown.
If the question falls outside this game's knowledge base, you must also return unknown.
Return JSON only, with no code fences and no extra commentary.

The only valid formats are:
{"status":"answered","answer":"your answer"}
{"status":"unknown","answer":"The current knowledge base does not contain enough information to answer this question."}

Current local knowledge base:
$knowledgeContext
''';
  }

  String _buildDirectFallbackSystemPrompt({
    required AppLanguage language,
    required GameInfo game,
    required bool useGlobalMode,
    required String knowledgeContext,
  }) {
    final String todayLabel = language == AppLanguage.zhHans
        ? _chineseTodayString()
        : _englishTodayString();
    final String gameProfile = _buildGameProfileBlock(language, game);
    final String knowledgeBlock = knowledgeContext.isEmpty
        ? ''
        : language == AppLanguage.zhHans
        ? '\n\n以下是本地知识库中可作为补充参考的摘录：\n$knowledgeContext'
        : '\n\nBelow are optional excerpts from the local knowledge base for reference:\n$knowledgeContext';

    if (language == AppLanguage.zhHans) {
      final String entryHint = useGlobalMode
          ? '用户当前位于独立 AI 入口，但当前选中的桌游上下文仍然是《${game.title}》。'
          : '用户当前位于《${game.title}》的桌游详情 AI 助手。';
      return '''
你是 MiMo，是小米公司研发的 AI 智能助手。
今天的日期：$todayLabel。你的知识截止日期是 2024 年 12 月。
$entryHint
你现在处于“智能补充”模式。
请优先围绕当前桌游回答，并结合下面给出的桌游详情来组织答案。
如果本地知识库不足，你可以使用你的通用知识直接回答，就像普通 AI 问答一样。
但如果涉及非常具体、你没有把握的规则细节，请明确说明你不确定，不要编造。
回答要清晰、简洁、可执行，并尽量贴合当前桌游。

当前桌游详情：
$gameProfile$knowledgeBlock
''';
    }

    final String entryHint = useGlobalMode
        ? 'The user is in the standalone AI entry, but the currently selected game context is still ${game.title}.'
        : 'The user is in the dedicated assistant for ${game.title}.';
    return '''
You are MiMo, an AI assistant developed by Xiaomi.
Today's date: $todayLabel. Your knowledge cutoff is December 2024.
$entryHint
You are now in smart supplement mode.
Prioritize the current game and use the game profile below to shape your answer.
If the local knowledge base is insufficient, you may answer directly from your general knowledge like a normal AI assistant.
However, if the user asks about a very specific rule detail and you are not confident, say you are not sure instead of inventing an answer.
Keep the answer practical, concise, and focused on the current game.

Current game profile:
$gameProfile$knowledgeBlock
''';
  }

  String _buildGameProfileBlock(AppLanguage language, GameInfo game) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('- title: ${game.title}')
      ..writeln('- subtitle: ${game.subtitle}')
      ..writeln('- summary: ${game.summary}')
      ..writeln('- mentorPitch: ${game.mentorPitch}')
      ..writeln('- playerCount: ${game.playerCount}')
      ..writeln('- playTime: ${game.playTime}')
      ..writeln('- complexity: ${game.complexity}')
      ..writeln('- learningDifficulty: ${game.learningDifficulty}')
      ..writeln('- perPlayerTime: ${game.perPlayerTime}')
      ..writeln('- setupTime: ${game.setupTime}')
      ..writeln('- languageRequirement: ${game.languageRequirement}')
      ..writeln('- supportedPlayers: ${game.supportedPlayers.join(', ')}')
      ..writeln('- recommendedPlayer: ${game.recommendedPlayer}');

    if (game.roundFlow.isNotEmpty) {
      buffer.writeln(
        language == AppLanguage.zhHans ? '- 一局流程：' : '- roundFlow:',
      );
      for (final String step in game.roundFlow) {
        buffer.writeln('  - $step');
      }
    }

    if (game.assistantSkills.isNotEmpty) {
      buffer.writeln(
        language == AppLanguage.zhHans ? '- 助手能力：' : '- assistantSkills:',
      );
      for (final String skill in game.assistantSkills) {
        buffer.writeln('  - $skill');
      }
    }

    return buffer.toString().trimRight();
  }

  _KnowledgeReply _parseKnowledgeReply(
    String input, {
    required AppLanguage language,
  }) {
    final String stripped = _stripCodeFences(input.trim());
    try {
      final Map<String, dynamic> json =
          jsonDecode(stripped) as Map<String, dynamic>;
      final String status = (json['status'] as String? ?? '')
          .trim()
          .toLowerCase();
      final String answer = (json['answer'] as String? ?? '').trim();
      if (status == _statusAnswered && answer.isNotEmpty) {
        return _KnowledgeReply(status: _statusAnswered, answer: answer);
      }
      if (status == _statusUnknown) {
        return _KnowledgeReply(
          status: _statusUnknown,
          answer: answer.isEmpty ? _unknownReply(language) : answer,
        );
      }
    } catch (_) {
      // Fallback parsing is handled below.
    }

    final RegExp statusPattern = RegExp(
      r'STATUS\s*:\s*([A-Za-z_]+)',
      caseSensitive: false,
    );
    final RegExp answerPattern = RegExp(
      r'ANSWER\s*:\s*([\s\S]+)$',
      caseSensitive: false,
    );
    final RegExpMatch? statusMatch = statusPattern.firstMatch(stripped);
    final RegExpMatch? answerMatch = answerPattern.firstMatch(stripped);
    final String status =
        statusMatch?.group(1)?.trim().toLowerCase() ?? _statusUnknown;
    final String answer = answerMatch?.group(1)?.trim() ?? '';

    if (status == _statusAnswered && answer.isNotEmpty) {
      return _KnowledgeReply(status: _statusAnswered, answer: answer);
    }
    return _KnowledgeReply(
      status: _statusUnknown,
      answer: answer.isEmpty ? _unknownReply(language) : answer,
    );
  }

  String _stripCodeFences(String input) {
    String value = input.trim();
    value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    return value.trim();
  }

  String _truncateKnowledgeForDirectFallback(String knowledgeContext) {
    if (knowledgeContext.length <= _maxKnowledgeCharsForDirectFallback) {
      return knowledgeContext;
    }
    return '${knowledgeContext.substring(0, _maxKnowledgeCharsForDirectFallback)}\n\n[Truncated for fallback prompt length]';
  }

  String _unknownReply(AppLanguage language) {
    return language == AppLanguage.zhHans
        ? '当前知识库没有足够信息回答这个问题。'
        : 'The current knowledge base does not contain enough information to answer this question.';
  }

  Future<String> _buildKnowledgeContext(
    GameInfo game,
    List<AssetSourceConfig> assetSourceConfigs,
    RemoteAssetService remoteAssetService,
  ) async {
    final StringBuffer buffer = StringBuffer();
    int totalChars = 0;

    for (final String remotePath in game.knowledgeAssetPaths) {
      if (!remotePath.endsWith('.md')) {
        continue;
      }

      try {
        String? content;
        try {
          content = await rootBundle.loadString(remotePath);
        } catch (_) {
          content = null;
        }
        content ??= await remoteAssetService.loadTextFromAny(
          sources: assetSourceConfigs,
          remotePaths: <String>[remotePath],
        );
        if (content == null) {
          continue;
        }
        content = _normalizeKnowledgeContent(content);
        if (content.isEmpty) {
          continue;
        }

        final int remaining = _maxKnowledgeCharsTotal - totalChars;
        if (remaining <= 0) {
          break;
        }

        if (content.length > _maxKnowledgeCharsPerAsset) {
          content =
              '${content.substring(0, _maxKnowledgeCharsPerAsset)}\n\n[Truncated for prompt length]';
        }

        if (content.length > remaining) {
          content = content.substring(0, remaining);
        }

        final String fileName = remotePath.split('/').last;
        buffer.writeln('### $fileName');
        buffer.writeln(content);
        buffer.writeln();
        totalChars += content.length;
      } catch (_) {
        continue;
      }
    }

    return buffer.toString().trim();
  }

  String _normalizeKnowledgeContent(String input) {
    return input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _englishTodayString() {
    final DateTime now = DateTime.now();
    const List<String> weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final String year = now.year.toString().padLeft(4, '0');
    final String month = now.month.toString().padLeft(2, '0');
    final String day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day ${weekdays[now.weekday - 1]}';
  }

  String _chineseTodayString() {
    final DateTime now = DateTime.now();
    const List<String> weekdays = <String>[
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日',
    ];
    final String year = now.year.toString().padLeft(4, '0');
    final String month = now.month.toString().padLeft(2, '0');
    final String day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day ${weekdays[now.weekday - 1]}';
  }
}

class _KnowledgeReply {
  const _KnowledgeReply({required this.status, required this.answer});

  final String status;
  final String answer;
}
