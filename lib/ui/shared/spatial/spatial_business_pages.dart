part of 'spatial_workspace.dart';

/// Desktop panes share business state with compact pages, without embedding a
/// phone Scaffold, its brand header or its fixed content width on wide screens.
extension _SpatialBusinessPages on _SpatialWorkspaceState {
  Widget _businessPage({required bool wide}) {
    final body = switch (_page) {
      'recommendations' => SpatialRecommendationsPage(
        controller: c,
        onBack: _back,
        onOpenGame: _openGame,
      ),
      'games' =>
        wide
            ? _desktopGames('games', c.copy.localized('桌游库', 'Game Library'))
            : MobileLibraryContent(
                controller: c,
                onOpenGame: _openGame,
                onActivities: _activities,
                onProfile: () => _select('account'),
                accountActions: const SizedBox.shrink(),
              ),
      'rankings' => GameRankingScreen(
        controller: c,
        onOpenGame: _openGame,
        onBack: _back,
      ),
      'assistant' =>
        wide
            ? DesktopAssistantPane(
                key: _assistantPane,
                controller: c,
                onConfigureAi: () =>
                    _navigator.currentState?.pushNamed('/settings/ai'),
              )
            : UniversalAiScreen(controller: c),
      'topic' =>
        wide
            ? DesktopNationalDayPage(controller: c, onOpenGame: _openGame)
            : MobileNationalDayScreen(controller: c, onOpenGame: _openGame),
      'downloads' =>
        wide
            ? DesktopLibraryPane(controller: c)
            : MobileRuleMaterialsScreen(controller: c),
      'account' => AccountScreen(onBack: _back),
      'settings' => _settingsPage(wide: wide),
      'favorites' =>
        wide
            ? _desktopGames('favorites', '我的喜欢', games: c.favoriteGames)
            : _collection(c.favoriteGames, '我的喜欢'),
      'recent' =>
        wide
            ? _desktopGames('recent', '最近浏览', games: c.recentlyViewedGames)
            : _collection(c.recentlyViewedGames, '最近浏览'),
      _ => const SizedBox.shrink(),
    };
    return ColoredBox(color: AppPalette.of(context).surface, child: body);
  }

  ScrollController _scrollFor(String page) => _pageScrolls.putIfAbsent(
    page,
    () => ScrollController(keepScrollOffset: false),
  );

  Widget _desktopScroll(
    String page,
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(24),
  }) {
    final scroll = _scrollFor(page);
    return Scrollbar(
      controller: scroll,
      child: SingleChildScrollView(
        key: PageStorageKey('spatial-desktop-scroll-$page'),
        controller: scroll,
        padding: padding,
        child: child,
      ),
    );
  }

  Widget _desktopGames(String page, String title, {List<GameInfo>? games}) =>
      Column(
        key: ValueKey('spatial-wide-$page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _desktopScroll(
              page,
              DesktopGamesPane(
                controller: c,
                sourceGames: games,
                browseState: games == null
                    ? null
                    : _collectionBrowse.putIfAbsent(
                        page,
                        LibraryBrowseState.new,
                      ),
                scrollController: _scrollFor(page),
                showPreview: true,
                posterAspectRatio: SpatialGamePoster.aspectRatio,
                posterBuilder: (game, onOpen) => SpatialGamePoster(
                  controller: c,
                  game: game,
                  onOpen: onOpen,
                  compact: false,
                ),
                onNavigate: _select,
                onOpenGame: _openGame,
                onToggleFavorite: (game) =>
                    unawaited(_toggleSpatialFavorite(game)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            ),
          ),
        ],
      );

  Widget _settingsPage({required bool wide, bool focusAi = false}) => wide
      ? Scaffold(
          key: const ValueKey('spatial-wide-settings'),
          backgroundColor: Colors.transparent,
          body: _desktopScroll(
            'settings',
            DesktopSettingsPane(
              controller: c,
              focusAiSettings: focusAi,
              transferService: widget.transferService,
              onOpenAbout: widget.onOpenAbout,
            ),
          ),
        )
      : MobileSettingsScreen(
          controller: c,
          focusAiSettings: focusAi,
          onOpenAbout: widget.onOpenAbout,
          transferService: widget.transferService,
        );

  Widget _detailPage({required bool wide}) => wide
      ? ColoredBox(
          color: AppPalette.of(context).surface,
          child: _desktopScroll(
            'detail-${_detail!.id}',
            DesktopGameDetailPane(
              controller: c,
              game: _detail!,
              backTooltip: '返回',
              onBack: _back,
              onOpenRules: () => _openDesktopRules(_detail!),
              onAskAi: () => _askSpatialAi(_detail!),
              onToggleFavorite: (game) =>
                  unawaited(_toggleSpatialFavorite(game)),
              onOpenGame: _openGame,
              favoriteSaving: _favoriteSaving.contains(_detail!.id),
              favoritePreview: _favoritePreview[_detail!.id],
            ),
            padding: EdgeInsets.zero,
          ),
        )
      : GameDetailScreen(controller: c, game: _detail!);

  Widget _collection(List<GameInfo> games, String title) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      leading: BackButton(onPressed: _back),
    ),
    body: games.isEmpty
        ? const Center(child: Text('暂无内容'))
        : ListView.builder(
            itemCount: games.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(games[i].title),
              subtitle: Text(games[i].categoryLine),
              onTap: () => _openGame(games[i]),
            ),
          ),
  );
}
