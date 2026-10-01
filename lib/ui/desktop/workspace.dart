import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:webdav_settings/webdav_settings.dart';
import '../../features/assistant/models/ai_conversation.dart';
import '../../core/models/app_activity.dart';
import '../../features/library/models/desktop_library_resource.dart';
import '../../features/games/models/game_info.dart';
import '../../app/state/app_controller.dart';
import 'business_panes.dart';
import 'home_pane.dart';
import 'national_day_page.dart';
import 'games_pane.dart';
import 'favorites_pane.dart';
import 'game_detail_pane.dart';
import 'home_search_overlay.dart';
import 'settings_pane.dart';
import 'sidebar.dart';
import 'desktop_responsive.dart';
import 'theme.dart';
import 'window_controls.dart';
import '../shared/app_page_transition.dart';
import '../shared/game_cover_motion.dart';
import 'desktop_resolved_image.dart';

class DesktopWorkspace extends StatefulWidget {
  const DesktopWorkspace({
    super.key,
    required this.controller,
    required this.onOpenAbout,
    this.webDavSettingsController,
    this.enableNativeWindowControls = true,
  });
  final AppController controller;
  final VoidCallback onOpenAbout;
  final WebDavSettingsController? webDavSettingsController;
  final bool enableNativeWindowControls;
  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  static const Duration _favoriteSnackBarDuration = Duration(seconds: 3);

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _assistantPane = GlobalKey<DesktopAssistantPaneState>();
  final _coverLayerKey = GlobalKey();
  final _detailHeroKey = GlobalKey();
  CoverOrigin? _coverOrigin;
  ({GameInfo game, Rect begin, Rect end, int generation, Size viewport})?
  _coverFlight;
  int _coverGeneration = 0;
  final Set<String> _favoriteSaving = {};
  final _activityLink = LayerLink();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchTapRegionGroup = Object();
  final _scroll = ScrollController();
  Timer? _favoriteSnackBarTimer;
  bool _searchOpen = false;
  String _page = 'home';
  String _gameDetailReturnPage = 'games';
  String? _libraryGameSlug;
  DesktopLibraryResourceType? _libraryFilter;
  static const _routes = [
    'home',
    'games',
    'assistant',
    'favorites',
    'settings',
  ];
  bool get _native =>
      widget.enableNativeWindowControls &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows;
  bool get _featurePage => ['assistant', 'library'].contains(_page);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _search.addListener(_refreshSearch);
    _searchFocus.addListener(_handleSearchFocusChanged);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _search.removeListener(_refreshSearch);
    _searchFocus.removeListener(_handleSearchFocusChanged);
    _favoriteSnackBarTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _navigate(String page) {
    _coverGeneration++;
    _coverFlight = null;
    _dismissSearch(clearQuery: true);
    if (page == 'assistant' && widget.controller.selectedConversation == null) {
      widget.controller.openGlobalAssistant();
    }
    setState(() {
      _page = page;
      if (page == 'library') {
        _libraryGameSlug = null;
        _libraryFilter = null;
      }
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _setLibraryFilter(DesktopLibraryResourceType? filter) {
    if (_libraryFilter == filter) return;
    setState(() => _libraryFilter = filter);
  }

  int get _selectedRouteIndex {
    if (_page == 'gameDetail' || _page == 'library') return 1;
    final index = _routes.indexOf(_page);
    return index < 0 ? 0 : index;
  }

  void _selectRoute(int index, {bool closeDrawer = false}) {
    if (closeDrawer) Navigator.maybePop(context);
    _navigate(_routes[index]);
  }

  void _game(GameInfo game) {
    final source = _coverOrigin;
    _coverOrigin = null;
    _coverFlight = null;
    final generation = ++_coverGeneration;
    _dismissSearch(clearQuery: true);
    unawaited(widget.controller.recordRecentlyViewed(game));
    widget.controller.selectGame(game.id);
    final origin = _page == 'gameDetail' ? _gameDetailReturnPage : _page;
    setState(() {
      _gameDetailReturnPage = origin == 'gameDetail' ? 'games' : origin;
      _page = 'gameDetail';
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (source?.matches(game.coverAssetPath) == true &&
        !AppMotion.reduced(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _page != 'gameDetail' ||
            generation != _coverGeneration) {
          return;
        }
        final target = _detailHeroKey.currentContext?.findRenderObject();
        final layer = _coverLayerKey.currentContext?.findRenderObject();
        if (target is! RenderBox ||
            layer is! RenderBox ||
            !target.hasSize ||
            !layer.hasSize) {
          return;
        }
        final origin = layer.localToGlobal(Offset.zero);
        setState(
          () => _coverFlight = (
            game: game,
            begin: source!.rect.shift(-origin),
            end: (target.localToGlobal(Offset.zero) & target.size).shift(
              -origin,
            ),
            generation: generation,
            viewport: layer.size,
          ),
        );
      });
    }
  }

  void _openNationalDay() {
    _dismissSearch(clearQuery: true);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => DesktopNationalDayPage(
          controller: widget.controller,
          enableNativeWindowControls: _native,
          onOpenGame: (game) {
            Navigator.of(pageContext).pop();
            _game(game);
          },
        ),
      ),
    );
  }

  void _openRules(GameInfo game) {
    _dismissSearch(clearQuery: true);
    widget.controller.selectGame(game.id);
    setState(() {
      _page = 'library';
      _libraryGameSlug = game.slug;
      _libraryFilter = null;
    });
  }

  void _askAi(GameInfo game) {
    _dismissSearch(clearQuery: true);
    if (!widget.controller.openGameAssistant(game.id)) return;
    setState(() => _page = 'assistant');
  }

  void _dismissFavoriteSnackBar() {
    _favoriteSnackBarTimer?.cancel();
    _favoriteSnackBarTimer = null;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  void _showFavoriteSnackBar({
    required String message,
    SnackBarAction? action,
  }) {
    _favoriteSnackBarTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: _favoriteSnackBarDuration,
        action: action,
      ),
    );
    final timer = Timer(_favoriteSnackBarDuration, controller.close);
    _favoriteSnackBarTimer = timer;
    unawaited(
      controller.closed.whenComplete(() {
        if (identical(_favoriteSnackBarTimer, timer)) {
          _favoriteSnackBarTimer = null;
        }
      }),
    );
  }

  Future<void> _toggleFavorite(GameInfo game) async {
    if (_favoriteSaving.contains(game.id)) return;
    setState(() => _favoriteSaving.add(game.id));
    _dismissFavoriteSnackBar();
    var saved = false;
    try {
      saved = await widget.controller.toggleFavorite(game);
    } finally {
      if (mounted) setState(() => _favoriteSaving.remove(game.id));
    }
    if (!mounted) return;

    final copy = widget.controller.copy;
    if (!saved) {
      _showFavoriteSnackBar(message: copy.favoriteSaveFailed);
      return;
    }

    final isFavorite = widget.controller.isFavorite(game);
    _showFavoriteSnackBar(
      message: isFavorite ? copy.favoriteAdded : copy.favoriteRemoved,
      action: isFavorite
          ? null
          : SnackBarAction(
              label: copy.favoriteUndo,
              onPressed: () => unawaited(_toggleFavorite(game)),
            ),
    );
  }

  Future<void> _openActivityCenter() async {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(math.max(240, size.width * .36), 332).toDouble();
    final height = math.min(math.max(180, size.height - 100), 520).toDouble();
    var markedRead = false;
    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      barrierLabel: widget.controller.copy.activityTitle,
      transitionDuration: AppMotion.duration(context, AppMotion.menu),
      pageBuilder: (dialogContext, _, _) {
        if (!markedRead) {
          markedRead = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(widget.controller.markActivitiesRead());
          });
        }
        return Stack(
          children: [
            CompositedTransformFollower(
              link: _activityLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 8),
              child: UnconstrainedBox(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: width,
                  child: DesktopActivityPopup(
                    controller: widget.controller,
                    maxHeight: height,
                    onClose: () => Navigator.of(dialogContext).pop(),
                    onActivityTap: (activity) => _handleActivityTap(
                      activity,
                      closePanel: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleActivityTap(AppActivity activity, {VoidCallback? closePanel}) {
    closePanel?.call();
    unawaited(widget.controller.markActivityRead(activity.id));
    activity = widget.controller.resolveActivityTarget(activity);
    if (activity.kind == AppActivityKind.libraryLoadFailed) {
      _navigate('library');
      return;
    }
    final conversationId = activity.conversationId;
    if (conversationId == null ||
        !widget.controller.conversations.any(
          (AiConversation item) => item.id == conversationId,
        )) {
      if (activity.kind == AppActivityKind.aiCompleted ||
          activity.kind == AppActivityKind.aiFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.controller.copy.activityConversationUnavailable,
            ),
          ),
        );
      }
      return;
    }
    widget.controller.selectConversation(conversationId);
    setState(() => _page = 'assistant');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _assistantPane.currentState?.revealMessage(activity.messageId);
    });
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  void _handleSearchFocusChanged() {
    if (_searchFocus.hasFocus && !_searchOpen && mounted) {
      setState(() => _searchOpen = true);
    }
  }

  void _openSearch() {
    if (!_searchOpen) setState(() => _searchOpen = true);
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _search.clear();
    if (_searchOpen) setState(() => _searchOpen = false);
  }

  void _dismissSearch({bool clearQuery = false}) {
    _searchFocus.unfocus();
    if (clearQuery) _search.clear();
    _searchOpen = false;
  }

  void _clearSearch() {
    _search.clear();
    _searchFocus.requestFocus();
    _openSearch();
  }

  void _setSearchQuery(String value) {
    _search.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _searchFocus.requestFocus();
    _openSearch();
  }

  void _recordSearch(String value) {
    unawaited(widget.controller.recordSearch(value));
  }

  void _clearSearchHistory() {
    unawaited(widget.controller.clearSearchHistory());
  }

  void _removeSearchHistoryEntry(String value) {
    unawaited(widget.controller.removeSearch(value));
  }

  void _find() {
    if (_page == 'gameDetail') setState(() => _page = 'home');
    _openSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _submitSearch(String value) {
    _recordSearch(value);
    _openSearch();
  }

  void _openSearchGame(GameInfo game, String query) {
    _recordSearch(query);
    _game(game);
  }

  void _openSearchRules(GameInfo game) {
    _recordSearch(_search.text);
    _openRules(game);
  }

  void _openSearchAi(GameInfo game) {
    _recordSearch(_search.text);
    _askAi(game);
  }

  void _openAllSearchResults() {
    _recordSearch(_search.text);
    _navigate('games');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final compact = !narrow && constraints.maxWidth < 1200;
        final metrics = DesktopResponsive.metricsFor(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final sidebarWidth = narrow
            ? 0.0
            : (compact
                  ? DesktopResponsive.compactSidebarWidth
                  : DesktopResponsive.fullSidebarWidth);
        // The Windows shell uses the full available window width. DesktopMetrics
        // still scale visual dimensions, but no longer cap the dashboard canvas
        // at 1280 * scale, which previously created internal dead space.
        final canvasWidth = constraints.maxWidth;
        final dragLeft = narrow ? 0.0 : metrics.px(sidebarWidth);
        final canvas = SizedBox(
          width: canvasWidth,
          height: constraints.maxHeight,
          child: Row(
            children: [
              if (!narrow)
                DesktopSidebar(
                  copy: widget.controller.copy,
                  compact: compact,
                  selectedIndex: _selectedRouteIndex,
                  onSelect: _selectRoute,
                ),
              Expanded(
                child: _workspaceBody(compact: compact, narrow: narrow),
              ),
            ],
          ),
        );
        Widget body = narrow
            ? canvas
            : Align(alignment: Alignment.topCenter, child: canvas);
        if (_native) {
          body = DragToResizeArea(
            resizeEdgeSize: 6,
            child: Stack(
              children: [
                Positioned(
                  left: dragLeft,
                  right: metrics.px(150),
                  top: 0,
                  height: metrics.px(45),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => windowManager.startDragging(),
                    onDoubleTap: () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                  ),
                ),
                body,
                const Positioned(top: 0, right: 0, child: WindowControls()),
              ],
            ),
          );
        }
        return DesktopMetricsScope(
          metrics: metrics,
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: DesktopColors.background,
            drawer: narrow
                ? Drawer(
                    width: 280,
                    shape: const RoundedRectangleBorder(),
                    child: SafeArea(
                      child: DesktopSidebar(
                        copy: widget.controller.copy,
                        width: 280,
                        selectedIndex: _selectedRouteIndex,
                        onSelect: (index) =>
                            _selectRoute(index, closeDrawer: true),
                      ),
                    ),
                  )
                : null,
            body: GameCoverMotionScope(
              onCapture: (origin) => _coverOrigin = origin,
              child: body,
            ),
          ),
        );
      },
    );
  }

  Widget _workspaceBody({required bool compact, required bool narrow}) => Focus(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          _searchOpen) {
        _closeSearch();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_page != 'gameDetail') _topBar(compact: compact, narrow: narrow),
        Expanded(
          child: AppPageTransition(
            key: const ValueKey('desktop-page-transition'),
            identity: (
              _page,
              _page == 'gameDetail' ? widget.controller.selectedGame.id : null,
            ),
            child: Stack(
              key: _coverLayerKey,
              fit: StackFit.expand,
              children: [
                if (_featurePage)
                  Positioned.fill(
                    child: switch (_page) {
                      'assistant' => DesktopAssistantPane(
                        key: _assistantPane,
                        controller: widget.controller,
                      ),
                      'library' => DesktopLibraryPane(
                        key: ValueKey(_libraryGameSlug ?? 'all-library-files'),
                        controller: widget.controller,
                        filter: _libraryFilter,
                        gameSlug: _libraryGameSlug,
                        onFilterChanged: _setLibraryFilter,
                        onShowAllResources: () => _navigate('library'),
                      ),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                if (!_featurePage)
                  Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: Column(
                        children: [
                          DesktopResponsiveFrame(
                            maxWidth: DesktopResponsive.maxContentWidthFor(
                              _page,
                            ),
                            fluid: DesktopResponsive.usesFluidPageWidth(_page),
                            padding: _page == 'gameDetail'
                                ? EdgeInsets.zero
                                : EdgeInsets.fromLTRB(
                                    narrow ? 10 : (_page == 'games' ? 20 : 15),
                                    0,
                                    narrow ? 10 : (_page == 'games' ? 55 : 12),
                                    14,
                                  ),
                            child: switch (_page) {
                              'home' => DesktopHomePane(
                                controller: widget.controller,
                                onNavigate: _navigate,
                                onOpenGame: _game,
                                onOpenNationalDay: _openNationalDay,
                              ),
                              'games' => DesktopGamesPane(
                                controller: widget.controller,
                                showPreview: !narrow,
                                onNavigate: _navigate,
                                onOpenGame: _game,
                                onToggleFavorite: _toggleFavorite,
                              ),
                              'favorites' => DesktopFavoritesPane(
                                controller: widget.controller,
                                showPreview: !narrow,
                                onNavigate: _navigate,
                                onOpenGame: _game,
                                onToggleFavorite: _toggleFavorite,
                              ),
                              'gameDetail' => DesktopGameDetailPane(
                                coverKey: _detailHeroKey,
                                favoriteSaving: _favoriteSaving.contains(
                                  widget.controller.selectedGame.id,
                                ),
                                controller: widget.controller,
                                game: widget.controller.selectedGame,
                                backTooltip: switch (_gameDetailReturnPage) {
                                  'home' => widget.controller.copy.localized(
                                    '返回首页',
                                    'Back to Home',
                                  ),
                                  'favorites' =>
                                    widget.controller.copy.localized(
                                      '返回我的喜欢',
                                      'Back to My Likes',
                                    ),
                                  _ => widget.controller.copy.localized(
                                    '返回游戏库',
                                    'Back to Game Library',
                                  ),
                                },
                                onBack: () => _navigate(_gameDetailReturnPage),
                                onSearch: _find,
                                onOpenRules: () =>
                                    _openRules(widget.controller.selectedGame),
                                onAskAi: () =>
                                    _askAi(widget.controller.selectedGame),
                                onToggleFavorite: _toggleFavorite,
                                onOpenGame: _game,
                              ),
                              'settings' => DesktopSettingsPane(
                                controller: widget.controller,
                                webDavSettingsController:
                                    widget.webDavSettingsController,
                                onOpenAbout: widget.onOpenAbout,
                              ),
                              _ => SizedBox(
                                height: 500,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.controller.copy.localized(
                                          '找不到这个页面',
                                          'Page not found',
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: () => _navigate('home'),
                                        child: Text(
                                          widget.controller.copy.localized(
                                            '返回首页',
                                            'Back to home',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                if (narrow && _page == 'gameDetail')
                  Positioned(
                    right: 12,
                    top: 12,
                    child: IconButton(
                      key: const ValueKey<String>('desktop-open-navigation'),
                      tooltip: widget.controller.copy.localized(
                        '打开导航',
                        'Open navigation',
                      ),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xCC5A4B42),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  ),
                if (_coverFlight case final flight?)
                  if (_page == 'gameDetail' &&
                      flight.game.id == widget.controller.selectedGame.id)
                    Positioned.fill(
                      child: ClipRect(
                        child: GameCoverFlight(
                          key: ValueKey('cover-flight-${flight.generation}'),
                          begin: flight.begin,
                          end: flight.end,
                          viewport: flight.viewport,
                          child: DesktopResolvedImage(
                            controller: widget.controller,
                            assetPath: flight.game.coverAssetPath,
                            palette: widget.controller.palette,
                          ),
                          onEnd: () =>
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted &&
                                    _coverFlight?.generation ==
                                        flight.generation) {
                                  setState(() => _coverFlight = null);
                                }
                              }),
                        ),
                      ),
                    ),
                if (_searchOpen)
                  Positioned(
                    left: DesktopMetricsScope.of(context).px(18),
                    right: DesktopMetricsScope.of(context).px(18),
                    top: 0,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: DesktopMetricsScope.of(context).px(780),
                        ),
                        child: DesktopHomeSearchOverlay(
                          key: const ValueKey<String>(
                            'desktop-home-search-overlay',
                          ),
                          query: _search.text,
                          games: widget.controller.games,
                          controller: widget.controller,
                          recentQueries: widget.controller.searchHistory
                              .map((record) => record.query)
                              .toList(growable: false),
                          tapRegionGroup: _searchTapRegionGroup,
                          onSelectQuery: _setSearchQuery,
                          onClearHistory: _clearSearchHistory,
                          onRemoveQuery: _removeSearchHistoryEntry,
                          onTapOutside: _closeSearch,
                          onOpenGame: _openSearchGame,
                          onOpenRules: _openSearchRules,
                          onAskAi: _openSearchAi,
                          onViewAll: _openAllSearchResults,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _topBar({required bool compact, required bool narrow}) {
    final assistant = _page == 'assistant';
    final metrics = DesktopMetricsScope.of(context);
    return SizedBox(
      key: const ValueKey<String>('desktop-top-bar'),
      height: metrics.px(assistant ? 72 : 104),
      child: Padding(
        padding: metrics.insets(
          EdgeInsets.fromLTRB(20, assistant ? 26 : 30, 18, assistant ? 6 : 12),
        ),
        child: Row(
          children: [
            if (narrow) ...[
              IconButton(
                key: const ValueKey<String>('desktop-open-navigation'),
                tooltip: widget.controller.copy.localized(
                  '打开导航',
                  'Open navigation',
                ),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(
                  Icons.menu_rounded,
                  color: DesktopColors.brown,
                ),
              ),
              SizedBox(width: metrics.px(6)),
            ],
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: metrics.px(assistant ? 460 : 780),
                  ),
                  child: SizedBox(
                    key: const ValueKey<String>('desktop-home-search-shell'),
                    width: double.infinity,
                    height: metrics.px(assistant ? 40 : 55),
                    child: AnimatedContainer(
                      duration: AppMotion.duration(context, AppMotion.feedback),
                      decoration: BoxDecoration(
                        color: _searchFocus.hasFocus
                            ? DesktopColors.card
                            : const Color(0xFFF8F2EA),
                        borderRadius: BorderRadius.circular(metrics.radius(26)),
                        border: Border.all(
                          color: _searchFocus.hasFocus
                              ? DesktopColors.orange
                              : Colors.transparent,
                        ),
                        boxShadow: _searchFocus.hasFocus
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x14FF6846),
                                  blurRadius: metrics.px(12),
                                  offset: Offset(0, metrics.px(2)),
                                ),
                              ]
                            : null,
                      ),
                      child: TapRegion(
                        groupId: _searchTapRegionGroup,
                        child: TextField(
                          key: const ValueKey<String>(
                            'desktop-home-search-field',
                          ),
                          controller: _search,
                          focusNode: _searchFocus,
                          onTap: _openSearch,
                          onSubmitted: _submitSearch,
                          style: TextStyle(
                            fontSize: metrics.font(assistant ? 14 : 19),
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF2F2924),
                          ),
                          decoration: InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            isDense: true,
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: DesktopColors.brown,
                              size: metrics.px(assistant ? 20 : 25),
                            ),
                            suffixIcon: _searchOpen
                                ? IconButton(
                                    tooltip: _search.text.isEmpty
                                        ? widget.controller.copy.localized(
                                            '关闭搜索',
                                            'Close search',
                                          )
                                        : widget.controller.copy.localized(
                                            '清空搜索',
                                            'Clear search',
                                          ),
                                    onPressed: _search.text.isEmpty
                                        ? _closeSearch
                                        : _clearSearch,
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: metrics.px(20),
                                      color: DesktopColors.secondaryText,
                                    ),
                                  )
                                : null,
                            hintText: widget.controller.copy.localized(
                              '搜索桌游 / 机制 / 作者 / 玩法',
                              'Search games / mechanics / designers / rules',
                            ),
                            hintStyle: TextStyle(
                              color: Color(0xFFA89C90),
                              fontSize: metrics.font(assistant ? 14 : 19),
                              fontWeight: FontWeight.w400,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: metrics.px(assistant ? 9 : 14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            CompositedTransformTarget(
              link: _activityLink,
              child: Badge(
                isLabelVisible: widget.controller.unreadActivityCount > 0,
                child: IconButton(
                  tooltip: widget.controller.copy.localized(
                    '通知',
                    'Notifications',
                  ),
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: DesktopColors.brown,
                  ),
                  onPressed: _openActivityCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
