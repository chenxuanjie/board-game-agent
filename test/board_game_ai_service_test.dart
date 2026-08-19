import 'package:app_ai_client/app_ai_client.dart';
import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/services/board_game_ai_service.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'knowledge-only mode returns unknown when knowledge pass says unknown',
    () async {
      final _FakeAiClient client = _FakeAiClient(
        responses: <AiResponse>[
          const AiResponse(
            text: '{"status":"unknown","answer":"当前知识库没有足够信息回答这个问题。"}',
            model: 'test-model',
          ),
        ],
      );
      final BoardGameAiService service = BoardGameAiService(aiClient: client);

      final BoardGameAiAnswer reply = await service.generateReply(
        prompt: '这款桌游支持几个人玩合作模式？',
        language: AppLanguage.zhHans,
        game: _gameInfo(),
        answerMode: AiAnswerMode.knowledgeOnly,
        useGlobalMode: false,
        config: AiApiConfig.defaultOpenAi,
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _FakeRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(reply.text, '当前知识库没有足够信息回答这个问题。');
      expect(reply.source, AnswerSource.insufficient);
      expect(client.requestCount, 1);
    },
  );

  test(
    'smart supplement mode falls back to direct answer after unknown',
    () async {
      final _FakeAiClient client = _FakeAiClient(
        responses: <AiResponse>[
          const AiResponse(
            text: '{"status":"unknown","answer":"当前知识库没有足够信息回答这个问题。"}',
            model: 'test-model',
          ),
          const AiResponse(text: '这款游戏通常以竞争为主，不是合作玩法。', model: 'test-model'),
        ],
      );
      final BoardGameAiService service = BoardGameAiService(aiClient: client);

      final BoardGameAiAnswer reply = await service.generateReply(
        prompt: '这款桌游支持几个人玩合作模式？',
        language: AppLanguage.zhHans,
        game: _gameInfo(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: AiApiConfig.defaultOpenAi,
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _FakeRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(reply.text, '这款游戏通常以竞争为主，不是合作玩法。');
      expect(reply.source, AnswerSource.generalAdvice);
      expect(client.requestCount, 2);
    },
  );

  test('knowledge answer returns rulebook source and matched evidence', () async {
    final _FakeAiClient client = _FakeAiClient(
      responses: <AiResponse>[
        const AiResponse(
          text:
              '{"status":"answered","answer":"Cabo 是竞争类游戏。","evidence":["faq_zh.md"]}',
          model: 'test-model',
        ),
      ],
    );
    final BoardGameAiService service = BoardGameAiService(aiClient: client);

    final BoardGameAiAnswer reply = await service.generateReply(
      prompt: 'Cabo 是合作游戏吗？',
      language: AppLanguage.zhHans,
      game: _gameInfo(),
      answerMode: AiAnswerMode.knowledgeOnly,
      useGlobalMode: false,
      config: AiApiConfig.defaultOpenAi,
      assetSourceConfigs: const <AssetSourceConfig>[],
      remoteAssetService: _FakeRemoteAssetService(),
      conversationHistory: const <ChatMessage>[],
    );

    expect(reply.source, AnswerSource.rulebook);
    expect(reply.text, 'Cabo 是竞争类游戏。');
    expect(reply.evidence, hasLength(1));
    expect(reply.evidence.single.sourceName, 'faq_zh.md');
  });

  test(
    'streaming knowledge answer emits visible deltas and provenance',
    () async {
      final _FakeAiClient client = _FakeAiClient(
        streams: <List<AiStreamEvent>>[
          <AiStreamEvent>[
            const AiStreamEvent(delta: '{"status":"answered","answer":"Cabo '),
            const AiStreamEvent(delta: '是竞争类游戏。","evidence":["faq_zh.md"]}'),
          ],
        ],
      );
      final BoardGameAiService service = BoardGameAiService(aiClient: client);

      final List<BoardGameAiStreamEvent> events = await service
          .streamReply(
            prompt: 'Cabo 是合作游戏吗？',
            language: AppLanguage.zhHans,
            game: _gameInfo(),
            answerMode: AiAnswerMode.knowledgeOnly,
            useGlobalMode: false,
            config: AiApiConfig.defaultOpenAi,
            assetSourceConfigs: const <AssetSourceConfig>[],
            remoteAssetService: _FakeRemoteAssetService(),
            conversationHistory: const <ChatMessage>[],
          )
          .toList();

      expect(events.map((event) => event.delta).join(), 'Cabo 是竞争类游戏。');
      expect(events.last.isDone, isTrue);
      expect(events.last.answer?.source, AnswerSource.rulebook);
      expect(events.last.answer?.evidence.single.sourceName, 'faq_zh.md');
    },
  );

  test(
    'streaming smart supplement falls back after knowledge stream is unknown',
    () async {
      final _FakeAiClient client = _FakeAiClient(
        streams: <List<AiStreamEvent>>[
          <AiStreamEvent>[const AiStreamEvent(delta: '{"status":"unknown"}')],
          <AiStreamEvent>[
            const AiStreamEvent(delta: '这款游戏通常以竞争为主'),
            const AiStreamEvent(delta: '，不是合作玩法。'),
          ],
        ],
      );
      final BoardGameAiService service = BoardGameAiService(aiClient: client);

      final List<BoardGameAiStreamEvent> events = await service
          .streamReply(
            prompt: '这款桌游支持几个人玩合作模式？',
            language: AppLanguage.zhHans,
            game: _gameInfo(),
            answerMode: AiAnswerMode.knowledgeThenDirect,
            useGlobalMode: false,
            config: AiApiConfig.defaultOpenAi,
            assetSourceConfigs: const <AssetSourceConfig>[],
            remoteAssetService: _FakeRemoteAssetService(),
            conversationHistory: const <ChatMessage>[],
          )
          .toList();

      expect(events.map((event) => event.delta).join(), '这款游戏通常以竞争为主，不是合作玩法。');
      expect(events.last.answer?.source, AnswerSource.generalAdvice);
      expect(client.streamRequestCount, 2);
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
    assistantIntro: '《Cabo》是一款节奏很快的记忆与推理卡牌游戏。',
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

class _FakeAiClient implements AiClient {
  _FakeAiClient({
    List<AiResponse> responses = const <AiResponse>[],
    List<List<AiStreamEvent>> streams = const <List<AiStreamEvent>>[],
  }) : _responses = List<AiResponse>.from(responses),
       _streams = List<List<AiStreamEvent>>.from(streams);

  final List<AiResponse> _responses;
  final List<List<AiStreamEvent>> _streams;
  int requestCount = 0;
  int streamRequestCount = 0;

  @override
  Future<List<AiModel>> listModels(AiEndpointConfig endpoint) async {
    return const <AiModel>[AiModel(id: 'test-model')];
  }

  @override
  Future<AiResponse> complete(AiRequest request) async {
    if (_responses.isEmpty) {
      throw StateError('No fake AI response is available.');
    }
    requestCount += 1;
    return _responses.removeAt(0);
  }

  @override
  Future<AiHealthResult> check(AiEndpointConfig endpoint) async {
    return const AiHealthResult(
      success: true,
      message: 'ok',
      latency: Duration.zero,
      model: 'test-model',
    );
  }

  @override
  void close() {}

  @override
  Stream<AiStreamEvent> stream(
    AiRequest request, {
    Future<void>? abortTrigger,
  }) {
    streamRequestCount += 1;
    if (_streams.isEmpty) {
      return const Stream<AiStreamEvent>.empty();
    }
    return Stream<AiStreamEvent>.fromIterable(_streams.removeAt(0));
  }
}

class _FakeRemoteAssetService extends RemoteAssetService {
  _FakeRemoteAssetService() : super(client: http.Client());

  @override
  Future<String?> loadTextFromAny({
    required List<AssetSourceConfig> sources,
    required List<String> remotePaths,
  }) async {
    return '# Cabo test knowledge\nCabo is a competitive card game.';
  }
}
