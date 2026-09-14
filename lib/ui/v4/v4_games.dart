// Body layout adapted directly from the read-only V4 reference.
import 'package:flutter/material.dart';
import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import 'v4_content_primitives.dart';
import 'v4_theme.dart';

class V4GamesPane extends StatefulWidget {
  const V4GamesPane({
    super.key,
    required this.controller,
    required this.onNavigate,
    required this.onOpenGame,
    this.showPreview = true,
  });
  final AppController controller;
  final ValueChanged<String> onNavigate;
  final ValueChanged<GameInfo> onOpenGame;
  final bool showPreview;
  @override
  State<V4GamesPane> createState() => _V4GamesPaneState();
}

class _V4GamesPaneState extends State<V4GamesPane> {
  String? _selectedId;
  int _category = 0;
  _V4GameSort _sort = _V4GameSort.catalog;
  String? _playerFilter;
  String? _weightFilter;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      const categories = ['全部', '策略', '家庭', '聚会', '合作', '双人'];
      final games =
          widget.controller.games
              .where(
                (g) =>
                    (_category == 0 ||
                        (_category == 5
                            ? g.supportedPlayers.contains(2)
                            : '${g.categoryLine} ${g.keywords.join(' ')}'
                                  .contains(categories[_category]))) &&
                    _matchesPlayer(g) &&
                    _matchesWeight(g),
              )
              .map((g) => V4ContentGame(g, widget.controller))
              .toList()
            ..sort(_compareGames);
      final found = games.indexWhere((g) => g.data.id == _selectedId);
      final index = found < 0 ? 0 : found;
      final selected = games.isEmpty ? null : games[index];
      void action(String label) {
        if (label == '查看规则' && selected != null) {
          widget.onOpenGame(selected.data);
        } else if ((label == '展开介绍' || label == '更多机制') && selected != null) {
          widget.onOpenGame(selected.data);
        } else {
          v4ContentPending(context, label);
        }
      }

      final main = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V4ContentStatus(
            controller: widget.controller,
            onOpenLibrary: () => widget.onNavigate('library'),
          ),
          if (games.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('暂无符合条件的游戏'),
                  TextButton(
                    onPressed: () => widget.onNavigate('library'),
                    child: const Text('打开资料库'),
                  ),
                ],
              ),
            ),
          _LibraryMain(
            games: games,
            selectedIndex: index,
            selectedCategory: _category,
            onSelectGame: (i) {
              if (!widget.showPreview ||
                  games[i].data.id == selected?.data.id) {
                widget.onOpenGame(games[i].data);
              } else {
                setState(() => _selectedId = games[i].data.id);
              }
            },
            onCategory: (i) => setState(() => _category = i),
            sortLabel: _sort.label,
            hasFilter: _playerFilter != null || _weightFilter != null,
            onSort: _chooseSort,
            onFilter: _chooseFilter,
            onUnavailable: action,
          ),
        ],
      );
      if (!widget.showPreview) return main;
      return V4ContentColumns(
        gap: 13,
        rightWidth: 360,
        main: main,
        right: selected == null
            ? const SizedBox(height: 648, child: Center(child: Text('请选择游戏')))
            : _GameDetailPanel(
                game: selected,
                favorite: false,
                onToggleFavorite: () => v4ContentPending(context, '收藏'),
                onOpenDetail: () => widget.onOpenGame(selected.data),
                onUnavailable: action,
              ),
      );
    },
  );

  int _compareGames(V4ContentGame a, V4ContentGame b) => switch (_sort) {
    _V4GameSort.catalog =>
      widget.controller.games
          .indexOf(a.data)
          .compareTo(widget.controller.games.indexOf(b.data)),
    _V4GameSort.name => a.title.compareTo(b.title),
    _V4GameSort.score => _score(b.data).compareTo(_score(a.data)),
  };

  double _score(GameInfo game) => double.tryParse(game.score) ?? -1;

  bool _matchesPlayer(GameInfo game) {
    final filter = _playerFilter;
    if (filter == null) return true;
    if (filter == '2') return game.supportedPlayers.contains(2);
    if (filter == '3-4') {
      return game.supportedPlayers.any((value) => value >= 3 && value <= 4);
    }
    return game.supportedPlayers.any((value) => value >= 5);
  }

  bool _matchesWeight(GameInfo game) {
    final filter = _weightFilter;
    if (filter == null) return true;
    final value = '${game.complexity} ${game.learningDifficulty}';
    if (filter == '轻度') return value.contains('轻');
    if (filter == '重度') return value.contains('重');
    return value.contains('中');
  }

  Future<void> _chooseSort() async {
    final value = await showDialog<_V4GameSort>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('排序'),
        children: [
          for (final item in _V4GameSort.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item),
              child: Row(
                children: [
                  Icon(
                    item == _sort
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(item.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (value != null && mounted) setState(() => _sort = value);
  }

  Future<void> _chooseFilter() async {
    var player = _playerFilter;
    var weight = _weightFilter;
    final result = await showDialog<(String?, String?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('筛选'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('人数'),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in const ['2', '3-4', '5+'])
                    ChoiceChip(
                      label: Text(value),
                      selected: player == value,
                      onSelected: (_) => setDialogState(
                        () => player = player == value ? null : value,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('策略重度'),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in const ['轻度', '中度', '重度'])
                    ChoiceChip(
                      label: Text(value),
                      selected: weight == value,
                      onSelected: (_) => setDialogState(
                        () => weight = weight == value ? null : value,
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, (null, null)),
              child: const Text('清除'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (player, weight)),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _playerFilter = result.$1;
        _weightFilter = result.$2;
      });
    }
  }
}

enum _V4GameSort {
  catalog('综合排序'),
  name('名称'),
  score('评分');

  const _V4GameSort(this.label);
  final String label;
}

class _LibraryMain extends StatelessWidget {
  final List<V4ContentGame> games;
  final int selectedIndex;
  final int selectedCategory;
  final ValueChanged<int> onSelectGame;
  final ValueChanged<int> onCategory;
  final String sortLabel;
  final bool hasFilter;
  final VoidCallback onSort;
  final VoidCallback onFilter;
  final ValueChanged<String> onUnavailable;

  const _LibraryMain({
    required this.games,
    required this.selectedIndex,
    required this.selectedCategory,
    required this.onSelectGame,
    required this.onCategory,
    required this.sortLabel,
    required this.hasFilter,
    required this.onSort,
    required this.onFilter,
    required this.onUnavailable,
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
                _OutlineAction(
                  label: sortLabel,
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: onSort,
                ),
                const SizedBox(width: 8),
                _OutlineAction(
                  label: hasFilter ? '筛选 · 已启用' : '筛选',
                  icon: Icons.filter_alt_outlined,
                  onTap: onFilter,
                ),
              ],
            );

            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: categoryRow,
                  ),
                  const SizedBox(height: 7),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }

            return SizedBox(
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: categoryRow,
                    ),
                  ),
                  const SizedBox(width: 8),
                  actions,
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final columns = (constraints.maxWidth / 145).floor().clamp(1, 4);
            final cardWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 12,
              children: [
                for (var i = 0; i < games.length; i++)
                  SizedBox(
                    width: cardWidth,
                    child: _LibraryGameCard(
                      game: games[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelectGame(i),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 700) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 45,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/v4/ref_library_promo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LibraryStats(count: games.length),
                ],
              );
            }
            final promoWidth = constraints.maxWidth * 0.58;
            return Row(
              children: [
                SizedBox(
                  width: promoWidth,
                  height: 45,
                  child: HoverSurface(
                    onTap: () => onUnavailable('桌游寄语'),
                    lift: 1,
                    borderRadius: BorderRadius.circular(10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/v4/ref_library_promo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _LibraryStats(count: games.length)),
              ],
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
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FilterChipButton> createState() => _FilterChipButtonState();
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
          duration: const Duration(milliseconds: 120),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [V4Colors.orange, V4Colors.orange2],
                  )
                : null,
            color: selected
                ? null
                : (hover ? const Color(0xFFFFF2E9) : V4Colors.card),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? Colors.transparent : const Color(0x219B5435),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : const Color(0xFF5E493B),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _OutlineAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_OutlineAction> createState() => _OutlineActionState();
}

class _OutlineActionState extends State<_OutlineAction> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hover ? const Color(0xFFFFF2E9) : V4Colors.card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0x219B5435)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF62493B),
                ),
              ),
              const SizedBox(width: 4),
              Icon(widget.icon, size: 16, color: V4Colors.brown),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryGameCard extends StatelessWidget {
  final V4ContentGame game;
  final bool selected;
  final VoidCallback onTap;

  const _LibraryGameCard({
    required this.game,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverSurface(
      onTap: onTap,
      lift: 2,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 278,
        decoration: BoxDecoration(
          color: V4Colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? V4Colors.orange : const Color(0x128A6044),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0x1FFF6846)
                  : const Color(0x0A7E4D2B),
              blurRadius: selected ? 13 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: double.infinity,
                  height: 158,
                  child: game.cover(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.2,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                game.englishTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8.2,
                  color: V4Colors.secondaryText,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFFFA400),
                    size: 16,
                  ),
                  const SizedBox(width: 1),
                  Text(
                    game.score,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 20,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: game.tags.length > 3 ? 3 : game.tags.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 4),
                  itemBuilder: (context, index) => _SmallTag(game.tags[index]),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(
                    Icons.group_rounded,
                    size: 11,
                    color: V4Colors.secondaryText,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      game.players,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.1,
                        color: V4Colors.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.schedule_rounded,
                    size: 11,
                    color: V4Colors.secondaryText,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      game.duration,
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.8,
                        color: V4Colors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallTag extends StatelessWidget {
  final String text;
  const _SmallTag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1EC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 8.8, color: Color(0xFF74675E)),
      ),
    );
  }
}

class _LibraryStats extends StatelessWidget {
  const _LibraryStats({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    final data = [
      (Icons.casino_rounded, '$count', '当前桌游'),
      (Icons.group_rounded, '-', '桌游爱好者'),
      (Icons.favorite_rounded, '-', '收藏总数'),
    ];
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: V4Colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x108A6044)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < data.length; i++) ...[
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    data[i].$1,
                    size: 19,
                    color: i == 2 ? const Color(0xFFFF5E56) : V4Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data[i].$2,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        data[i].$3,
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: V4Colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (i < data.length - 1)
              Container(width: 1, height: 33, color: const Color(0x128A6044)),
          ],
        ],
      ),
    );
  }
}

class _GameDetailPanel extends StatelessWidget {
  final V4ContentGame game;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenDetail;
  final ValueChanged<String> onUnavailable;

  const _GameDetailPanel({
    required this.game,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onOpenDetail,
    required this.onUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 648,
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
      decoration: BoxDecoration(
        color: V4Colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x108A6044)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C7E4D2B),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: '打开完整详情页',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onOpenDetail,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        width: 160,
                        height: 236,
                        child: game.cover(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 5),
                    Text(
                      game.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      game.englishTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: V4Colors.secondaryText,
                        letterSpacing: .2,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFA400),
                          size: 23,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          game.score,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '(${game.reviewCount})',
                            style: const TextStyle(
                              fontSize: 9,
                              color: V4Colors.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    _FavoriteButton(
                      favorite: favorite,
                      onTap: onToggleFavorite,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      game.quote,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: Color(0xFF665A52),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFF9F5EF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _DetailStat(
                  icon: Icons.group_rounded,
                  value: game.players,
                  label: '玩家人数',
                ),
                const _StatDivider(),
                _DetailStat(
                  icon: Icons.schedule_rounded,
                  value: game.duration,
                  label: '游戏时长',
                ),
                const _StatDivider(),
                _DetailStat(
                  icon: Icons.bar_chart_rounded,
                  value: game.difficulty,
                  label: '游戏难度',
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Text(
            game.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.2,
              height: 1.58,
              color: Color(0xFF5F554E),
            ),
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => onUnavailable('展开介绍'),
              child: const MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '展开',
                      style: TextStyle(
                        fontSize: 10,
                        color: V4Colors.orange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: V4Colors.orange,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                '游戏标签',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              InkWell(
                onTap: () => onUnavailable('更多机制'),
                child: const MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    children: [
                      Text(
                        '查看更多',
                        style: TextStyle(
                          fontSize: 10,
                          color: V4Colors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: V4Colors.orange,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 7,
            children: [
              for (final mechanism in game.mechanisms.take(6))
                _MechanismTag(mechanism),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _BottomAction(
                  label: '查看规则',
                  icon: Icons.menu_book_rounded,
                  filled: false,
                  onTap: () => onUnavailable('查看规则'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BottomAction(
                  label: '想玩 · 未开放',
                  icon: Icons.play_circle_fill_rounded,
                  filled: true,
                  onTap: () => onUnavailable('加入想玩'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatefulWidget {
  final bool favorite;
  final VoidCallback onTap;

  const _FavoriteButton({required this.favorite, required this.onTap});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            gradient: widget.favorite
                ? const LinearGradient(
                    colors: [V4Colors.orange, V4Colors.orange2],
                  )
                : null,
            color: widget.favorite
                ? null
                : (hover ? const Color(0xFFFFF2E9) : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: widget.favorite
                ? null
                : Border.all(color: const Color(0x309B5435)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 19,
                color: widget.favorite ? Colors.white : V4Colors.orange,
              ),
              const SizedBox(width: 7),
              Text(
                '收藏 · 未开放',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: widget.favorite ? Colors.white : V4Colors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _DetailStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: V4Colors.orange),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 8.3,
                    color: V4Colors.secondaryText,
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

class _StatDivider extends StatelessWidget {
  const _StatDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: const Color(0x128A6044));
}

class _MechanismTag extends StatelessWidget {
  final String text;
  const _MechanismTag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1EB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9.5, color: Color(0xFF695D55)),
      ),
    );
  }
}

class _BottomAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _BottomAction({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  State<_BottomAction> createState() => _BottomActionState();
}

class _BottomActionState extends State<_BottomAction> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 48,
          decoration: BoxDecoration(
            gradient: widget.filled
                ? const LinearGradient(
                    colors: [V4Colors.orange, V4Colors.orange2],
                  )
                : null,
            color: widget.filled
                ? null
                : (hover ? const Color(0xFFFFF2E9) : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: widget.filled
                ? null
                : Border.all(color: const Color(0x309B5435)),
            boxShadow: widget.filled && hover
                ? const [
                    BoxShadow(
                      color: Color(0x22FF6846),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 19,
                color: widget.filled ? Colors.white : V4Colors.brown,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: widget.filled ? Colors.white : const Color(0xFF5E493B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
