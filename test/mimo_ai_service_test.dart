import 'dart:convert';

import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/services/mimo_ai_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'knowledge-only mode returns unknown when knowledge pass says unknown',
    () async {
      final _FakeHttpClient client = _FakeHttpClient(
        responses: <Map<String, dynamic>>[
          _chatResponse('{"status":"unknown","answer":"当前知识库没有足够信息回答这个问题。"}'),
        ],
      );
      final MimoAiService service = MimoAiService(client: client);

      final String reply = await service.generateReply(
        prompt: '这款桌游支持几个人玩合作模式？',
        language: AppLanguage.zhHans,
        game: _gameInfo(),
        answerMode: AiAnswerMode.knowledgeOnly,
        useGlobalMode: false,
        config: AiApiConfig.defaultMimo,
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: RemoteAssetService(client: _FakeHttpClient.empty()),
      );

      expect(reply, '当前知识库没有足够信息回答这个问题。');
      expect(client.requestCount, 1);
    },
  );

  test(
    'smart supplement mode falls back to direct answer after unknown',
    () async {
      final _FakeHttpClient client = _FakeHttpClient(
        responses: <Map<String, dynamic>>[
          _chatResponse('{"status":"unknown","answer":"当前知识库没有足够信息回答这个问题。"}'),
          _chatResponse('这款游戏通常以竞争为主，不是合作玩法。'),
        ],
      );
      final MimoAiService service = MimoAiService(client: client);

      final String reply = await service.generateReply(
        prompt: '这款桌游支持几个人玩合作模式？',
        language: AppLanguage.zhHans,
        game: _gameInfo(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: AiApiConfig.defaultMimo,
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: RemoteAssetService(client: _FakeHttpClient.empty()),
      );

      expect(reply, '这款游戏通常以竞争为主，不是合作玩法。');
      expect(client.requestCount, 2);
    },
  );
}

GameInfo _gameInfo() {
  return GameInfo(
    id: 'cabo',
    slug: 'cabo',
    title: 'Cabo',
    subtitle: 'Cabo',
    coverAssetPath: 'assets/games/cabo/images/cover.jpg',
    bannerAssetPath: 'assets/games/cabo/images/background.jpg',
    cardAccent: 0xFFCC6A2F,
    score: '7.0',
    scoreCountLabel: 'test',
    releaseYear: '2010',
    categoryLine: '竞争 / 记忆 / 卡牌',
    learningDifficulty: '3/10',
    perPlayerTime: '15-30 分钟',
    setupTime: '2 分钟',
    languageRequirement: '低',
    supportedPlayers: const <int>[2, 3, 4, 5],
    recommendedPlayer: 4,
    rankBadges: const <String>['2-5 人'],
    rulebookAssetPath: 'assets/games/cabo/docs/rulebook_zh.md',
    faqAssetPath: 'assets/games/cabo/docs/faq_zh.md',
    knowledgeAssetPaths: const <String>[
      'assets/games/cabo/docs/rulebook_zh.md',
      'assets/games/cabo/docs/faq_zh.md',
    ],
    heroTagline: '记住低分牌。',
    summary: '一款轻量记忆卡牌游戏。',
    mentorPitch: '适合边玩边问。',
    playTime: '15-30 分钟',
    playerCount: '2-5 人',
    complexity: '轻',
    roundFlow: const <String>['每位玩家有 4 张盖牌。', '轮到你时抽牌、替换或宣告 Cabo。'],
    assistantSkills: const <String>['解释 Cabo 宣告和配对规则'],
    quickPrompts: const <String>['喊 Cabo 后其他玩家还会行动吗？'],
  );
}

Map<String, dynamic> _chatResponse(String content) {
  return <String, dynamic>{
    'choices': <Map<String, dynamic>>[
      <String, dynamic>{
        'message': <String, dynamic>{'content': content},
      },
    ],
  };
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required List<Map<String, dynamic>> responses})
    : _responses = List<Map<String, dynamic>>.from(responses);

  _FakeHttpClient.empty() : _responses = <Map<String, dynamic>>[];

  final List<Map<String, dynamic>> _responses;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Map<String, dynamic> body = requestCount < _responses.length
        ? _responses[requestCount]
        : _chatResponse('{"status":"unknown","answer":"当前知识库没有足够信息回答这个问题。"}');
    requestCount += 1;
    final List<int> bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}
