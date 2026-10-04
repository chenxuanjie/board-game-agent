part of '../app_controller.dart';

extension AppRankingController on AppController {
  Future<bool> _ensureFavoriteRecords() async {
    if (_favoriteRecordsLoaded) return true;
    final epoch = _identityScopeEpoch;
    try {
      final records = await _preferencesService.loadFavoriteGames();
      if (epoch != _identityScopeEpoch) return false;
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
    if (_switchingIdentityScope) return;
    final epoch = _identityScopeEpoch;
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
    if (epoch != _identityScopeEpoch || _switchingIdentityScope) return;
    await favoriteStatistics.sync();
  }

  bool get favoriteRankingSourceReady => _favoriteRecordsLoaded;
}
