import '../models/app_language.dart';
import '../models/game_info.dart';

abstract class AiService {
  Future<String> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
  });
}
