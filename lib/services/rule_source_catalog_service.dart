import 'package:flutter/services.dart' show rootBundle;

import '../models/asset_source_config.dart';
import '../models/game_info.dart';
import '../models/rule_source.dart';
import 'remote_asset_service.dart';

/// Loads the source manifest without allowing the model to invent paths.
class RuleSourceCatalogService {
  const RuleSourceCatalogService();

  static const String remotePath = 'rule_sources.json';

  Future<RuleSourceCatalog?> load({
    required GameInfo game,
    required List<AssetSourceConfig> sources,
    required RemoteAssetService remoteAssetService,
  }) async {
    String? source = await remoteAssetService.loadText(
      sources: sources,
      remotePath: remotePath,
    );
    source ??= await remoteAssetService.fetchRemoteText(
      sources: sources,
      remotePath: remotePath,
    );
    if (source == null) {
      try {
        source = await rootBundle.loadString('assets/rule_sources.json');
      } catch (_) {
        source = null;
      }
    }
    if (source == null || source.trim().isEmpty) {
      return null;
    }
    try {
      return RuleSourceCatalog.fromJson(source);
    } catch (_) {
      return null;
    }
  }
}
