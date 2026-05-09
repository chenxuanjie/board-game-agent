import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_api_config.dart';
import '../models/app_language.dart';
import '../models/color_scheme_option.dart';

class PreferencesService {
  static const _languageKey = 'app_language';
  static const _voiceReplyKey = 'voice_reply_enabled';
  static const _colorSchemeKey = 'color_scheme';
  static const _aiApiConfigKey = 'ai_api_config';

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
}
