import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_language.dart';
import '../models/game_info.dart';
import 'ai_service.dart';

class MimoAiService implements AiService {
  static const String apiKey = 'tp-cqrdq1go3g16pd4nhg05vd91dmh36vp0eq49i41qjmb4rdlb';
  static const String baseUrl = 'https://token-plan-cn.xiaomimimo.com/v1';
  static const String model = 'mimo-v2.5-pro';

  final http.Client _client;

  MimoAiService({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<String> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/chat/completions');
    final String systemPrompt = _buildSystemPrompt(language: language, game: game);

    final Map<String, dynamic> payload = <String, dynamic>{
      'model': model,
      'messages': <Map<String, String>>[
        <String, String>{
          'role': 'system',
          'content': systemPrompt,
        },
        <String, String>{
          'role': 'user',
          'content': prompt,
        },
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
        'api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('MiMo 接口请求失败：${response.statusCode} ${response.body}');
    }

    final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
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

  String _buildSystemPrompt({
    required AppLanguage language,
    required GameInfo game,
  }) {
    if (language == AppLanguage.zhHans) {
      return '''
你是MiMo（中文名称也是MiMo），是小米公司研发的AI智能助手。
今天的日期：2026-05-08 星期五，你的知识截止日期是2024年12月。
你当前正在担任桌游助手，主要服务于《${game.title}》。
请优先围绕这款桌游回答规则、流程、上手建议、术语解释和游玩提示。
如果用户进入的是通用AI助手，也允许回答跨桌游的泛问题，但保持中文回答、清晰、简洁、可执行。
如果你不确定某条具体规则，请明确说明不确定，不要编造。
''';
    }

    return '''
You are MiMo, an AI assistant developed by Xiaomi.
Today's date: 2026-05-08 Friday. Your knowledge cutoff date is December 2024.
You are currently acting as a board game assistant, mainly helping with ${game.title}.
Prioritize answers about rules, round flow, terminology, onboarding help, and practical play guidance.
If the user is in the global AI helper, you may answer broader cross-game questions, but stay concise, practical, and clear.
If you are unsure about a specific rule, say so instead of inventing an answer.
''';
  }
}
