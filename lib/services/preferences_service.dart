import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_activity.dart';
import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/assistant_mode.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/color_scheme_option.dart';
import '../models/desktop_library_resource.dart';
import '../models/favorite_game_record.dart';

class PreferencesService {
  static const _languageKey = 'app_language';
  static const _voiceReplyKey = 'voice_reply_enabled';
  static const _colorSchemeKey = 'color_scheme';
  static const _aiApiConfigKey = 'ai_api_config';
  static const _aiCustomPresetsKey = 'ai_custom_presets';
  static const _assetSourceOrderKey = 'asset_source_order';
  static const _gameAnswerModeKey = 'game_answer_mode';
  static const _globalAnswerModeKey = 'global_answer_mode';
  static const _globalUseCurrentGameKnowledgeKey =
      'global_use_current_game_knowledge';
  static const _checkForUpdatesKey = 'check_for_updates';
  static const _assistantModeKey = 'assistant_mode';
  static const _selectedConversationKey = 'selected_conversation_id';
  static const _activitiesKey = 'app_activities';
  static const _desktopLibraryResourcesKey = 'desktop_library_resources_v1';
  static const _favoriteGamesKey = 'favorite_games_v1';

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
    if (!prefs.containsKey(_colorSchemeKey)) {
      // A completely empty preference store is a fresh install. If another
      // legacy setting already exists, keep the old classic default instead
      // of silently changing an existing user's appearance.
      return prefs.getKeys().isEmpty
          ? ColorSchemeOption.sunsetCoast
          : ColorSchemeOption.classic;
    }
    return ColorSchemeOptionX.fromCode(prefs.getString(_colorSchemeKey));
  }

  Future<void> saveColorScheme(ColorSchemeOption scheme) async {
    final prefs = await _prefs;
    await prefs.setString(_colorSchemeKey, scheme.code);
  }

  Future<AiApiConfig> loadAiApiConfig() async {
    final prefs = await _prefs;
    final String? stored = prefs.getString(_aiApiConfigKey);
    final AiApiConfig config = AiApiConfig.fromJson(stored);
    if (stored != null && stored.trim().isNotEmpty) {
      final String normalized = config.toJson();
      if (stored != normalized) {
        await prefs.setString(_aiApiConfigKey, normalized);
      }
    }
    return config;
  }

  Future<void> saveAiApiConfig(AiApiConfig config) async {
    final prefs = await _prefs;
    await prefs.setString(_aiApiConfigKey, config.toJson());
  }

  Future<List<AiApiConfig>> loadAiCustomPresets() async {
    final prefs = await _prefs;
    return AiApiConfig.decodeList(prefs.getString(_aiCustomPresetsKey));
  }

  Future<void> saveAiCustomPresets(Iterable<AiApiConfig> configs) async {
    final prefs = await _prefs;
    await prefs.setString(_aiCustomPresetsKey, AiApiConfig.encodeList(configs));
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

  Future<bool> loadGlobalUseCurrentGameKnowledge() async {
    final prefs = await _prefs;
    return prefs.getBool(_globalUseCurrentGameKnowledgeKey) ?? false;
  }

  Future<void> saveGlobalUseCurrentGameKnowledge(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_globalUseCurrentGameKnowledgeKey, enabled);
  }

  Future<bool> loadCheckForUpdates() async {
    final prefs = await _prefs;
    return prefs.getBool(_checkForUpdatesKey) ?? true;
  }

  Future<void> saveCheckForUpdates(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_checkForUpdatesKey, enabled);
  }

  Future<AssistantMode> loadAssistantMode() async {
    final prefs = await _prefs;
    return AssistantModeX.fromCode(prefs.getString(_assistantModeKey));
  }

  Future<void> saveAssistantMode(AssistantMode mode) async {
    final prefs = await _prefs;
    await prefs.setString(_assistantModeKey, mode.code);
  }

  Future<String?> loadSelectedConversationId() async {
    final prefs = await _prefs;
    final String? value = prefs.getString(_selectedConversationKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveSelectedConversationId(String conversationId) async {
    final prefs = await _prefs;
    await prefs.setString(_selectedConversationKey, conversationId);
  }

  Future<void> clearSelectedConversationId() async {
    final prefs = await _prefs;
    await prefs.remove(_selectedConversationKey);
  }

  Future<List<AppActivity>> loadActivities() async {
    final prefs = await _prefs;
    final String? stored = prefs.getString(_activitiesKey);
    if (stored == null || stored.trim().isEmpty) {
      return const <AppActivity>[];
    }

    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! List<Object?>) {
        return const <AppActivity>[];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AppActivity.fromMap)
          .toList(growable: false);
    } catch (_) {
      return const <AppActivity>[];
    }
  }

  Future<void> saveActivities(Iterable<AppActivity> activities) async {
    final prefs = await _prefs;
    await prefs.setString(
      _activitiesKey,
      jsonEncode(
        activities.map((AppActivity activity) => activity.toMap()).toList(),
      ),
    );
  }

  /// Loads the lightweight desktop library index. Document bytes are never
  /// stored here; they remain in the asset cache and are fetched on demand.
  Future<List<DesktopLibraryResource>> loadDesktopLibraryResources() async {
    final prefs = await _prefs;
    final String? stored = prefs.getString(_desktopLibraryResourcesKey);
    if (stored == null || stored.trim().isEmpty) {
      return const <DesktopLibraryResource>[];
    }

    try {
      final Object? decoded = jsonDecode(stored);
      final List<Object?> entries;
      if (decoded is List<Object?>) {
        entries = decoded;
      } else if (decoded is Map<String, dynamic> &&
          decoded['resources'] is List<Object?>) {
        entries = decoded['resources'] as List<Object?>;
      } else {
        return const <DesktopLibraryResource>[];
      }
      return entries
          .whereType<Map<String, dynamic>>()
          .map(DesktopLibraryResource.fromMap)
          .whereType<DesktopLibraryResource>()
          .toList(growable: false);
    } catch (_) {
      return const <DesktopLibraryResource>[];
    }
  }

  Future<void> saveDesktopLibraryResources(
    Iterable<DesktopLibraryResource> resources,
  ) async {
    final prefs = await _prefs;
    await prefs.setString(
      _desktopLibraryResourcesKey,
      jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        'resources': resources
            .map((DesktopLibraryResource resource) => resource.toMap())
            .toList(growable: false),
      }),
    );
  }

  Future<List<FavoriteGameRecord>> loadFavoriteGames() async {
    final prefs = await _prefs;
    final String? stored = prefs.getString(_favoriteGamesKey);
    if (stored == null || stored.trim().isEmpty) {
      return const <FavoriteGameRecord>[];
    }

    try {
      final Object? decoded = jsonDecode(stored);
      final Object? rawRecords = decoded is Map<String, dynamic>
          ? decoded['records']
          : decoded;
      if (rawRecords is! List<Object?>) {
        return const <FavoriteGameRecord>[];
      }
      return rawRecords
          .whereType<Map<String, dynamic>>()
          .map(FavoriteGameRecord.tryFromMap)
          .whereType<FavoriteGameRecord>()
          .toList(growable: false);
    } catch (_) {
      return const <FavoriteGameRecord>[];
    }
  }

  Future<void> saveFavoriteGames(Iterable<FavoriteGameRecord> records) async {
    final prefs = await _prefs;
    await prefs.setString(
      _favoriteGamesKey,
      jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        'records': records
            .map((FavoriteGameRecord record) => record.toMap())
            .toList(growable: false),
      }),
    );
  }
}
