import '../models/ai_api_config.dart';
import '../models/app_language.dart';
import '../models/game_info.dart';

abstract class AiService {
  Future<String> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
  });
}
