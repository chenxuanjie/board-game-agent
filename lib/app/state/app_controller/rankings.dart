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
    final trace = reactionDiagnostics.start('刷新喜欢榜');
    try {
      if (!await _refreshFavoriteRankingsNow(trace)) {
        trace.finish(failed: true, detail: '本机收藏读取失败，未请求公共统计，保留现有数据');
        return;
      }
      final state = favoriteStatistics.status;
      trace.finish(
        failed: state == GameVoteSyncStatus.pending,
        detail: state == GameVoteSyncStatus.synced
            ? '本轮远端统计已保存并显示'
            : state == GameVoteSyncStatus.paused
            ? '账号同步已暂停，未请求 NAS'
            : state == GameVoteSyncStatus.localOnly
            ? '当前仅本机统计，未确认远端'
            : '未获得新的远端统计，保留上次结果',
      );
    } catch (failure) {
      trace.finish(
        failed: true,
        detail: ReactionSyncDiagnostics.failureLabel(failure),
      );
      rethrow;
    }
  }

  Future<bool> _refreshFavoriteRankingsNow(ReactionTrace trace) async {
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
      await trace.measure(
        '等待本机提交释放',
        () => _personalReloadWork!.timeout(remaining),
      );
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
      if (!await read) return false;
    }
    if (epoch != _identityScopeEpoch || _switchingIdentityScope) {
      throw StateError('账号已切换');
    }
    await trace.measure('请求新鲜公共统计', () => favoriteStatistics.sync(fresh: true));
    return true;
  }

  bool get favoriteRankingSourceReady => _favoriteRecordsLoaded;
}
