import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../../../app/state/app_controller.dart';
import '../../../app/state/browse_session.dart';
import '../../../core/theme/app_palette.dart';
import '../../../features/games/models/game_info.dart';
import '../../../features/settings/services/settings_transfer_service.dart';
import '../../mobile/game_detail_screen.dart';
import '../../mobile/library_content.dart';
import '../../mobile/settings_screen.dart';
import '../../mobile/national_day_screen.dart';
import '../../mobile/universal_ai_screen.dart';
import '../../mobile/rule_materials_screen.dart';
import '../account_screen.dart';
import '../game_ranking_screen.dart';
import '../library_update_review.dart';
import '../app_modals.dart';
import '../app_failure_notice.dart';
import '../../desktop/business_panes.dart';
import '../../desktop/games_pane.dart';
import '../../desktop/game_detail_pane.dart';
import '../../desktop/settings_pane.dart';
import '../../desktop/national_day_page.dart';
import '../../desktop/desktop_responsive.dart';
import 'spatial_material.dart';
import 'spatial_primitives.dart';
import 'spatial_banner.dart';
import 'spatial_recommendations.dart';

part 'spatial_business_pages.dart';

/// Fourth theme: a separate presentation shell, never DesktopWorkspace repaint.
/// Business pages select desktop or touch compositions inside the same shell.
class SpatialWorkspace extends StatefulWidget {
  const SpatialWorkspace({
    super.key,
    required this.controller,
    required this.onOpenAbout,
    this.transferService,
  });
  final AppController controller;
  final VoidCallback onOpenAbout;
  final SettingsTransferService? transferService;
  @override
  State<SpatialWorkspace> createState() => _SpatialWorkspaceState();
}

class _SpatialWorkspaceState extends State<SpatialWorkspace> {
  final _navigator = GlobalKey<NavigatorState>();
  final _search = TextEditingController();
  String _menu = 'home';
  String? _page, _sample;
  GameInfo? _detail;
  final _pageScrolls = <String, ScrollController>{};
  final _collectionBrowse = <String, LibraryBrowseState>{};
  final _favoriteSaving = <String>{};
  final _favoritePreview = <String, bool>{};
  bool _restoringSearch = false;
  bool? _compactLayout;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_refresh);
    _search.addListener(_searchChanged);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _searchChanged() {
    if (_restoringSearch) return;
    if (_page == 'games' && c.browseSession.library.query != _search.text) {
      c.browseSession.library
        ..query = _search.text
        ..resetPosition();
    }
    _refresh();
  }

  void _restoreLibrarySearch() {
    final query = c.browseSession.library.query;
    if (_search.text == query) return;
    _restoringSearch = true;
    _search.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _restoringSearch = false;
  }

  @override
  void didUpdateWidget(covariant SpatialWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_refresh);
      c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    c.removeListener(_refresh);
    _search.dispose();
    for (final scroll in _pageScrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _select(String menu) {
    setState(() {
      _menu = menu;
      _detail = null;
      _page = menu == 'home' ? null : menu;
      if (menu == 'games') _restoreLibrarySearch();
    });
    if (menu == 'games') unawaited(c.checkForLibraryUpdatesQuick());
    if (menu == 'assistant') c.openGlobalAssistant();
  }

  void _openGame(GameInfo game) {
    c.selectGame(game.id);
    unawaited(c.recordRecentlyViewed(game));
    setState(() => _detail = game);
  }

  void _back() {
    setState(() {
      if (_detail != null) {
        _detail = null;
      } else {
        _page = null;
        _menu = 'home';
      }
    });
  }

  void _askSpatialAi(GameInfo game) {
    if (!c.openGameAssistant(game.id)) return;
    setState(() {
      _detail = null;
      _page = _menu = 'assistant';
    });
  }

  void _openDesktopRules(GameInfo game) => _navigator.currentState?.push<void>(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(game.title)),
        body: DesktopLibraryPane(controller: c, gameSlug: game.slug),
      ),
    ),
  );

  Future<void> _toggleSpatialFavorite(GameInfo game) async {
    if (_favoriteSaving.contains(game.id)) return;
    setState(() {
      _favoriteSaving.add(game.id);
      _favoritePreview[game.id] = !c.isFavorite(game);
    });
    var saved = false;
    try {
      saved = await c.toggleFavorite(game);
    } catch (_) {
      saved = false;
    } finally {
      if (mounted) {
        setState(() {
          _favoriteSaving.remove(game.id);
          _favoritePreview.remove(game.id);
        });
        if (!saved) showAppFailureNotice(context, c.copy.favoriteSaveFailed);
      }
    }
  }

  void _activities() => showLibraryUpdateReview(
    _navigator.currentState?.overlay?.context ?? context,
    c,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('spatial-workspace'),
    backgroundColor: Colors.transparent,
    body: LayoutBuilder(
      builder: (context, box) {
        final mobile = box.maxWidth < 760,
            tablet = box.maxWidth >= 760 && box.maxWidth < 1020;
        if (_compactLayout != mobile) {
          _compactLayout = mobile;
          if (_page == 'games') _restoreLibrarySearch();
        }
        final width = mobile
            ? box.maxWidth * .95
            : tablet
            ? box.maxWidth * .94
            : math.min(1160.0, box.maxWidth - 32);
        final height = mobile
            ? box.maxHeight * .94
            : math.min(tablet ? 720.0 : 710.0, box.maxHeight - 64);
        final nativeDesktop =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
        final panel = SpatialGlass(
          key: const ValueKey('spatial-glass-window'),
          embedded: nativeDesktop,
          child: Row(
            children: [
              if (!mobile) _sidebar(tablet),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, contentBox) => DesktopMetricsScope(
                    metrics: DesktopResponsive.metricsFor(contentBox.biggest),
                    child: Navigator(
                      key: _navigator,
                      onGenerateRoute: (settings) {
                        if (settings.name == '/settings/ai') {
                          return MaterialPageRoute<void>(
                            settings: settings,
                            builder: (context) => LayoutBuilder(
                              builder: (_, box) => _settingsPage(
                                wide: MediaQuery.sizeOf(context).width >= 760,
                                focusAi: true,
                              ),
                            ),
                          );
                        }
                        if (settings.name == GameRankingScreen.routeName) {
                          return MaterialPageRoute<void>(
                            settings: settings,
                            builder: (_) => GameRankingScreen(
                              controller: c,
                              onOpenGame: _openGame,
                            ),
                          );
                        }
                        return null;
                      },
                      pages: [
                        MaterialPage<void>(
                          key: const ValueKey('spatial-home-route'),
                          child: _home(mobile: mobile, tablet: tablet),
                        ),
                        if (_page != null)
                          MaterialPage<void>(
                            key: ValueKey('spatial-$_page-route'),
                            child: _businessPage(wide: !mobile),
                          ),
                        if (_detail != null)
                          MaterialPage<void>(
                            key: ValueKey('spatial-detail-${_detail!.id}'),
                            child: _detailPage(wide: !mobile),
                          ),
                      ],
                      onDidRemovePage: (page) {
                        if (!mounted) return;
                        if (_detail != null &&
                            page.key ==
                                ValueKey('spatial-detail-${_detail!.id}')) {
                          setState(() => _detail = null);
                        } else if (_page != null &&
                            page.key == ValueKey('spatial-$_page-route')) {
                          setState(() {
                            _page = null;
                            _menu = 'home';
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        if (nativeDesktop) {
          return SizedBox.expand(
            key: const ValueKey('spatial-native-panel'),
            child: panel,
          );
        }
        return Stack(
          children: [
            const Positioned.fill(child: SpatialScene()),
            Positioned(
              top: 20,
              right: mobile ? 20 : 45,
              child: const SpatialCapsule(),
            ),
            Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: mobile ? 12 : 28),
                child: SizedBox(
                  width: width,
                  height: math.max(200, height),
                  child: panel,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _sidebar(bool tablet, {VoidCallback? dismiss}) => Container(
    key: const ValueKey('spatial-sidebar'),
    width: tablet ? 180 : 220,
    padding: const EdgeInsets.fromLTRB(20, 26, 14, 24),
    decoration: BoxDecoration(
      border: Border(
        right: BorderSide(color: Colors.white.withValues(alpha: .08)),
      ),
      gradient: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
          ? null
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: .02), Colors.transparent],
            ),
    ),
    child: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Text(
            '桌游伙伴',
            style: TextStyle(
              color: Color(0xFFE50914),
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 15, color: Colors.white54),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const ValueKey('spatial-search'),
                  controller: _search,
                  onSubmitted: (query) {
                    c.browseSession.library
                      ..query = query
                      ..resetPosition();
                    _select('games');
                  },
                  style: const TextStyle(fontSize: 11.5, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: '搜索桌游',
                    hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (_search.text.isNotEmpty)
                InkWell(
                  onTap: _search.clear,
                  child: const Icon(
                    Icons.clear_rounded,
                    size: 14,
                    color: Colors.white60,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.only(left: 10, bottom: 4),
          child: Text(
            'HOME',
            style: TextStyle(
              fontSize: 8.5,
              letterSpacing: 1.2,
              color: Colors.white38,
            ),
          ),
        ),
        for (final item in const [
          ('home', '首页', Icons.home_rounded),
          ('games', '桌游库', Icons.grid_view_rounded),
          ('rankings', '排行榜', Icons.local_fire_department_rounded),
          ('favorites', '我的喜欢', Icons.add_rounded),
          ('assistant', 'AI 助手', Icons.auto_awesome_rounded),
          ('topic', '桌游专题', Icons.movie_outlined),
        ])
          _menuItem(item, dismiss: dismiss),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.only(left: 10, bottom: 12),
          child: Text(
            'MY COLLECTION',
            style: TextStyle(
              fontSize: 8.5,
              letterSpacing: 1.2,
              color: Colors.white38,
            ),
          ),
        ),
        for (final item in const [
          ('recent', '最近浏览', Icons.history_rounded),
          ('downloads', '资料下载', Icons.download_rounded),
          ('account', '账户', Icons.person_outline_rounded),
          ('settings', '设置', Icons.tune_rounded),
        ])
          _menuItem(item, dismiss: dismiss),
      ],
    ),
  );
  Widget _menuItem((String, String, IconData) item, {VoidCallback? dismiss}) =>
      SpatialSidebarButton(
        key: ValueKey('spatial-menu-${item.$1}'),
        title: item.$2,
        icon: item.$3,
        isActive: _menu == item.$1,
        onTap: () {
          dismiss?.call();
          _select(item.$1);
        },
      );

  Widget _home({required bool mobile, required bool tablet}) {
    final query = _search.text.trim().toLowerCase();
    final games = (query.isEmpty ? c.personalizedRecommendedGames : c.games)
        .where(
          (game) =>
              query.isEmpty ||
              '${game.title} ${game.subtitle} ${game.categoryLine}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, box) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
          final inset = mobile ? 18.0 : 22.0;
          final header = Row(
            children: [
              if (mobile)
                IconButton(
                  key: const ValueKey('spatial-open-navigation'),
                  tooltip: '导航',
                  onPressed: () => showAppBottomSheet<void>(
                    context: context,
                    builder: (sheetContext) => _sidebar(
                      true,
                      dismiss: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                  icon: const Icon(Icons.menu, size: 20),
                ),
              Expanded(
                child: Text(
                  _sample ?? 'Continue Browsing',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: _activities,
                tooltip: '消息',
                style: mobile
                    ? null
                    : IconButton.styleFrom(
                        minimumSize: const Size(28, 28),
                        maximumSize: const Size(28, 28),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.notifications_none, size: 18),
              ),
              IconButton(
                onPressed: () => _select('account'),
                tooltip: '账户',
                style: mobile
                    ? null
                    : IconButton.styleFrom(
                        minimumSize: const Size(28, 28),
                        maximumSize: const Size(28, 28),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.account_circle, size: 28),
              ),
            ],
          );
          final top = SizedBox(
            height: mobile ? 260 : 288,
            child: Row(
              children: [
                Expanded(
                  flex: mobile ? 1 : 5,
                  child: SpatialBanner(
                    onExplore: () => _select('games'),
                    onTopic: () => _select('topic'),
                    onAssistant: () => _select('assistant'),
                  ),
                ),
                if (!mobile) ...[
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: _movie(false)),
                ],
                if (!mobile && !tablet) ...[
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: _movie(true)),
                ],
              ],
            ),
          );
          final title = Row(
            children: [
              Expanded(
                child: Text(
                  query.isEmpty ? '推荐桌游' : '搜索结果 (${games.length})',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('spatial-more-recommendations'),
                tooltip: query.isEmpty ? '查看推荐桌游' : '查看桌游库',
                onPressed: () =>
                    _select(query.isEmpty ? 'recommendations' : 'games'),
                style: mobile
                    ? null
                    : IconButton.styleFrom(
                        minimumSize: const Size(20, 20),
                        maximumSize: const Size(20, 20),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                constraints: const BoxConstraints.tightFor(
                  width: 20,
                  height: 20,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_right, size: 17),
              ),
            ],
          );
          final shelf = _SpatialShelf(
            controller: c,
            games: games,
            onOpenGame: _openGame,
            count: mobile
                ? 2
                : tablet
                ? 4
                : 6,
          );
          if (largeText || box.maxHeight < 560) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(inset),
              child: Column(
                children: [
                  header,
                  const SizedBox(height: 12),
                  top,
                  const SizedBox(height: 18),
                  title,
                  const SizedBox(height: 10),
                  SizedBox(height: 240, child: shelf),
                ],
              ),
            );
          }
          return Padding(
            padding: EdgeInsets.fromLTRB(inset, 26, inset, mobile ? 24 : 80),
            child: Column(
              children: [
                header,
                const SizedBox(height: 12),
                top,
                const SizedBox(height: 18),
                title,
                const SizedBox(height: 10),
                Expanded(child: shelf),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _movie(bool second) => SpatialPoster(
    key: ValueKey(
      second ? 'spatial-movie-wednesday' : 'spatial-movie-night-agent',
    ),
    title: second ? 'WEDNESDAY' : 'NIGHT AGENT',
    match: second ? '96% Match' : '94% Match',
    genres: second ? 'Mystery  •  Comedy' : 'Thriller  •  Action',
    badge: 'N SERIES',
    imageUrl: second
        ? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500&q=80'
        : 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500&q=80',
    fallbackGradient: second
        ? const [Color(0xFF101A27), Color(0xFF1C3655), Color(0xFF090D14)]
        : const [Color(0xFF382B21), Color(0xFF6B513E), Color(0xFF14171A)],
    onSelect: () => setState(
      () => _sample = second ? 'Wednesday · 电影示例' : 'The Night Agent · 电影示例',
    ),
  );
}

class _SpatialShelf extends StatelessWidget {
  const _SpatialShelf({
    required this.controller,
    required this.games,
    required this.onOpenGame,
    required this.count,
  });
  final AppController controller;
  final List<GameInfo> games;
  final ValueChanged<GameInfo> onOpenGame;
  final int count;
  @override
  Widget build(BuildContext context) => games.isEmpty
      ? const Center(child: Text('没有匹配的桌游'))
      : LayoutBuilder(
          builder: (context, box) {
            final width = (box.maxWidth - (count - 1) * 10) / count;
            final visible = games.take(count).toList();
            return Row(
              key: const ValueKey('spatial-game-shelf'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  SizedBox(
                    width: width,
                    child: Align(
                      alignment: Alignment.topCenter,
                      // Original wide Web card: 141 dp wide, 216 dp high.
                      // Extra native window height must not stretch the poster.
                      child: SizedBox(
                        height: width * 216 / 141,
                        child: SpatialGamePoster(
                          controller: controller,
                          game: visible[i],
                          onOpen: () => onOpenGame(visible[i]),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
}
