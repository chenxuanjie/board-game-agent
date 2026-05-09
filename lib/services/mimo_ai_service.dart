import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/ai_api_config.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/game_info.dart';
import 'ai_service.dart';
import 'remote_asset_service.dart';

class MimoAiService implements AiService {
  static const int _maxKnowledgeCharsPerAsset = 6000;
  static const int _maxKnowledgeCharsTotal = 24000;

  final http.Client _client;

  MimoAiService({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<String> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
  }) async {
    final String normalizedBaseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final String normalizedChatPath = config.chatPath.startsWith('/')
        ? config.chatPath
        : '/${config.chatPath}';
    final Uri uri = Uri.parse('$normalizedBaseUrl$normalizedChatPath');
    final String systemPrompt = await _buildSystemPrompt(
      language: language,
      game: game,
      assetSourceConfigs: assetSourceConfigs,
      remoteAssetService: remoteAssetService,
    );

    final Map<String, dynamic> payload = <String, dynamic>{
      'model': config.model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': prompt},
      ],
      'max_completion_tokens': 1024,
      'temperature': 1.0,
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

  Future<String> _buildSystemPrompt({
    required AppLanguage language,
    required GameInfo game,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
  }) async {
    final String todayLabel = language == AppLanguage.zhHans
        ? _chineseTodayString()
        : _englishTodayString();
    final String knowledgeContext = await _buildKnowledgeContext(
      game,
      assetSourceConfigs,
      remoteAssetService,
    );
    final String knowledgeBlock = knowledgeContext.isEmpty
        ? ''
        : '\n\n当前游戏的本地知识库摘录如下，请优先依据这些内容回答：\n$knowledgeContext';

    if (language == AppLanguage.zhHans) {
      return '''
你是MiMo（中文名称也是MiMo），是小米公司研发的AI智能助手。
今天的日期：$todayLabel，你的知识截止日期是2024年12月。
你当前正在担任桌游助手，主要服务于《${game.title}》。
请优先围绕这款桌游回答规则、流程、上手建议、术语解释和游玩提示。
如果本地知识库内容与泛化记忆冲突，以本地知识库和其中标注的官方资料摘要为准。
如果知识库没有直接覆盖某个细节，但你能根据上下文做出合理推断，请明确说明这是推断。
如果用户进入的是通用AI助手，也允许回答跨桌游的泛问题，但保持中文回答、清晰、简洁、可执行。
如果你不确定某条具体规则，请明确说明不确定，不要编造。
$knowledgeBlock
''';
    }

    final String englishKnowledgeBlock = knowledgeContext.isEmpty
        ? ''
        : '\n\nThe local knowledge base excerpts for this game are below. Prioritize them when answering:\n$knowledgeContext';

    return '''
You are MiMo, an AI assistant developed by Xiaomi.
Today's date: $todayLabel. Your knowledge cutoff date is December 2024.
You are currently acting as a board game assistant, mainly helping with ${game.title}.
Prioritize answers about rules, round flow, terminology, onboarding help, and practical play guidance.
If the provided local knowledge base conflicts with your general memory, prefer the local knowledge base and its official-source summaries.
If the knowledge base does not fully cover a detail but you can infer it, label that part as an inference.
If the user is in the global AI helper, you may answer broader cross-game questions, but stay concise, practical, and clear.
If you are unsure about a specific rule, say so instead of inventing an answer.
$englishKnowledgeBlock
''';
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
