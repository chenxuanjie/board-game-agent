import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import '../screens/desktop_workspace_screen.dart';
import 'v4_home.dart';
import 'v4_games.dart';
import 'v4_game_detail.dart';
import 'v4_settings.dart';
import 'v4_sidebar.dart';
import 'v4_theme.dart';
import 'v4_window_controls.dart';

class V4Workspace extends StatefulWidget {
  const V4Workspace({
    super.key,
    required this.controller,
    required this.onOpenAbout,
    this.enableNativeWindowControls = true,
  });
  final AppController controller;
  final VoidCallback onOpenAbout;
  final bool enableNativeWindowControls;
  @override
  State<V4Workspace> createState() => _V4WorkspaceState();
}

class _V4WorkspaceState extends State<V4Workspace> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _legacy = GlobalKey<DesktopWorkspaceScreenState>();
  final _activityLink = LayerLink();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _page = 'home';
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
  bool get _oldPage => ['assistant', 'library', 'advanced'].contains(_page);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _navigate(String page) {
    setState(() => _page = page);
    if (_oldPage) {
      _legacy.currentState?.navigateTo(page == 'advanced' ? 'settings' : page);
    }
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
    widget.controller.selectGame(game.id);
    setState(() => _page = 'gameDetail');
  }

  void _openRules(GameInfo game) {
    setState(() => _page = 'library');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _legacy.currentState?.navigateTo('library');
      _legacy.currentState?.openRulesForGame(game);
    });
  }

  void _askAi(GameInfo game) {
    setState(() => _page = 'assistant');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _legacy.currentState?.openAssistantForGame(game);
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

  void _find() {
    // Keep the established search implementation, filters and document routing.
    _legacy.currentState?.openSearch();
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
              V4Sidebar(
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
          backgroundColor: V4Colors.background,
          drawer: narrow
              ? Drawer(
                  width: 280,
                  shape: const RoundedRectangleBorder(),
                  child: SafeArea(
                    child: V4Sidebar(
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

  Widget _workspaceBody({required bool compact, required bool narrow}) =>
      Column(
        children: [
          if (_page != 'gameDetail') _topBar(compact: compact, narrow: narrow),
          Expanded(
            child: Stack(
              children: [
                Offstage(
                  offstage: !_oldPage,
                  child: DesktopWorkspaceScreen(
                    key: _legacy,
                    controller: widget.controller,
                    onOpenAbout: widget.onOpenAbout,
                    embedded: true,
                    activityLink: _activityLink,
                    onDestinationChanged: (page) => setState(
                      () => _page = page == 'settings' ? 'advanced' : page,
                    ),
                  ),
                ),
                if (!_oldPage)
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
                              'home' => V4HomePane(
                                controller: widget.controller,
                                onNavigate: _navigate,
                                onOpenGame: _game,
                              ),
                              'games' => V4GamesPane(
                                controller: widget.controller,
                                showPreview: !compact && !narrow,
                                onNavigate: _navigate,
                                onOpenGame: _game,
                              ),
                              'gameDetail' => V4GameDetailPane(
                                controller: widget.controller,
                                game: widget.controller.selectedGame,
                                onBack: () => _navigate('games'),
                                onSearch: _find,
                                onOpenRules: () =>
                                    _openRules(widget.controller.selectedGame),
                                onAskAi: () =>
                                    _askAi(widget.controller.selectedGame),
                              ),
                              'settings' => V4SettingsPane(
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
                                          color: V4Colors.secondaryText,
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
                      key: const ValueKey<String>('v4-open-navigation'),
                      tooltip: '打开导航',
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xCC5A4B42),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _topBar({required bool compact, required bool narrow}) => SizedBox(
    height: 78,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
      child: Row(
        children: [
          if (narrow) ...[
            IconButton(
              key: const ValueKey<String>('v4-open-navigation'),
              tooltip: '打开导航',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: V4Colors.brown),
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
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F2EA),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _search,
                      readOnly: true,
                      onTap: _find,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: V4Colors.brown,
                          size: 21,
                        ),
                        hintText: '搜索桌游 / 机制 / 作者 / 玩法',
                        hintStyle: TextStyle(
                          color: Color(0xFF998D83),
                          fontSize: 14,
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 11),
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
                  color: V4Colors.brown,
                ),
                onPressed: () => _legacy.currentState?.openActivities(),
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
                      'assets/v4/avatar.png',
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
                            color: V4Colors.secondaryText,
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
