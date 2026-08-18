import 'package:app_ai_client/app_ai_client.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/board_game_ai_answer.dart';
import '../models/chat_message.dart';
import '../models/game_info.dart';
import 'remote_asset_service.dart';

abstract class AiService {
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

  Future<AiHealthResult> checkConnection(AiApiConfig config);

  void dispose();
}
