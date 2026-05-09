import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_language.dart';
import '../models/color_scheme_option.dart';

class PreferencesService {
  static const _languageKey = 'app_language';
  static const _voiceReplyKey = 'voice_reply_enabled';
  static const _colorSchemeKey = 'color_scheme';

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
}
