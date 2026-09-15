import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import 'content_primitives.dart';
import 'theme.dart';

/// Search suggestions and results backed by the active game catalog.
class DesktopHomeSearchOverlay extends StatelessWidget {
  const DesktopHomeSearchOverlay({
    super.key,
    required this.query,
    required this.games,
    required this.controller,
    required this.recentQueries,
    required this.tapRegionGroup,
    required this.onSelectQuery,
    required this.onClearHistory,
    required this.onTapOutside,
    required this.onOpenGame,
    required this.onOpenRules,
    required this.onAskAi,
    required this.onViewAll,
  });

  final String query;
  final List<GameInfo> games;
  final AppController controller;
  final List<String> recentQueries;
  final Object tapRegionGroup;
  final ValueChanged<String> onSelectQuery;
  final VoidCallback onClearHistory;
  final VoidCallback onTapOutside;
  final ValueChanged<GameInfo> onOpenGame;
  final ValueChanged<GameInfo> onOpenRules;
  final ValueChanged<GameInfo> onAskAi;
  final VoidCallback onViewAll;

  static const List<String> _quickFilters = <String>[
    '双人',
    '聚会',
    '合作',
    '策略',
    '家庭',
    '新手',
    '卡牌',
    '推理',
  ];
  static const List<String> _suggestions = <String>[
    '适合新手的桌游',
    '两人可以玩的桌游',
    '聚会推荐桌游',
    '合作类桌游',
  ];

  List<GameInfo> get _results => _findGames(query, games);

  @override
  Widget build(BuildContext context) => TapRegion(
    groupId: tapRegionGroup,
    onTapOutside: (_) => onTapOutside(),
    child: Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double maxHeight = math.min(500, constraints.maxHeight);
          return Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: DesktopColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DesktopColors.line),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: query.trim().isEmpty
                    ? _buildDiscoveryPanel()
                    : _buildResultsPanel(_results),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _buildDiscoveryPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _SectionHeader(
        icon: Icons.history_rounded,
        title: '最近搜索',
        trailing: TextButton.icon(
          onPressed: onClearHistory,
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('清空记录'),
          style: _linkStyle,
        ),
      ),
      const SizedBox(height: 8),
      if (recentQueries.isEmpty)
        const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('暂无最近搜索', style: _metaStyle),
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String value in recentQueries)
              _QueryChip(
                label: value,
                icon: Icons.schedule_rounded,
                onPressed: () => onSelectQuery(value),
              ),
          ],
        ),
      const SizedBox(height: 15),
      const _SectionHeader(
        icon: Icons.tune_rounded,
        title: '快速筛选',
        iconColor: DesktopColors.orange,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final String value in _quickFilters)
            _QueryChip(label: value, onPressed: () => onSelectQuery(value)),
        ],
      ),
      const SizedBox(height: 15),
      _SectionHeader(
        icon: Icons.auto_awesome_rounded,
        title: '桌游推荐',
        trailing: TextButton.icon(
          onPressed: onViewAll,
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          label: const Text('查看游戏库'),
          style: _linkStyle,
        ),
      ),
      const SizedBox(height: 8),
      if (games.isEmpty)
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('游戏资料尚未加载', style: _metaStyle),
        )
      else
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double gap = 10;
            final int columns = ((constraints.maxWidth + gap) / 94)
                .floor()
                .clamp(2, 6);
            final double itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 10,
              children: <Widget>[
                for (final GameInfo game in games.take(columns))
                  SizedBox(
                    width: itemWidth,
                    child: _RecommendationCard(
                      game: game,
                      controller: controller,
                      onTap: () => onOpenGame(game),
                    ),
                  ),
              ],
            );
          },
        ),
      const SizedBox(height: 10),
      const Divider(height: 1),
      for (final String suggestion in _suggestions)
        _SuggestionRow(
          label: suggestion,
          onTap: () => onSelectQuery(suggestion),
        ),
    ],
  );

  Widget _buildResultsPanel(List<GameInfo> results) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _SectionHeader(
        icon: Icons.search_rounded,
        title: '搜索结果（${results.length}）',
        trailing: TextButton.icon(
          onPressed: onViewAll,
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          label: const Text('打开游戏库'),
          style: _linkStyle,
        ),
      ),
      const SizedBox(height: 8),
      if (results.isEmpty)
        _EmptyResult(query: query, onClear: () => onSelectQuery(''))
      else ...<Widget>[
        for (final GameInfo game in results.take(8))
          _SearchResultRow(
            game: game,
            controller: controller,
            onOpen: () => onOpenGame(game),
            onOpenRules: () => onOpenRules(game),
            onAskAi: () => onAskAi(game),
          ),
        if (results.length > 8)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: onViewAll,
              child: Text('在游戏库中查看全部 ${results.length} 个结果'),
            ),
          ),
      ],
    ],
  );

  static List<GameInfo> _findGames(String value, List<GameInfo> games) {
    final String normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return <GameInfo>[];
    final String compactQuery = normalized.replaceAll(
      RegExp(r'[\s，,。.!！?？、：:；;（）()\[\]【】]'),
      '',
    );
    final List<String> terms = _queryTerms(normalized);

    return games
        .where((GameInfo game) {
          final List<String> searchableValues = <String>[
            game.title,
            game.subtitle,
            ...game.aliases,
            ...game.designers,
            ...game.publishers,
            ...game.keywords,
            game.categoryLine,
            game.summary,
            game.heroTagline,
            game.mentorPitch,
            game.assistantIntro,
            game.complexity,
            game.learningDifficulty,
            game.playerCount,
            game.playTime,
          ];
          final String searchable = searchableValues.join(' ').toLowerCase();
          final String compactSearchable = searchable.replaceAll(
            RegExp(r'[\s，,。.!！?？、：:；;（）()\[\]【】]'),
            '',
          );
          if (compactSearchable.contains(compactQuery)) return true;
          if (terms.any(searchable.contains)) return true;

          if (RegExp(r'双人|两人|2人').hasMatch(normalized) &&
              game.supportedPlayers.contains(2)) {
            return true;
          }
          if (RegExp(r'新手|入门|轻度').hasMatch(normalized) &&
              RegExp(r'轻|易|入门|新手|简单').hasMatch(
                <String>[
                  game.complexity,
                  game.learningDifficulty,
                  ...game.keywords,
                ].join(' '),
              )) {
            return true;
          }
          if (RegExp(r'聚会|派对').hasMatch(normalized) &&
              RegExp(r'聚会|派对|派对游戏|party|social').hasMatch(searchable)) {
            return true;
          }
          if (RegExp(r'合作|协作').hasMatch(normalized) &&
              RegExp(r'合作|协作|cooperative').hasMatch(searchable)) {
            return true;
          }
          return false;
        })
        .toList(growable: false);
  }

  static List<String> _queryTerms(String query) {
    final String cleaned = query.replaceAll(
      RegExp(
        r'适合|推荐|我想玩|想玩|可以玩的|可以玩|玩的|桌游|游戏|给我|帮我|找|搜索|查询|查找|有什么|有没有|的|一个|一些|类型|类',
      ),
      ' ',
    );
    return cleaned
        .split(RegExp(r'[\s，,。.!！?？、：:；;]+'))
        .where((String term) => term.isNotEmpty)
        .toList(growable: false);
  }
}

const TextStyle _metaStyle = TextStyle(
  fontSize: 12,
  color: DesktopColors.secondaryText,
  height: 1.45,
);

const ButtonStyle _linkStyle = ButtonStyle(
  visualDensity: VisualDensity.compact,
  padding: WidgetStatePropertyAll<EdgeInsets>(
    EdgeInsets.symmetric(horizontal: 6),
  ),
  textStyle: WidgetStatePropertyAll<TextStyle>(TextStyle(fontSize: 12)),
  foregroundColor: WidgetStatePropertyAll<Color>(DesktopColors.secondaryText),
);

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.iconColor = DesktopColors.secondaryText,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: 19, color: iconColor),
      const SizedBox(width: 7),
      Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: DesktopColors.text,
        ),
      ),
      const Spacer(),
      ?trailing,
    ],
  );
}

class _QueryChip extends StatelessWidget {
  const _QueryChip({required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: icon == null
        ? null
        : Icon(icon, size: 14, color: DesktopColors.secondaryText),
    label: Text(label),
    onPressed: onPressed,
    labelStyle: const TextStyle(fontSize: 12, color: DesktopColors.text),
    visualDensity: VisualDensity.compact,
    side: BorderSide.none,
    backgroundColor: DesktopColors.soft,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  );
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.game,
    required this.controller,
    required this.onTap,
  });

  final GameInfo game;
  final AppController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: AspectRatio(
              aspectRatio: 1,
              child: DesktopContentGame(game, controller).cover(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            game.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DesktopColors.text,
            ),
          ),
          Text(
            game.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: DesktopColors.secondaryText,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    visualDensity: const VisualDensity(vertical: -3),
    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
    leading: const Icon(
      Icons.search_rounded,
      size: 17,
      color: DesktopColors.secondaryText,
    ),
    title: Text(label, style: const TextStyle(fontSize: 13)),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: DesktopColors.secondaryText,
    ),
    onTap: onTap,
  );
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.game,
    required this.controller,
    required this.onOpen,
    required this.onOpenRules,
    required this.onAskAi,
  });

  final GameInfo game;
  final AppController controller;
  final VoidCallback onOpen;
  final VoidCallback onOpenRules;
  final VoidCallback onAskAi;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('desktop-search-result-${game.id}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 42,
                  height: 56,
                  child: DesktopContentGame(game, controller).cover(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DesktopColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (game.subtitle.trim().isNotEmpty) game.subtitle,
                        if (game.playerCount.trim().isNotEmpty)
                          game.playerCount,
                        if (game.playTime.trim().isNotEmpty) game.playTime,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _metaStyle,
                    ),
                  ],
                ),
              ),
              if (game.score.trim().isNotEmpty &&
                  game.score != '—') ...<Widget>[
                const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: Color(0xFFFFA400),
                ),
                const SizedBox(width: 2),
                Text(game.score, style: const TextStyle(fontSize: 12)),
              ],
              IconButton(
                tooltip: '查看规则资料',
                onPressed: onOpenRules,
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: '询问 AI',
                onPressed: onAskAi,
                icon: const Icon(Icons.smart_toy_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(
      children: <Widget>[
        const Icon(
          Icons.search_off_rounded,
          size: 30,
          color: DesktopColors.secondaryText,
        ),
        const SizedBox(height: 7),
        Text(
          '没有找到“$query”',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        const Text('试试桌游名称、机制、作者或玩法关键词。', style: _metaStyle),
        TextButton(onPressed: onClear, child: const Text('清空关键词')),
      ],
    ),
  );
}
