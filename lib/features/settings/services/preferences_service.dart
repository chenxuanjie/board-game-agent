import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/app_activity.dart';
import '../../assistant/models/ai_api_config.dart';
import '../../assistant/models/ai_answer_mode.dart';
import '../../assistant/models/assistant_mode.dart';
import '../../library/models/asset_source_config.dart';
import '../../../core/localization/app_language.dart';
import '../../../core/theme/color_scheme_option.dart';
import '../../library/models/desktop_library_resource.dart';
import '../../games/models/daily_recommendation_record.dart';
import '../../games/models/favorite_game_record.dart';
import '../../games/models/recent_game_record.dart';
import '../../games/models/search_history_record.dart';

class PreferencesService {
  PreferencesService({String? identityUserId})
    : identityUserId = validateIdentityUserId(identityUserId);

  /// Immutable: outstanding writes always retain their original account.
  /// Null retains every legacy guest key. Existing data is never adopted.
  final String? identityUserId;
  final Set<Future<void>> _pendingPersonalWrites = {};
  Future<void> _galleryWriteQueue = Future<void>.value();

  /// Includes writes owned by votes and the seasonal list, outside AppController.
  Future<void> drainPersonalWrites() async {
    while (_pendingPersonalWrites.isNotEmpty) {
      await Future.wait(_pendingPersonalWrites.toList());
    }
  }

  Future<void> _trackPersonalWrite(Future<void> Function() action) {
    final write = action();
    _pendingPersonalWrites.add(write);
    // Observe cleanup errors without changing the caller's failure result.
    write.then<void>(
      (_) => _pendingPersonalWrites.remove(write),
      onError: (Object _, StackTrace _) => _pendingPersonalWrites.remove(write),
    );
    return write;
  }

  Future<void> _requirePersonalWrite(Future<bool> result) async {
    if (!await result) throw StateError('Personal preferences write failed');
  }

  PreferencesService forIdentityScope(String? userId) =>
      userId == identityUserId
      ? this
      : PreferencesService(identityUserId: userId);

  static String? validateIdentityUserId(String? userId) {
    if (userId != null && (userId.trim().isEmpty || userId.length > 4096)) {
      throw ArgumentError.value(
        userId,
        'userId',
        'Expected a stable identity ID',
      );
    }
    return userId;
  }

  /// Fixed alphabet and length; never interpolate an identity into a path.
  static String? identityStorageId(String? userId) {
    validateIdentityUserId(userId);
    return userId == null
        ? null
        : sha256.convert(utf8.encode(userId)).toString();
  }

  String _personalKey(String key) {
    final scope = identityStorageId(identityUserId);
    return scope == null ? key : 'personal_v1.$scope.$key';
  }

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
  static const _recentSearchesKey = 'recent_searches_v1';
  static const _recentGamesKey = 'recent_games_v1';
  static const _dailyRecommendationsKey = 'daily_recommendations_v1';
  static const _nationalDayGamesKey = 'national_day_game_slugs_v1';
  static const _gameVoteCacheKey = 'national_day_votes_v1';
  static const _gameGallerySelectionsKey = 'game_gallery_selections_v1';
  static const int recentSearchesLimit = 8;
  static const int recentGamesLimit = 20;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Map<String, String>> loadGameGallerySelections() async {
    final raw = (await _prefs).getString(
      _personalKey(_gameGallerySelectionsKey),
    );
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String &&
              entry.value is String &&
              (entry.value as String).isNotEmpty)
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> saveGameGallerySelection(String slug, String path) =>
      _trackPersonalWrite(() {
        final write = _galleryWriteQueue.catchError((Object _) {}).then((
          _,
        ) async {
          final selections = await loadGameGallerySelections();
          selections[slug] = path;
          final prefs = await _prefs;
          await _requirePersonalWrite(
            prefs.setString(
              _personalKey(_gameGallerySelectionsKey),
              jsonEncode(selections),
            ),
          );
        });
        _galleryWriteQueue = write;
        return write;
      });

  static const accountCloudPreferenceKeys = <String>{
    _voiceReplyKey,
    _assistantModeKey,
    _gameAnswerModeKey,
    _globalAnswerModeKey,
    _globalUseCurrentGameKnowledgeKey,
  };
  Future<Map<String, Object>> accountCloudPreferences() async {
    final prefs = await _prefs;
    return {
      for (final key in accountCloudPreferenceKeys)
        if (prefs.get(_personalKey(key)) case final Object value) key: value,
    };
  }

  Future<void> applyAccountCloudPreferences(Map<String, Object> values) =>
      _trackPersonalWrite(() async {
        final prefs = await _prefs;
        for (final key in accountCloudPreferenceKeys) {
          final value = values[key];
          final boolean =
              key == _voiceReplyKey || key == _globalUseCurrentGameKnowledgeKey;
          if (value != null && (boolean ? value is! bool : value is! String)) {
            throw const FormatException('个人偏好格式错误');
          }
          final saved = value == null
              ? await prefs.remove(_personalKey(key))
              : value is bool
              ? await prefs.setBool(_personalKey(key), value)
              : await prefs.setString(_personalKey(key), value as String);
          if (!saved) throw StateError('个人偏好保存失败');
        }
      });

  Future<String?> loadGameVoteCache() async =>
      (await _prefs).getString(_personalKey(_gameVoteCacheKey));

  Future<String?> loadFavoriteRankingCache() async =>
      (await _prefs).getString(_personalKey('game_favorite_ranking_v1'));

  Future<void> saveFavoriteRankingCache(String value) async {
    await _trackPersonalWrite(() async {
      if (!await (await _prefs).setString(
        _personalKey('game_favorite_ranking_v1'),
        value,
      )) {
        throw StateError('Favorite ranking cache write failed');
      }
    });
  }

  Future<void> saveGameVoteCache(String value) async {
    await _trackPersonalWrite(() async {
      if (!await (await _prefs).setString(
        _personalKey(_gameVoteCacheKey),
        value,
      )) {
        throw StateError('Game votes could not be saved');
      }
    });
  }

  Future<List<String>?> loadNationalDayGameSlugs() async =>
      (await _prefs).getStringList(_personalKey(_nationalDayGamesKey));

  Future<void> saveNationalDayGameSlugs(Iterable<String> slugs) async {
    await _trackPersonalWrite(() async {
      final saved = await (await _prefs).setStringList(
        _personalKey(_nationalDayGamesKey),
        slugs.toSet().toList(),
      );
      if (!saved) throw StateError('National Day list could not be saved');
    });
  }

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
    return prefs.getBool(_personalKey(_voiceReplyKey)) ?? false;
  }

  Future<void> saveVoiceReplyEnabled(bool enabled) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.setBool(_personalKey(_voiceReplyKey), enabled),
      );
    });
  }

  Future<ColorSchemeOption> loadColorScheme() async {
    final prefs = await _prefs;
    if (!prefs.containsKey(_colorSchemeKey)) {
      return defaultColorScheme;
    }
    return ColorSchemeOptionX.fromCode(prefs.getString(_colorSchemeKey));
  }

  Future<void> saveColorScheme(ColorSchemeOption scheme) async {
    final prefs = await _prefs;
    await prefs.setString(_colorSchemeKey, scheme.code);
  }

  Future<bool> loadCinemaGlassEnabled() async =>
      (await _prefs).getBool('cinema_glass_enabled') ?? true;
  Future<void> saveCinemaGlassEnabled(bool enabled) async {
    if (!await (await _prefs).setBool('cinema_glass_enabled', enabled)) {
      throw StateError('外观设置未保存');
    }
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
    if (!await prefs.setString(_aiApiConfigKey, config.toJson())) {
      throw StateError('AI configuration write failed');
    }
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
    final saved = await prefs.setString(
      _assetSourceOrderKey,
      AssetSourceConfig.encodeList(configs),
    );
    if (!saved) throw StateError('Resource sources could not be saved');
  }

  Future<AiAnswerMode> loadGameAnswerMode() async {
    final prefs = await _prefs;
    return AiAnswerModeX.fromCode(
      prefs.getString(_personalKey(_gameAnswerModeKey)),
      fallback: AiAnswerMode.knowledgeOnly,
    );
  }

  Future<void> saveGameAnswerMode(AiAnswerMode mode) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      if (!await prefs.setString(_personalKey(_gameAnswerModeKey), mode.code)) {
        throw StateError('Game answer mode write failed');
      }
    });
  }

  Future<AiAnswerMode> loadGlobalAnswerMode() async {
    final prefs = await _prefs;
    return AiAnswerModeX.fromCode(
      prefs.getString(_personalKey(_globalAnswerModeKey)),
      fallback: AiAnswerMode.knowledgeThenDirect,
    );
  }

  Future<void> saveGlobalAnswerMode(AiAnswerMode mode) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      if (!await prefs.setString(
        _personalKey(_globalAnswerModeKey),
        mode.code,
      )) {
        throw StateError('Global answer mode write failed');
      }
    });
  }

  Future<bool> loadGlobalUseCurrentGameKnowledge() async {
    final prefs = await _prefs;
    return prefs.getBool(_personalKey(_globalUseCurrentGameKnowledgeKey)) ??
        false;
  }

  Future<void> saveGlobalUseCurrentGameKnowledge(bool enabled) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.setBool(_personalKey(_globalUseCurrentGameKnowledgeKey), enabled),
      );
    });
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
    return AssistantModeX.fromCode(
      prefs.getString(_personalKey(_assistantModeKey)),
    );
  }

  Future<void> saveAssistantMode(AssistantMode mode) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.setString(_personalKey(_assistantModeKey), mode.code),
      );
    });
  }

  Future<String?> loadSelectedConversationId() async {
    final prefs = await _prefs;
    final String? value = prefs
        .getString(_personalKey(_selectedConversationKey))
        ?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveSelectedConversationId(String conversationId) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.setString(_personalKey(_selectedConversationKey), conversationId),
      );
    });
  }

  Future<void> clearSelectedConversationId() async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.remove(_personalKey(_selectedConversationKey)),
      );
    });
  }

  Future<List<AppActivity>> loadActivities() async {
    final prefs = await _prefs;
    final String? stored = prefs.getString(_personalKey(_activitiesKey));
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
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.setString(
          _personalKey(_activitiesKey),
          jsonEncode(
            activities.map((AppActivity activity) => activity.toMap()).toList(),
          ),
        ),
      );
    });
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
    final String? stored = prefs.getString(_personalKey(_favoriteGamesKey));
    if (stored == null || stored.trim().isEmpty) {
      return const <FavoriteGameRecord>[];
    }

    try {
      final Object? decoded = jsonDecode(stored);
      final Object? rawRecords = decoded is Map<String, dynamic>
          ? decoded['records']
          : decoded;
      if (rawRecords is! List<Object?>) {
        throw const FormatException('Invalid favorites data');
      }
      final records = <FavoriteGameRecord>[];
      for (final raw in rawRecords) {
        final record = raw is Map<String, dynamic>
            ? FavoriteGameRecord.tryFromMap(raw)
            : null;
        if (record == null) {
          throw const FormatException('Invalid favorites data');
        }
        records.add(record);
      }
      return records;
    } catch (_) {
      // A damaged source must not be uploaded as an empty favorites snapshot.
      throw const FormatException('Invalid favorites data');
    }
  }

  Future<void> saveFavoriteGames(Iterable<FavoriteGameRecord> records) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      final saved = await prefs.setString(
        _personalKey(_favoriteGamesKey),
        jsonEncode(<String, dynamic>{
          'schemaVersion': 1,
          'records': records
              .map((FavoriteGameRecord record) => record.toMap())
              .toList(growable: false),
        }),
      );
      if (!saved) throw StateError('Favorites could not be saved');
    });
  }

  Future<List<SearchHistoryRecord>> loadSearchHistory() async {
    final prefs = await _prefs;
    final Object? stored = prefs.get(_personalKey(_recentSearchesKey));
    if (stored is List) {
      final DateTime migratedAt = DateTime.now().toUtc();
      return _normalizeSearchHistory(
        stored.whereType<String>().map(
          (query) => SearchHistoryRecord(query: query, searchedAt: migratedAt),
        ),
      );
    }
    if (stored is! String || stored.trim().isEmpty) {
      return const <SearchHistoryRecord>[];
    }

    try {
      final Object? decoded = jsonDecode(stored);
      final Object? rawRecords = decoded is Map<String, dynamic>
          ? decoded['records']
          : decoded;
      if (rawRecords is! List) {
        return const <SearchHistoryRecord>[];
      }
      return _normalizeSearchHistory(
        rawRecords
            .whereType<Map<String, dynamic>>()
            .map(SearchHistoryRecord.tryFromMap)
            .whereType<SearchHistoryRecord>(),
      );
    } catch (_) {
      return const <SearchHistoryRecord>[];
    }
  }

  Future<void> saveSearchHistory(Iterable<SearchHistoryRecord> records) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.setString(
          _personalKey(_recentSearchesKey),
          jsonEncode(<String, dynamic>{
            'schemaVersion': 1,
            'records': _normalizeSearchHistory(
              records,
            ).map((record) => record.toMap()).toList(growable: false),
          }),
        ),
      );
    });
  }

  Future<List<String>> loadRecentSearches() async {
    final records = await loadSearchHistory();
    return records.map((record) => record.query).toList(growable: false);
  }

  Future<void> saveRecentSearches(Iterable<String> queries) async {
    final DateTime searchedAt = DateTime.now().toUtc();
    await saveSearchHistory(
      queries.map(
        (query) => SearchHistoryRecord(query: query, searchedAt: searchedAt),
      ),
    );
  }

  Future<List<RecentGameRecord>> loadRecentGames() async {
    final prefs = await _prefs;
    final String? stored = prefs.getString(_personalKey(_recentGamesKey));
    if (stored == null || stored.trim().isEmpty) {
      return const <RecentGameRecord>[];
    }

    try {
      final Object? decoded = jsonDecode(stored);
      final Object? rawRecords = decoded is Map<String, dynamic>
          ? decoded['records']
          : decoded;
      if (rawRecords is! List) return const <RecentGameRecord>[];
      return _normalizeRecentGames(
        rawRecords
            .whereType<Map<String, dynamic>>()
            .map(RecentGameRecord.tryFromMap)
            .whereType<RecentGameRecord>(),
      );
    } catch (_) {
      return const <RecentGameRecord>[];
    }
  }

  Future<void> saveRecentGames(Iterable<RecentGameRecord> records) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.setString(
          _personalKey(_recentGamesKey),
          jsonEncode(<String, dynamic>{
            'schemaVersion': 1,
            'records': _normalizeRecentGames(
              records,
            ).map((record) => record.toMap()).toList(growable: false),
          }),
        ),
      );
    });
  }

  Future<List<DailyRecommendationRecord>> loadDailyRecommendations() async {
    final prefs = await _prefs;
    final stored = prefs.getString(_personalKey(_dailyRecommendationsKey));
    if (stored == null || stored.isEmpty) {
      return const <DailyRecommendationRecord>[];
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return const <DailyRecommendationRecord>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DailyRecommendationRecord.tryFromMap)
          .whereType<DailyRecommendationRecord>()
          .take(30)
          .toList(growable: false);
    } catch (_) {
      return const <DailyRecommendationRecord>[];
    }
  }

  Future<void> saveDailyRecommendations(
    List<DailyRecommendationRecord> records,
  ) async {
    await _trackPersonalWrite(() async {
      final prefs = await _prefs;
      await _requirePersonalWrite(
        prefs.setString(
          _personalKey(_dailyRecommendationsKey),
          jsonEncode(records.map((record) => record.toMap()).toList()),
        ),
      );
    });
  }

  static List<SearchHistoryRecord> _normalizeSearchHistory(
    Iterable<SearchHistoryRecord> records,
  ) {
    final seen = <String>{};
    final result = <SearchHistoryRecord>[];
    for (final record in records) {
      final query = record.query.trim();
      final normalized = query.toLowerCase();
      if (query.isEmpty || !seen.add(normalized)) continue;
      result.add(
        SearchHistoryRecord(
          query: query,
          searchedAt: record.searchedAt.toUtc(),
        ),
      );
      if (result.length >= recentSearchesLimit) break;
    }
    return result;
  }

  static List<RecentGameRecord> _normalizeRecentGames(
    Iterable<RecentGameRecord> records,
  ) {
    final seen = <String>{};
    final result = <RecentGameRecord>[];
    for (final record in records) {
      final slug = record.gameSlug.trim();
      if (slug.isEmpty || !seen.add(slug.toLowerCase())) continue;
      result.add(
        RecentGameRecord(gameSlug: slug, viewedAt: record.viewedAt.toUtc()),
      );
      if (result.length >= recentGamesLimit) break;
    }
    return result;
  }
}
