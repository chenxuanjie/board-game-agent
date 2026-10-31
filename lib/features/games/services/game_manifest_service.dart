import '../../library/models/asset_source_config.dart';
import '../../library/services/remote_asset_service.dart';
import '../models/game_catalog_manifest.dart';

/// Published SQL editions; language selection remains a domain concern.
class GameManifestService {
  Future<List<GameManifest>> loadEnabledGames({
    required RemoteAssetService remoteAssetService,
    List<AssetSourceConfig> sources = const [],
    bool preferRemote = false,
  }) async =>
      (await remoteAssetService.loadCatalog(refresh: preferRemote)).games;
}
