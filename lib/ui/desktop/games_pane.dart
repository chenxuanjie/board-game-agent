// Body layout adapted directly from the read-only Desktop reference.
import 'package:flutter/material.dart';
import '../shared/content_entrance.dart';
import '../shared/library_viewport.dart';
import '../shared/app_modals.dart';
import '../../core/theme/cinema_theme.dart';
import '../../core/theme/app_palette.dart';
import '../shared/cinema/cinema_home.dart';
import '../../app/state/browse_session.dart';
import '../../core/theme/app_motion.dart';
import '../../features/games/models/game_info.dart';
import '../../app/state/app_controller.dart';
import 'poster_card.dart';
import 'content_primitives.dart';
import 'theme.dart';

class DesktopGamesPane extends StatefulWidget {
  const DesktopGamesPane({
    super.key,
    required this.controller,
    required this.onNavigate,
    required this.onOpenGame,
    required this.onToggleFavorite,
    this.sourceGames,
    this.showPreview = true,
    this.scrollController,
  });
  final AppController controller;
  final ValueChanged<String> onNavigate;
  final ValueChanged<GameInfo> onOpenGame;
  final ValueChanged<GameInfo> onToggleFavorite;
  final List<GameInfo>? sourceGames;
  final bool showPreview;
  final ScrollController? scrollController;
  @override
  State<DesktopGamesPane> createState() => _DesktopGamesPaneState();
}

class _DesktopGamesPaneState extends State<DesktopGamesPane> {
  final _favoriteBrowse = LibraryBrowseState();
  LibraryBrowseState get _browse => widget.sourceGames == null
      ? widget.controller.browseSession.library
      : _favoriteBrowse;
  int get _category => _browse.category;
  set _category(int value) {
    _browse.category = value;
    _browse.resetPosition();
  }

  _DesktopGameSort get _sort => _DesktopGameSort.values.firstWhere(
    (s) => s.name == _browse.sort,
    orElse: () => _DesktopGameSort.catalog,
  );
  set _sort(_DesktopGameSort value) {
    _browse.sort = value.name;
    _browse.resetPosition();
  }

  String? get _playerFilter => _browse.player;
  set _playerFilter(String? value) => _browse.player = value;
  String? get _durationFilter => _browse.duration;
  set _durationFilter(String? value) => _browse.duration = value;
  Set<String> get _typeFilters => _browse.types;
  String? get _weightFilter => _browse.weight;
  set _weightFilter(String? value) => _browse.weight = value;
  double? get _minScore => _browse.minScore;
  set _minScore(double? value) => _browse.minScore = value;
  bool _sortMenuOpen = false;
  bool _filterMenuOpen = false;

  bool get _hasFilter =>
      _playerFilter != null ||
      _durationFilter != null ||
      _typeFilters.isNotEmpty ||
      _weightFilter != null ||
      _minScore != null;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final games = _browse
          .filter(widget.sourceGames ?? widget.controller.games)
          .map((game) => DesktopContentGame(game, widget.controller))
          .toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopContentStatus(controller: widget.controller),
          LibraryViewport(
            state: _browse,
            ids: games.map((g) => g.data.id).toList(),
            controller: widget.scrollController,
            layout: (
              MediaQuery.sizeOf(context),
              isCinema(context),
              MediaQuery.textScalerOf(context).scale(16),
            ),
            builder: (keys) => _LibraryMain(
              itemKeys: keys,
              browse: _browse,
              games: games,
              selectedCategory: _category,
              onSelectGame: (i) => widget.onOpenGame(games[i].data),
              onOpenAssistant: (game) {
                widget.controller.selectGame(game.id);
                widget.onNavigate('assistant');
              },
              onCategory: (i) => setState(() => _category = i),
              sortLabel: _sort.label,
              hasFilter: _hasFilter,
              sortMenuOpen: _sortMenuOpen,
              filterMenuOpen: _filterMenuOpen,
              onSort: _chooseSort,
              onFilter: _chooseFilter,
            ),
          ),
        ],
      );
    },
  );

  Future<void> _chooseSort(BuildContext anchorContext) async {
    if (_sortMenuOpen || _filterMenuOpen) return;
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _sortMenuOpen = true);
    final lifetime = AppMenuLifetime();
    final value = await showMenu<_DesktopGameSort>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 6,
        overlay.size.width - origin.dx - box.size.width,
        0,
      ),
      constraints: BoxConstraints.tightFor(width: 335),
      color: desktopTone(context, Color(0xFFFFFEFC), DesktopToneRole.card),
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      popUpAnimationStyle: AppMotion.menuStyle(context),
      items: [
        PopupMenuItem<_DesktopGameSort>(
          enabled: false,
          height: 48,
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: desktopColors(context).brown,
              ),
              SizedBox(width: 9),
              Text(
                '排序方式',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        for (final item in _DesktopGameSort.values)
          PopupMenuItem<_DesktopGameSort>(
            key: ValueKey<String>('desktop-library-sort-option-${item.name}'),
            value: item,
            height: 72,
            child: _SortMenuRow(
              item: item,
              selected: item == _sort,
              lifetime: lifetime,
            ),
          ),
      ],
    );
    if (!mounted) return;
    setState(() {
      if (value != null) _sort = value;
    });
    await lifetime.closed;
    if (mounted) setState(() => _sortMenuOpen = false);
  }

  Future<void> _chooseFilter(BuildContext anchorContext) async {
    if (_sortMenuOpen || _filterMenuOpen) return;
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _filterMenuOpen = true);
    final lifetime = AppMenuLifetime();
    final result = await showMenu<_DesktopFilterResult>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx + box.size.width - 372,
        origin.dy + box.size.height + 6,
        overlay.size.width - origin.dx - box.size.width,
        0,
      ),
      constraints: BoxConstraints.tightFor(width: 372),
      color: desktopTone(context, Color(0xFFFFFEFC), DesktopToneRole.card),
      elevation: 14,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      popUpAnimationStyle: AppMotion.menuStyle(context),
      items: [
        _FilterPopupEntry(
          lifetime: lifetime,
          player: _playerFilter,
          duration: _durationFilter,
          types: _typeFilters,
          weight: _weightFilter,
          minScore: _minScore,
        ),
      ],
    );
    if (!mounted) return;
    if (result == null) {
      await lifetime.closed;
      if (!mounted) return;
      setState(() => _filterMenuOpen = false);
      return;
    }
    setState(() {
      _playerFilter = result.player;
      _durationFilter = result.duration;
      _typeFilters
        ..clear()
        ..addAll(result.types);
      _weightFilter = result.weight;
      _minScore = result.minScore;
      _browse.resetPosition();
    });
    await lifetime.closed;
    if (mounted) setState(() => _filterMenuOpen = false);
  }
}

enum _DesktopGameSort {
  catalog('综合排序'),
  name('名称'),
  score('评分');

  const _DesktopGameSort(this.label);
  final String label;
}

class _LibraryMain extends StatelessWidget {
  final Map<String, GlobalKey> itemKeys;
  final LibraryBrowseState browse;
  final List<DesktopContentGame> games;
  final int selectedCategory;
  final ValueChanged<int> onSelectGame;
  final ValueChanged<GameInfo> onOpenAssistant;
  final ValueChanged<int> onCategory;
  final String sortLabel;
  final bool hasFilter;
  final bool sortMenuOpen;
  final bool filterMenuOpen;
  final ValueChanged<BuildContext> onSort;
  final ValueChanged<BuildContext> onFilter;

  const _LibraryMain({
    required this.itemKeys,
    required this.browse,
    required this.games,
    required this.selectedCategory,
    required this.onSelectGame,
    required this.onOpenAssistant,
    required this.onCategory,
    required this.sortLabel,
    required this.hasFilter,
    required this.sortMenuOpen,
    required this.filterMenuOpen,
    required this.onSort,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    const categories = ['全部', '策略', '家庭', '聚会', '合作', '双人'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final categoryRow = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < categories.length; i++) ...[
                  _FilterChipButton(
                    key: ValueKey<String>('desktop-library-category-$i'),
                    label: categories[i],
                    selected: selectedCategory == i,
                    onTap: () => onCategory(i),
                  ),
                  if (i != categories.length - 1) SizedBox(width: 8),
                ],
              ],
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (buttonContext) => _OutlineAction(
                    key: ValueKey<String>('desktop-library-sort-action'),
                    label: sortLabel,
                    active: sortMenuOpen || sortLabel != '综合排序',
                    expanded: sortMenuOpen,
                    onTap: () => onSort(buttonContext),
                  ),
                ),
                SizedBox(width: 10),
                Builder(
                  builder: (buttonContext) => _OutlineAction(
                    key: ValueKey<String>('desktop-library-filter-action'),
                    label: '筛选',
                    leadingIcon: Icons.filter_alt_outlined,
                    active: filterMenuOpen || hasFilter,
                    expanded: filterMenuOpen,
                    onTap: () => onFilter(buttonContext),
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: categoryRow,
                  ),
                  SizedBox(height: 9),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }

            return SizedBox(
              height: isCinema(context) ? 40 : 38,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: categoryRow,
                    ),
                  ),
                  SizedBox(width: 12),
                  actions,
                ],
              ),
            );
          },
        ),
        SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final cinema = isCinema(context);
            final gap = cinema ? 16.0 : 20.0;
            final columns = cinema
                ? ((constraints.maxWidth + gap) / (192 + gap)).floor().clamp(
                    1,
                    6,
                  )
                : constraints.maxWidth >= 1130
                ? 5
                : constraints.maxWidth >= 860
                ? 4
                : constraints.maxWidth >= 640
                ? 3
                : 2;
            final fittedWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            final posterWidth =
                (columns == 5 ? fittedWidth.clamp(198.0, 210.0) : fittedWidth)
                    .toDouble();
            return Align(
              alignment: Alignment.topLeft,
              child: Wrap(
                key: ValueKey<String>('desktop-library-posters'),
                spacing: gap,
                runSpacing: 24,
                clipBehavior: Clip.none,
                children: [
                  for (var index = 0; index < games.length; index++)
                    ContentEntrance(
                      key: ValueKey('library-entrance-${games[index].data.id}'),
                      order: index,
                      animate:
                          index < 6 &&
                          browse.revealed.add(games[index].data.id),
                      changeIdentity: (
                        index,
                        games[index].data.title,
                        games[index].data.score,
                        games[index].data.coverAssetPath,
                      ),
                      child: SizedBox(
                        key: itemKeys[games[index].data.id],
                        width: posterWidth,
                        height: cinema
                            ? posterWidth * 4 / 3 +
                                  MediaQuery.textScalerOf(context).scale(16) *
                                      2.6 +
                                  MediaQuery.textScalerOf(context).scale(14) *
                                      1.55 +
                                  MediaQuery.textScalerOf(context).scale(12) *
                                      2.9 +
                                  48
                            : posterWidth * 1.49,
                        child: _LibraryGameCard(
                          game: games[index],
                          onTap: () => onSelectGame(index),
                          onOpenAssistant: () =>
                              onOpenAssistant(games[index].data),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FilterChipButton extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FilterChipButton> createState() => _FilterChipButtonState();
}

TextStyle _libraryToolbarTextStyle({
  required bool active,
  required Color foreground,
}) {
  return TextStyle(
    fontSize: 13,
    height: 1,
    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
    color: foreground,
  );
}

class _FilterChipButtonState extends State<_FilterChipButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.menu),
          curve: AppMotion.curve,
          height: isCinema(context) ? 40 : 38,
          padding: EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      desktopColors(context).orange,
                      desktopColors(context).orange2,
                    ],
                  )
                : null,
            color: selected
                ? null
                : (hover
                      ? desktopTone(
                          context,
                          Color(0xFFFFF2E9),
                          DesktopToneRole.selected,
                        )
                      : desktopColors(context).card),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : desktopTone(
                      context,
                      Color(0x219B5435),
                      DesktopToneRole.line,
                    ),
            ),
          ),
          child: Text(
            widget.label,
            style: _libraryToolbarTextStyle(
              active: selected,
              foreground: selected
                  ? (isCinema(context)
                        ? AppPalette.of(context).onPrimary
                        : Colors.white)
                  : desktopTone(
                      context,
                      Color(0xFF5E493B),
                      DesktopToneRole.text,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineAction extends StatefulWidget {
  final String label;
  final IconData? leadingIcon;
  final bool active;
  final bool expanded;
  final VoidCallback onTap;

  const _OutlineAction({
    super.key,
    required this.label,
    this.leadingIcon,
    required this.active,
    required this.expanded,
    required this.onTap,
  });

  @override
  State<_OutlineAction> createState() => _OutlineActionState();
}

class _OutlineActionState extends State<_OutlineAction> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.active
        ? (isCinema(context) ? AppPalette.of(context).onPrimary : Colors.white)
        : desktopTone(context, Color(0xFF5E493B), DesktopToneRole.text);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.menu),
          curve: AppMotion.curve,
          height: isCinema(context) ? 40 : 38,
          constraints: BoxConstraints(minWidth: 104),
          padding: EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: widget.active
                ? LinearGradient(
                    colors: [
                      desktopColors(context).orange,
                      desktopColors(context).orange2,
                    ],
                  )
                : null,
            color: widget.active
                ? null
                : (hover
                      ? desktopTone(
                          context,
                          Color(0xFFFFF2E9),
                          DesktopToneRole.selected,
                        )
                      : desktopColors(context).card),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.active
                  ? Colors.transparent
                  : (hover
                        ? desktopTone(
                            context,
                            Color(0x55FF6846),
                            DesktopToneRole.primary,
                          )
                        : desktopTone(
                            context,
                            Color(0x219B5435),
                            DesktopToneRole.line,
                          )),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.leadingIcon != null) ...[
                Icon(widget.leadingIcon, size: 16, color: foreground),
                SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: _libraryToolbarTextStyle(
                  active: widget.active,
                  foreground: foreground,
                ),
              ),
              SizedBox(width: 6),
              AnimatedRotation(
                key: ValueKey<String>('desktop-library-action-arrow'),
                turns: widget.expanded ? 0.5 : 0,
                duration: AppMotion.duration(context, AppMotion.menu),
                curve: AppMotion.curve,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortMenuRow extends StatelessWidget {
  const _SortMenuRow({
    required this.item,
    required this.selected,
    required this.lifetime,
  });
  final AppMenuLifetime lifetime;

  final _DesktopGameSort item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    lifetime.capture(context);
    final subtitle = switch (item) {
      _DesktopGameSort.catalog => '按相关性推荐',
      _DesktopGameSort.name => '按游戏名称 A-Z 排序',
      _DesktopGameSort.score => '按玩家评分从高到低',
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? desktopTone(context, Color(0xFFFFF0E8), DesktopToneRole.selected)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected
                ? desktopColors(context).orange
                : desktopTone(
                    context,
                    Color(0xFF8A6E62),
                    DesktopToneRole.secondary,
                  ),
            size: 25,
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? desktopTone(
                            context,
                            Color(0xFFB64B2F),
                            DesktopToneRole.primary,
                          )
                        : desktopTone(
                            context,
                            Color(0xFF493D36),
                            DesktopToneRole.text,
                          ),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: desktopColors(context).secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopFilterResult {
  const _DesktopFilterResult({
    this.player,
    this.duration,
    required this.types,
    this.weight,
    this.minScore,
  });

  final String? player;
  final String? duration;
  final Set<String> types;
  final String? weight;
  final double? minScore;
}

class _FilterPopupEntry extends PopupMenuEntry<_DesktopFilterResult> {
  const _FilterPopupEntry({
    required this.lifetime,
    required this.player,
    required this.duration,
    required this.types,
    required this.weight,
    required this.minScore,
  });
  final AppMenuLifetime lifetime;

  final String? player;
  final String? duration;
  final Set<String> types;
  final String? weight;
  final double? minScore;

  @override
  double get height => 758;

  @override
  bool represents(_DesktopFilterResult? value) => false;

  @override
  State<_FilterPopupEntry> createState() => _FilterPopupEntryState();
}

class _FilterPopupEntryState extends State<_FilterPopupEntry> {
  String? player;
  String? duration;
  late Set<String> types;
  String? weight;
  double? minScore;

  @override
  void initState() {
    super.initState();
    player = widget.player;
    duration = widget.duration;
    types = <String>{...widget.types};
    weight = widget.weight;
    minScore = widget.minScore;
  }

  void _clear() => setState(() {
    player = null;
    duration = null;
    types.clear();
    weight = null;
    minScore = null;
  });

  @override
  Widget build(BuildContext context) {
    widget.lifetime.capture(context);
    const typeOptions = [
      '策略',
      '家庭',
      '聚会',
      '合作',
      '对抗',
      '卡牌',
      '推理',
      '骰子',
      '建造',
      '经济',
      '冒险',
      '主题',
    ];
    return SizedBox(
      width: 372,
      height: 758,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  color: desktopColors(context).orange,
                  size: 22,
                ),
                SizedBox(width: 10),
                Text(
                  '筛选条件',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Spacer(),
                TextButton(
                  onPressed: _clear,
                  child: Text(
                    '清除全部',
                    style: TextStyle(color: desktopColors(context).orange),
                  ),
                ),
              ],
            ),
            Divider(height: 10),
            _FilterGridSection(
              title: '玩家人数',
              columns: 5,
              children: [
                for (final value in ['1', '2', '3', '4', '5+'])
                  _OptionChip(
                    label: value,
                    expand: true,
                    selected: player == value,
                    onTap: () =>
                        setState(() => player = player == value ? null : value),
                  ),
              ],
            ),
            _FilterGridSection(
              title: '游戏时长',
              columns: 3,
              children: [
                for (final option in [
                  ('<30', '< 30 分钟'),
                  ('30-60', '30-60 分钟'),
                  ('60-120', '60-120 分钟'),
                  ('>120', '> 120 分钟'),
                ])
                  _OptionChip(
                    label: option.$2,
                    expand: true,
                    selected: duration == option.$1,
                    onTap: () => setState(
                      () => duration = duration == option.$1 ? null : option.$1,
                    ),
                  ),
              ],
            ),
            _FilterGridSection(
              title: '游戏类型',
              columns: 4,
              children: [
                for (final value in typeOptions)
                  _OptionChip(
                    label: value,
                    expand: true,
                    selected: types.contains(value),
                    onTap: () => setState(() {
                      if (!types.add(value)) types.remove(value);
                    }),
                  ),
              ],
            ),
            _FilterGridSection(
              title: '难度',
              columns: 4,
              children: [
                for (final value in ['入门', '轻度', '中度', '重度'])
                  _OptionChip(
                    label: value,
                    expand: true,
                    selected: weight == value,
                    onTap: () =>
                        setState(() => weight = weight == value ? null : value),
                  ),
              ],
            ),
            _FilterGridSection(
              title: '评分',
              columns: 4,
              children: [
                _OptionChip(
                  label: '不限',
                  expand: true,
                  selected: minScore == null,
                  onTap: () => setState(() => minScore = null),
                ),
                for (final value in [7.0, 8.0, 9.0])
                  _OptionChip(
                    label: '${value.toInt()}+',
                    expand: true,
                    selected: minScore == value,
                    onTap: () => setState(() => minScore = value),
                  ),
              ],
            ),
            Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.fromHeight(46),
                      side: BorderSide(
                        color: desktopTone(
                          context,
                          Color(0xFFFFB39B),
                          DesktopToneRole.outline,
                        ),
                      ),
                      foregroundColor: desktopTone(
                        context,
                        Color(0xFFB64B2F),
                        DesktopToneRole.primary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: Text(
                      '重置',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _DesktopFilterResult(
                        player: player,
                        duration: duration,
                        types: types,
                        weight: weight,
                        minScore: minScore,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: Size.fromHeight(46),
                      backgroundColor: desktopColors(context).orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: Text(
                      '应用筛选',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterGridSection extends StatelessWidget {
  const _FilterGridSection({
    required this.title,
    required this.columns,
    required this.children,
  });

  final String title;
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 7),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 8,
              children: [
                for (final child in children)
                  SizedBox(width: width, child: child),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.expand = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.feedback),
      height: isCinema(context) ? 40 : 38,
      width: expand ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: 15),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? desktopColors(context).orange
            : desktopTone(context, Color(0xFFFFFEFC), DesktopToneRole.card),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? desktopColors(context).orange
              : desktopTone(context, Color(0xFFE9DFD8), DesktopToneRole.line),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isCinema(context) ? 14 : 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected
              ? (isCinema(context)
                    ? AppPalette.of(context).onPrimary
                    : Colors.white)
              : desktopTone(context, Color(0xFF5F554E), DesktopToneRole.text),
        ),
      ),
    ),
  );
}

class _LibraryGameCard extends StatelessWidget {
  final DesktopContentGame game;
  final VoidCallback onTap;
  final VoidCallback onOpenAssistant;

  const _LibraryGameCard({
    required this.game,
    required this.onTap,
    required this.onOpenAssistant,
  });

  @override
  Widget build(BuildContext context) {
    if (isCinema(context)) {
      return CinemaPoster(
        key: ValueKey('desktop-game-card-${game.data.id}'),
        controller: game.controller,
        game: game.data,
        onOpen: onTap,
        details: true,
      );
    }
    return DesktopLibraryPosterCard(
      key: ValueKey<String>('desktop-game-card-${game.data.id}'),
      controller: game.controller,
      game: game.data,
      onTap: onTap,
      onOpenAssistant: onOpenAssistant,
    );
  }
}
