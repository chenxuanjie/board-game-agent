part of '../app_controller.dart';

extension AppCollectionController on AppController {
  List<GameInfo> get defaultNationalDayGames {
    const slugs = ['carcassonne_3', 'splendor', 'harmonies'];
    final preferred = slugs.expand(
      (slug) => games.where((game) => game.slug == slug),
    );
    return {...preferred, ...games}.take(3).toList();
  }

  List<GameInfo> get nationalDayGames => nationalDayList.slugs
      .expand((slug) => games.where((game) => game.slug == slug))
      .toList();

  String get nationalDayShareText =>
      '${copy.localized('国庆聚会 · 桌游清单', 'National Day · Games to play')}\n'
      '${nationalDayGames.map((game) => '• ${game.title}｜${game.playerCount}｜${game.playTime}').join('\n')}';

  Future<bool> toggleFavorite(GameInfo game) {
    final Future<bool> operation = _favoriteMutationQueue
        .catchError((Object _) {})
        .then<bool>((_) => _toggleFavoriteNow(game));
    _favoriteMutationQueue = operation.then<void>((_) {});
    return operation;
  }

  Future<bool> _toggleFavoriteNow(GameInfo game) async {
    final slug = game.slug.trim();
    if (slug.isEmpty) return false;

    final previous = Map<String, DateTime>.of(_favoriteCreatedAtBySlug);
    if (_favoriteCreatedAtBySlug.containsKey(slug)) {
      _favoriteCreatedAtBySlug.remove(slug);
    } else {
      _favoriteCreatedAtBySlug[slug] = DateTime.now().toUtc();
    }
    _notifyListeners();

    try {
      await _preferencesService.saveFavoriteGames(
        _favoriteCreatedAtBySlug.entries.map(
          (entry) =>
              FavoriteGameRecord(gameSlug: entry.key, createdAt: entry.value),
        ),
      );
      return true;
    } catch (error) {
      _favoriteCreatedAtBySlug
        ..clear()
        ..addAll(previous);
      _notifyListeners();
      debugPrint('[favorites] save failed: $error');
      return false;
    }
  }

  Future<bool> recordSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) return Future<bool>.value(false);

    final previous = List<SearchHistoryRecord>.from(_searchHistory);
    final normalized = query.toLowerCase();
    _searchHistory = <SearchHistoryRecord>[
      SearchHistoryRecord(query: query, searchedAt: DateTime.now().toUtc()),
      ..._searchHistory.where((record) => record.normalizedQuery != normalized),
    ].take(PreferencesService.recentSearchesLimit).toList(growable: false);
    final int stateVersion = ++_searchHistoryStateVersion;
    _notifyListeners();
    return _queueSearchHistorySave(
      snapshot: _searchHistory,
      previous: previous,
      stateVersion: stateVersion,
    );
  }

  Future<bool> removeSearch(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return Future<bool>.value(false);

    final previous = List<SearchHistoryRecord>.from(_searchHistory);
    _searchHistory = _searchHistory
        .where((record) => record.normalizedQuery != normalized)
        .toList(growable: false);
    final int stateVersion = ++_searchHistoryStateVersion;
    _notifyListeners();
    return _queueSearchHistorySave(
      snapshot: _searchHistory,
      previous: previous,
      stateVersion: stateVersion,
    );
  }

  Future<bool> clearSearchHistory() {
    final previous = List<SearchHistoryRecord>.from(_searchHistory);
    _searchHistory = <SearchHistoryRecord>[];
    final int stateVersion = ++_searchHistoryStateVersion;
    _notifyListeners();
    return _queueSearchHistorySave(
      snapshot: _searchHistory,
      previous: previous,
      stateVersion: stateVersion,
    );
  }

  Future<bool> _queueSearchHistorySave({
    required List<SearchHistoryRecord> snapshot,
    required List<SearchHistoryRecord> previous,
    required int stateVersion,
  }) {
    final Future<void> write = _searchHistoryMutationQueue.then<void>(
      (_) => _preferencesService.saveSearchHistory(snapshot),
    );
    final Future<bool> result = write.then<bool>(
      (_) => true,
      onError: (Object error, StackTrace stackTrace) {
        if (_searchHistoryStateVersion == stateVersion) {
          _searchHistory = previous;
          _notifyListeners();
        }
        debugPrint('[search-history] save failed: $error');
        return false;
      },
    );
    _searchHistoryMutationQueue = result.then<void>((_) {});
    return result;
  }

  Future<bool> recordRecentlyViewed(GameInfo game) {
    final slug = game.slug.trim();
    if (slug.isEmpty) return Future<bool>.value(false);

    final previous = List<RecentGameRecord>.from(_recentGameRecords);
    final normalized = slug.toLowerCase();
    _recentGameRecords = <RecentGameRecord>[
      RecentGameRecord(gameSlug: slug, viewedAt: DateTime.now().toUtc()),
      ..._recentGameRecords.where(
        (record) => record.normalizedGameSlug != normalized,
      ),
    ].take(PreferencesService.recentGamesLimit).toList(growable: false);
    final int stateVersion = ++_recentGamesStateVersion;
    _notifyListeners();
    return _queueRecentGamesSave(
      snapshot: _recentGameRecords,
      previous: previous,
      stateVersion: stateVersion,
    );
  }

  Future<bool> removeRecentlyViewed(GameInfo game) {
    final normalized = game.slug.trim().toLowerCase();
    if (normalized.isEmpty) return Future<bool>.value(false);

    final previous = List<RecentGameRecord>.from(_recentGameRecords);
    _recentGameRecords = _recentGameRecords
        .where((record) => record.normalizedGameSlug != normalized)
        .toList(growable: false);
    final int stateVersion = ++_recentGamesStateVersion;
    _notifyListeners();
    return _queueRecentGamesSave(
      snapshot: _recentGameRecords,
      previous: previous,
      stateVersion: stateVersion,
    );
  }

  Future<bool> clearRecentlyViewed() {
    final previous = List<RecentGameRecord>.from(_recentGameRecords);
    _recentGameRecords = <RecentGameRecord>[];
    final int stateVersion = ++_recentGamesStateVersion;
    _notifyListeners();
    return _queueRecentGamesSave(
      snapshot: _recentGameRecords,
      previous: previous,
      stateVersion: stateVersion,
    );
  }

  Future<bool> _queueRecentGamesSave({
    required List<RecentGameRecord> snapshot,
    required List<RecentGameRecord> previous,
    required int stateVersion,
  }) {
    final Future<void> write = _recentGamesMutationQueue.then<void>(
      (_) => _preferencesService.saveRecentGames(snapshot),
    );
    final Future<bool> result = write.then<bool>(
      (_) => true,
      onError: (Object error, StackTrace stackTrace) {
        if (_recentGamesStateVersion == stateVersion) {
          _recentGameRecords = previous;
          _notifyListeners();
        }
        debugPrint('[recent-games] save failed: $error');
        return false;
      },
    );
    _recentGamesMutationQueue = result.then<void>((_) {});
    return result;
  }
}
