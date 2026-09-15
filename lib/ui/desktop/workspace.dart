import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/ai_conversation.dart';
import '../../models/app_activity.dart';
import '../../models/desktop_library_resource.dart';
import '../../models/game_info.dart';
import '../../models/resolved_document.dart';
import '../../state/app_controller.dart';
import '../screens/markdown_document_screen.dart';
import '../screens/pdf_document_screen.dart';
import 'business_panes.dart';
import 'home_pane.dart';
import 'games_pane.dart';
import 'game_detail_pane.dart';
import 'home_search_overlay.dart';
import 'settings_pane.dart';
import 'sidebar.dart';
import 'theme.dart';
import 'window_controls.dart';

class DesktopWorkspace extends StatefulWidget {
  const DesktopWorkspace({
    super.key,
    required this.controller,
    required this.onOpenAbout,
    this.enableNativeWindowControls = true,
  });
  final AppController controller;
  final VoidCallback onOpenAbout;
  final bool enableNativeWindowControls;
  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _assistantPane = GlobalKey<DesktopAssistantPaneState>();
  final _activityLink = LayerLink();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchTapRegionGroup = Object();
  final _scroll = ScrollController();
  final List<String> _searchHistory = <String>[];
  bool _searchOpen = false;
  String _page = 'home';
  String _gameDetailReturnPage = 'games';
  bool _rulesDrawerOpen = false;
  GameInfo? _rulesDrawerGame;
  DesktopLibraryResource? _rulesDrawerResource;
  int _rulesDrawerTab = 0;
  static const _routes = [
    'home',
    'games',
    'assistant',
    'rankings',
    'favorites',
    'community',
    'settings',
  ];
  bool get _native =>
      widget.enableNativeWindowControls &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows;
  bool get _featurePage => ['assistant', 'library', 'advanced'].contains(_page);

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
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _navigate(String page) {
    _dismissSearch();
    if (page == 'assistant' && widget.controller.selectedConversation == null) {
      widget.controller.openGlobalAssistant();
    }
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  int get _selectedRouteIndex {
    if (_page == 'gameDetail' || _page == 'library') return 1;
    if (_page == 'advanced') return 6;
    final index = _routes.indexOf(_page);
    return index < 0 ? 0 : index;
  }

  void _selectRoute(int index, {bool closeDrawer = false}) {
    if (closeDrawer) Navigator.maybePop(context);
    _navigate(_routes[index]);
  }

  void _game(GameInfo game) {
    _dismissSearch();
    widget.controller.selectGame(game.id);
    final origin = _page == 'gameDetail' ? _gameDetailReturnPage : _page;
    setState(() {
      _gameDetailReturnPage = origin == 'gameDetail' ? 'games' : origin;
      _page = 'gameDetail';
    });
  }

  void _openRules(GameInfo game) {
    _dismissSearch();
    widget.controller.selectGame(game.id);
    setState(() {
      _page = 'library';
      _rulesDrawerGame = game;
      _rulesDrawerResource = null;
      _rulesDrawerTab = 0;
      _rulesDrawerOpen = true;
    });
  }

  void _askAi(GameInfo game) {
    _dismissSearch();
    if (!widget.controller.openGameAssistant(game.id)) return;
    setState(() => _page = 'assistant');
  }

  void _openRulesForResource(DesktopLibraryResource resource) {
    final game = widget.controller.games
        .where((item) => item.slug == resource.gameSlug)
        .firstOrNull;
    if (game != null) widget.controller.selectGame(game.id);
    setState(() {
      _rulesDrawerGame = game;
      _rulesDrawerResource = resource;
      _rulesDrawerTab = 0;
      _rulesDrawerOpen = true;
    });
  }

  void _closeRulesDrawer() => setState(() => _rulesDrawerOpen = false);

  void _openDrawerAssistant() {
    final game = _rulesDrawerGame;
    _closeRulesDrawer();
    if (game != null) {
      _askAi(game);
    } else {
      _navigate('assistant');
    }
  }

  Future<void> _openDrawerResource() async {
    final resource = _rulesDrawerResource;
    if (resource == null || !resource.canOpen) return;
    _closeRulesDrawer();
    final ResolvedDocument? document = await widget.controller
        .resolveLibraryResource(resource);
    if (!mounted || document == null) return;
    final title = '${resource.gameTitle} · ${resource.title}';
    final Widget page;
    if (document.renderType == DocumentRenderType.markdown) {
      page = MarkdownDocumentScreen(
        controller: widget.controller,
        remotePath: document.remotePath,
        title: title,
      );
    } else if (document.renderType == DocumentRenderType.pdf) {
      page = PdfDocumentScreen(
        controller: widget.controller,
        title: title,
        remotePath: document.remotePath,
      );
    } else {
      return;
    }
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
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
      transitionDuration: const Duration(milliseconds: 150),
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

  void _unavailable(String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('未开放'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
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
    if (_searchOpen) setState(() => _searchOpen = false);
  }

  void _dismissSearch() {
    _searchFocus.unfocus();
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
    final query = value.trim();
    if (query.isEmpty) return;
    _searchHistory
      ..remove(query)
      ..insert(0, query);
    if (_searchHistory.length > 5) _searchHistory.removeLast();
    setState(() {});
  }

  void _clearSearchHistory() {
    setState(_searchHistory.clear);
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final compact = !narrow && constraints.maxWidth < 1200;
        final sidebarWidth = narrow ? 0.0 : (compact ? 76.0 : 205.0);
        Widget body = Row(
          children: [
            if (!narrow)
              DesktopSidebar(
                compact: compact,
                selectedIndex: _selectedRouteIndex,
                onSelect: _selectRoute,
              ),
            Expanded(
              child: _workspaceBody(compact: compact, narrow: narrow),
            ),
          ],
        );
        if (_native) {
          body = DragToResizeArea(
            resizeEdgeSize: 6,
            child: Stack(
              children: [
                body,
                Positioned(
                  left: sidebarWidth,
                  right: 96,
                  top: 0,
                  height: 18,
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
                const Positioned(top: 0, right: 0, child: WindowControls()),
              ],
            ),
          );
        }
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: DesktopColors.background,
          drawer: narrow
              ? Drawer(
                  width: 280,
                  shape: const RoundedRectangleBorder(),
                  child: SafeArea(
                    child: DesktopSidebar(
                      width: 280,
                      selectedIndex: _selectedRouteIndex,
                      onSelect: (index) =>
                          _selectRoute(index, closeDrawer: true),
                    ),
                  ),
                )
              : null,
          body: body,
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
          child: Stack(
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
                      controller: widget.controller,
                      onOpenRules: _openRulesForResource,
                    ),
                    'advanced' => DesktopAdvancedSettingsPane(
                      controller: widget.controller,
                      onOpenAbout: widget.onOpenAbout,
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
                        Padding(
                          padding: _page == 'gameDetail'
                              ? EdgeInsets.zero
                              : EdgeInsets.fromLTRB(
                                  narrow ? 10 : 15,
                                  0,
                                  narrow ? 10 : 12,
                                  14,
                                ),
                          child: switch (_page) {
                            'home' => DesktopHomePane(
                              controller: widget.controller,
                              onNavigate: _navigate,
                              onOpenGame: _game,
                            ),
                            'games' => DesktopGamesPane(
                              controller: widget.controller,
                              showPreview: !compact && !narrow,
                              onNavigate: _navigate,
                              onOpenGame: _game,
                            ),
                            'gameDetail' => DesktopGameDetailPane(
                              controller: widget.controller,
                              game: widget.controller.selectedGame,
                              backTooltip: _gameDetailReturnPage == 'home'
                                  ? '返回首页'
                                  : '返回游戏库',
                              onBack: () => _navigate(_gameDetailReturnPage),
                              onSearch: _find,
                              onOpenRules: () =>
                                  _openRules(widget.controller.selectedGame),
                              onAskAi: () =>
                                  _askAi(widget.controller.selectedGame),
                            ),
                            'settings' => DesktopSettingsPane(
                              controller: widget.controller,
                              onOpenExistingSettings: () =>
                                  _navigate('advanced'),
                              onOpenAbout: widget.onOpenAbout,
                            ),
                            _ => SizedBox(
                              height: 500,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      switch (_page) {
                                        'rankings' => '排行榜',
                                        'favorites' => '我的收藏',
                                        'community' => '社区',
                                        _ => _page,
                                      },
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      '未开放',
                                      style: TextStyle(
                                        color: DesktopColors.secondaryText,
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
                    tooltip: '打开导航',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xCC5A4B42),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.menu_rounded),
                  ),
                ),
              if (_searchOpen)
                Positioned(
                  left: 18,
                  right: 18,
                  top: 0,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: DesktopHomeSearchOverlay(
                        key: const ValueKey<String>(
                          'desktop-home-search-overlay',
                        ),
                        query: _search.text,
                        games: widget.controller.games,
                        controller: widget.controller,
                        recentQueries: _searchHistory,
                        tapRegionGroup: _searchTapRegionGroup,
                        onSelectQuery: _setSearchQuery,
                        onClearHistory: _clearSearchHistory,
                        onTapOutside: _closeSearch,
                        onOpenGame: _game,
                        onOpenRules: _openRules,
                        onAskAi: _askAi,
                        onViewAll: () => _navigate('games'),
                      ),
                    ),
                  ),
                ),
              DesktopRulesDrawer(
                open: _rulesDrawerOpen,
                tabIndex: _rulesDrawerTab,
                game: _rulesDrawerGame,
                resource: _rulesDrawerResource,
                controller: widget.controller,
                onClose: _closeRulesDrawer,
                onTabChanged: (value) =>
                    setState(() => _rulesDrawerTab = value),
                onOpenAssistant: _openDrawerAssistant,
                onOpenResource: _openDrawerResource,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _topBar({required bool compact, required bool narrow}) => SizedBox(
    height: 78,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
      child: Row(
        children: [
          if (narrow) ...[
            IconButton(
              key: const ValueKey<String>('desktop-open-navigation'),
              tooltip: '打开导航',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: DesktopColors.brown),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      color: _searchFocus.hasFocus
                          ? DesktopColors.card
                          : const Color(0xFFF8F2EA),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _searchFocus.hasFocus
                            ? DesktopColors.orange
                            : Colors.transparent,
                      ),
                      boxShadow: _searchFocus.hasFocus
                          ? const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x14FF6846),
                                blurRadius: 12,
                                offset: Offset(0, 2),
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
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: DesktopColors.brown,
                            size: 21,
                          ),
                          suffixIcon: _searchOpen
                              ? IconButton(
                                  tooltip: _search.text.isEmpty
                                      ? '关闭搜索'
                                      : '清空搜索',
                                  onPressed: _search.text.isEmpty
                                      ? _closeSearch
                                      : _clearSearch,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: DesktopColors.secondaryText,
                                  ),
                                )
                              : null,
                          hintText: '搜索桌游 / 机制 / 作者 / 玩法',
                          hintStyle: const TextStyle(
                            color: Color(0xFF998D83),
                            fontSize: 14,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 11,
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
                tooltip: '通知',
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: DesktopColors.brown,
                ),
                onPressed: _openActivityCenter,
              ),
            ),
          ),
          if (!narrow) const SizedBox(width: 11),
          if (!narrow)
            InkWell(
              onTap: () => _unavailable('个人中心'),
              borderRadius: BorderRadius.circular(22),
              child: Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/desktop/warmwood/avatar.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (!compact)
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '—',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '未开放',
                          style: TextStyle(
                            fontSize: 11,
                            color: DesktopColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
