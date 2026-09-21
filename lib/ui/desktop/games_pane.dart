// Body layout adapted directly from the read-only Desktop reference.
import 'package:flutter/material.dart';
import '../../models/game_info.dart';
import '../../state/app_controller.dart';
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
  });
  final AppController controller;
  final ValueChanged<String> onNavigate;
  final ValueChanged<GameInfo> onOpenGame;
  final ValueChanged<GameInfo> onToggleFavorite;
  final List<GameInfo>? sourceGames;
  final bool showPreview;
  @override
  State<DesktopGamesPane> createState() => _DesktopGamesPaneState();
}

class _DesktopGamesPaneState extends State<DesktopGamesPane> {
  int _category = 0;
  _DesktopGameSort _sort = _DesktopGameSort.catalog;
  String? _playerFilter;
  String? _durationFilter;
  final Set<String> _typeFilters = <String>{};
  String? _weightFilter;
  double? _minScore;
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
      const categories = ['全部', '策略', '家庭', '聚会', '合作', '双人'];
      final games =
          (widget.sourceGames ?? widget.controller.games)
              .where(
                (g) =>
                    (_category == 0 ||
                        (_category == 5
                            ? g.supportedPlayers.contains(2)
                            : _gameSearchText(
                                g,
                              ).contains(categories[_category]))) &&
                    _matchesPlayer(g) &&
                    _matchesDuration(g) &&
                    _matchesType(g) &&
                    _matchesWeight(g) &&
                    _matchesScore(g),
              )
              .map((g) => DesktopContentGame(g, widget.controller))
              .toList()
            ..sort(_compareGames);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopContentStatus(controller: widget.controller),
          _LibraryMain(
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
        ],
      );
    },
  );

  String _gameSearchText(GameInfo game) =>
      '${game.categoryLine} ${game.keywords.join(' ')} ${game.title}';

  int _compareGames(DesktopContentGame a, DesktopContentGame b) =>
      switch (_sort) {
        _DesktopGameSort.catalog =>
          widget.controller.games
              .indexOf(a.data)
              .compareTo(widget.controller.games.indexOf(b.data)),
        _DesktopGameSort.name => a.title.compareTo(b.title),
        _DesktopGameSort.score => _score(b.data).compareTo(_score(a.data)),
      };

  double _score(GameInfo game) => double.tryParse(game.score) ?? -1;

  bool _matchesPlayer(GameInfo game) {
    final filter = _playerFilter;
    if (filter == null) return true;
    if (filter == '5+') {
      return game.supportedPlayers.any((value) => value >= 5);
    }
    final target = int.tryParse(filter);
    return target == null || game.supportedPlayers.contains(target);
  }

  bool _matchesDuration(GameInfo game) {
    final filter = _durationFilter;
    if (filter == null) return true;
    final values = RegExp(r'\d+')
        .allMatches('${game.playTime} ${game.perPlayerTime}')
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .toList();
    if (values.isEmpty) return false;
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    return switch (filter) {
      '<30' => low < 30,
      '30-60' => high >= 30 && low <= 60,
      '60-120' => high >= 60 && low <= 120,
      '>120' => high > 120,
      _ => true,
    };
  }

  bool _matchesType(GameInfo game) {
    if (_typeFilters.isEmpty) return true;
    final text = _gameSearchText(game);
    return _typeFilters.any(text.contains);
  }

  bool _matchesWeight(GameInfo game) {
    final filter = _weightFilter;
    if (filter == null) return true;
    final value = '${game.complexity} ${game.learningDifficulty}';
    return switch (filter) {
      '入门' => value.contains('入门') || value.contains('简单'),
      '轻度' => value.contains('轻'),
      '重度' => value.contains('重') || value.contains('困难'),
      _ => value.contains('中'),
    };
  }

  bool _matchesScore(GameInfo game) =>
      _minScore == null || _score(game) >= _minScore!;

  Future<void> _chooseSort(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _sortMenuOpen = true);
    final value = await showMenu<_DesktopGameSort>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 6,
        overlay.size.width - origin.dx - box.size.width,
        0,
      ),
      constraints: const BoxConstraints.tightFor(width: 335),
      color: const Color(0xFFFFFEFC),
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 180),
        reverseDuration: Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      items: [
        const PopupMenuItem<_DesktopGameSort>(
          enabled: false,
          height: 48,
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: DesktopColors.brown),
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
            child: _SortMenuRow(item: item, selected: item == _sort),
          ),
      ],
    );
    if (!mounted) return;
    setState(() {
      _sortMenuOpen = false;
      if (value != null) _sort = value;
    });
  }

  Future<void> _chooseFilter(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _filterMenuOpen = true);
    final result = await showMenu<_DesktopFilterResult>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx + box.size.width - 372,
        origin.dy + box.size.height + 6,
        overlay.size.width - origin.dx - box.size.width,
        0,
      ),
      constraints: const BoxConstraints.tightFor(width: 372),
      color: const Color(0xFFFFFEFC),
      elevation: 14,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 180),
        reverseDuration: Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      items: [
        _FilterPopupEntry(
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
      setState(() => _filterMenuOpen = false);
      return;
    }
    setState(() {
      _filterMenuOpen = false;
      _playerFilter = result.player;
      _durationFilter = result.duration;
      _typeFilters
        ..clear()
        ..addAll(result.types);
      _weightFilter = result.weight;
      _minScore = result.minScore;
    });
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
                  if (i != categories.length - 1) const SizedBox(width: 8),
                ],
              ],
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (buttonContext) => _OutlineAction(
                    key: const ValueKey<String>('desktop-library-sort-action'),
                    label: sortLabel,
                    active: sortMenuOpen || sortLabel != '综合排序',
                    expanded: sortMenuOpen,
                    onTap: () => onSort(buttonContext),
                  ),
                ),
                const SizedBox(width: 10),
                Builder(
                  builder: (buttonContext) => _OutlineAction(
                    key: const ValueKey<String>(
                      'desktop-library-filter-action',
                    ),
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
                  const SizedBox(height: 9),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }

            return SizedBox(
              height: 38,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: categoryRow,
                    ),
                  ),
                  const SizedBox(width: 12),
                  actions,
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 20.0;
            final columns = constraints.maxWidth >= 1130
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
                key: const ValueKey<String>('desktop-library-posters'),
                spacing: gap,
                runSpacing: 24,
                clipBehavior: Clip.none,
                children: [
                  for (var index = 0; index < games.length; index++)
                    SizedBox(
                      width: posterWidth,
                      height: posterWidth * 1.49,
                      child: _LibraryGameCard(
                        game: games[index],
                        onTap: () => onSelectGame(index),
                        onOpenAssistant: () =>
                            onOpenAssistant(games[index].data),
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [DesktopColors.orange, DesktopColors.orange2],
                  )
                : null,
            color: selected
                ? null
                : (hover ? const Color(0xFFFFF2E9) : DesktopColors.card),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.transparent : const Color(0x219B5435),
            ),
          ),
          child: Text(
            widget.label,
            style: _libraryToolbarTextStyle(
              active: selected,
              foreground: selected ? Colors.white : const Color(0xFF5E493B),
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
    final foreground = widget.active ? Colors.white : const Color(0xFF5E493B);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 38,
          constraints: const BoxConstraints(minWidth: 104),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: widget.active
                ? const LinearGradient(
                    colors: [DesktopColors.orange, DesktopColors.orange2],
                  )
                : null,
            color: widget.active
                ? null
                : (hover ? const Color(0xFFFFF2E9) : DesktopColors.card),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.active
                  ? Colors.transparent
                  : (hover ? const Color(0x55FF6846) : const Color(0x219B5435)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.leadingIcon != null) ...[
                Icon(widget.leadingIcon, size: 16, color: foreground),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: _libraryToolbarTextStyle(
                  active: widget.active,
                  foreground: foreground,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                key: const ValueKey<String>('desktop-library-action-arrow'),
                turns: widget.expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
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
  const _SortMenuRow({required this.item, required this.selected});

  final _DesktopGameSort item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (item) {
      _DesktopGameSort.catalog => '按相关性推荐',
      _DesktopGameSort.name => '按游戏名称 A-Z 排序',
      _DesktopGameSort.score => '按玩家评分从高到低',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF0E8) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? DesktopColors.orange : const Color(0xFF8A6E62),
            size: 25,
          ),
          const SizedBox(width: 14),
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
                        ? const Color(0xFFB64B2F)
                        : const Color(0xFF493D36),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DesktopColors.secondaryText,
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
    required this.player,
    required this.duration,
    required this.types,
    required this.weight,
    required this.minScore,
  });

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
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.filter_alt_outlined,
                  color: DesktopColors.orange,
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Text(
                  '筛选条件',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clear,
                  child: const Text(
                    '清除全部',
                    style: TextStyle(color: DesktopColors.orange),
                  ),
                ),
              ],
            ),
            const Divider(height: 10),
            _FilterGridSection(
              title: '玩家人数',
              columns: 5,
              children: [
                for (final value in const ['1', '2', '3', '4', '5+'])
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
                for (final option in const [
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
                for (final value in const ['入门', '轻度', '中度', '重度'])
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
                for (final value in const [7.0, 8.0, 9.0])
                  _OptionChip(
                    label: '${value.toInt()}+',
                    expand: true,
                    selected: minScore == value,
                    onTap: () => setState(() => minScore = value),
                  ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      side: const BorderSide(color: Color(0xFFFFB39B)),
                      foregroundColor: const Color(0xFFB64B2F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: const Text(
                      '重置',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: DesktopColors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: const Text(
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
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
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
      duration: const Duration(milliseconds: 120),
      height: 38,
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? DesktopColors.orange : const Color(0xFFFFFEFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? DesktopColors.orange : const Color(0xFFE9DFD8),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : const Color(0xFF5F554E),
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
    return DesktopLibraryPosterCard(
      key: ValueKey<String>('desktop-game-card-${game.data.id}'),
      controller: game.controller,
      game: game.data,
      onTap: onTap,
      onOpenAssistant: onOpenAssistant,
    );
  }
}
