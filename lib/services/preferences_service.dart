import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/color_scheme_option.dart';

class PreferencesService {
  static const _languageKey = 'app_language';
  static const _voiceReplyKey = 'voice_reply_enabled';
  static const _colorSchemeKey = 'color_scheme';
  static const _aiApiConfigKey = 'ai_api_config';
  static const _assetSourceOrderKey = 'asset_source_order';
  static const _gameAnswerModeKey = 'game_answer_mode';
  static const _globalAnswerModeKey = 'global_answer_mode';
  static const _checkForUpdatesKey = 'check_for_updates';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<AppLanguage> loadLanguage() async {
    final prefs = await _prefs;
    return AppLanguageX.fromCode(prefs.getString(_languageKey));
  }

  Future<void> saveLanguage(AppLanguage language) async {
    final prefs = await _prefs;
    await prefs.setString(_languageKey, language.code);
  }

  Future<bool> loadVoiceReplyEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_voiceReplyKey) ?? false;
  }

  Future<void> saveVoiceReplyEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_voiceReplyKey, enabled);
  }

  Future<ColorSchemeOption> loadColorScheme() async {
    final prefs = await _prefs;
    return ColorSchemeOptionX.fromCode(prefs.getString(_colorSchemeKey));
  }

  Future<void> saveColorScheme(ColorSchemeOption scheme) async {
    final prefs = await _prefs;
    await prefs.setString(_colorSchemeKey, scheme.code);
  }

  Future<AiApiConfig> loadAiApiConfig() async {
    final prefs = await _prefs;
    return AiApiConfig.fromJson(prefs.getString(_aiApiConfigKey));
  }

  Future<void> saveAiApiConfig(AiApiConfig config) async {
    final prefs = await _prefs;
    await prefs.setString(_aiApiConfigKey, config.toJson());
  }

  Future<List<AssetSourceConfig>> loadAssetSourceConfigs() async {
    final prefs = await _prefs;
    return AssetSourceConfig.decodeList(prefs.getString(_assetSourceOrderKey));
  }

  Future<void> saveAssetSourceConfigs(List<AssetSourceConfig> configs) async {
    final prefs = await _prefs;
    await prefs.setString(
      _assetSourceOrderKey,
      AssetSourceConfig.encodeList(configs),
    );
  }

  Future<AiAnswerMode> loadGameAnswerMode() async {
    final prefs = await _prefs;
    return AiAnswerModeX.fromCode(
      prefs.getString(_gameAnswerModeKey),
      fallback: AiAnswerMode.knowledgeOnly,
    );
  }

  Future<void> saveGameAnswerMode(AiAnswerMode mode) async {
    final prefs = await _prefs;
    await prefs.setString(_gameAnswerModeKey, mode.code);
  }

  Future<AiAnswerMode> loadGlobalAnswerMode() async {
    final prefs = await _prefs;
    return AiAnswerModeX.fromCode(
      prefs.getString(_globalAnswerModeKey),
      fallback: AiAnswerMode.knowledgeThenDirect,
    );
  }

  Future<void> saveGlobalAnswerMode(AiAnswerMode mode) async {
    final prefs = await _prefs;
    await prefs.setString(_globalAnswerModeKey, mode.code);
  }

  Future<bool> loadCheckForUpdates() async {
    final prefs = await _prefs;
    return prefs.getBool(_checkForUpdatesKey) ?? true;
  }

  Future<void> saveCheckForUpdates(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_checkForUpdatesKey, enabled);
  }
}
