part of '../app_controller.dart';

extension AppRankingController on AppController {
  Future<bool> _ensureFavoriteRecords() async {
    if (_favoriteRecordsLoaded) return true;
    try {
      final records = await _preferencesService.loadFavoriteGames();
      _favoriteCreatedAtBySlug
        ..clear()
        ..addEntries(
          records.map((record) => MapEntry(record.gameSlug, record.createdAt)),
        );
      _favoriteRecordsLoaded = true;
      _committedFavoriteSlugs
        ..clear()
        ..addAll(_favoriteCreatedAtBySlug.keys);
      return true;
    } catch (_) {
      return false;
    }
  }

  List<GameRankingEntry> get favoriteRankings =>
      GameFavoriteRanker.rank(_games, favoriteStatistics.count);

  Future<void> refreshFavoriteRankings() async {
    if (!_favoriteRecordsLoaded) {
      final read = _favoriteMutationQueue.catchError((Object _) {}).then<bool>((
        _,
      ) async {
        final loaded = await _ensureFavoriteRecords();
        if (loaded) _notifyListeners();
        return loaded;
      });
      _favoriteMutationQueue = read.then<void>((_) {});
      if (!await read) return;
    }
    await favoriteStatistics.sync();
  }

  bool get favoriteRankingSourceReady => _favoriteRecordsLoaded;
}
