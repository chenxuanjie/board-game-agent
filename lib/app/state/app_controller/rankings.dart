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
    if (_controllerDisposed || _identityScopeRequests > 0) {
      throw StateError('账号不可用');
    }
    final epoch = _identityScopeEpoch;
    // A brief journal projection is not an account switch. Queue ranking entry
    // behind that commit instead of silently dropping its refresh request.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (_personalReloadWork != null) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) throw TimeoutException('本机提交等待超时');
      await _personalReloadWork!.timeout(remaining);
      if (epoch != _identityScopeEpoch || _identityScopeRequests > 0) {
        throw StateError('账号已切换');
      }
    }
    if (epoch != _identityScopeEpoch || _switchingIdentityScope) {
      throw StateError('账号已切换');
    }
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
    if (epoch != _identityScopeEpoch || _switchingIdentityScope) {
      throw StateError('账号已切换');
    }
    await favoriteStatistics.sync(fresh: true);
  }

  bool get favoriteRankingSourceReady => _favoriteRecordsLoaded;

  bool get favoriteRankingHasData =>
      hasGames &&
      (favoriteStatistics.hasCachedRemoteCounts ||
          (favoriteStatistics.ready &&
              favoriteStatistics.status == GameVoteSyncStatus.localOnly &&
              _accountReactionProvider == null &&
              _favoriteRemoteProvider == null));

  String? get favoriteRankingRealtimeError => _accountReactionError?.call();

  /// A page retry repairs missing catalog data, a failed aggregate read and
  /// the public subscription without making the user choose separate lanes.
  Future<void> refreshFavoriteRankingPage() async {
    final epoch = _identityScopeEpoch;
    if (!hasGames || gameCatalogFailed) await retryGameCatalog();
    if (_controllerDisposed || epoch != _identityScopeEpoch) return;
    await refreshFavoriteRankings();
    if (_controllerDisposed || epoch != _identityScopeEpoch) return;
    if (favoriteStatistics.publicationStatus ==
        GameVotePublicationStatus.failed) {
      await favoriteStatistics.publish();
    }
    if (_controllerDisposed || epoch != _identityScopeEpoch) return;
    if (favoriteRankingRealtimeError != null)
      await _recoverPublicReactions?.call();
  }
}
