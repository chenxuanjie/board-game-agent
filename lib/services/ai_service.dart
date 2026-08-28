import 'package:app_ai_client/app_ai_client.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/ai_run.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/board_game_ai_answer.dart';
import '../models/chat_message.dart';
import '../models/game_info.dart';
import '../models/rule_citation.dart';
import 'remote_asset_service.dart';

/// A normalized application-level update from a streaming board-game answer.
///
/// [delta] is safe to append to the assistant draft. [answer] is populated on
/// the terminal event so the controller can persist provenance and evidence.
class BoardGameAiStreamEvent {
  const BoardGameAiStreamEvent({
    this.delta = '',
    this.answer,
    this.isDone = false,
    this.status,
    this.citations = const <RuleCitation>[],
    this.runEvent,
    this.errorMessage,
    this.isFailure = false,
  });

  final String delta;
  final BoardGameAiAnswer? answer;
  final bool isDone;
  final String? status;
  final List<RuleCitation> citations;
  final AiRunEvent? runEvent;
  final String? errorMessage;
  final bool isFailure;
}

abstract class AiService {
  Future<List<AiModel>> listModels(AiApiConfig config);

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
  });

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
  });

  Future<AiHealthResult> checkConnection(AiApiConfig config);

  void dispose();
}
