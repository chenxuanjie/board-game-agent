import '../models/ai_api_config.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/game_info.dart';
import 'remote_asset_service.dart';

abstract class AiService {
  Future<String> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
  });
}
