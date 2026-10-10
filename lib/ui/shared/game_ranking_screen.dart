import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/ui_tokens.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_ranking_entry.dart';
import '../../features/games/services/game_vote_service.dart';
import '../desktop/desktop_responsive.dart';
import '../mobile/game_cover.dart';
import 'ranking_medal.dart';

/// Public favorites ranking, independent from seasonal want-to-play votes.
class GameRankingScreen extends StatefulWidget {
  const GameRankingScreen({
    super.key,
    required this.controller,
    required this.onOpenGame,
    this.onBack,
  });
  static const routeName = '/rankings';
  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback? onBack;
  @override
  State<GameRankingScreen> createState() => _GameRankingScreenState();
}

class _GameRankingScreenState extends State<GameRankingScreen> {
  bool _loading = true;
  bool _failed = false;
  bool _refreshRunning = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_refreshRunning) return;
    _refreshRunning = true;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await widget.controller.refreshFavoriteRankings();
    } catch (_) {
      _failed = true;
    } finally {
      _refreshRunning = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final copy = controller.copy;
    final statistics = controller.favoriteStatistics;
    final palette = AppPalette.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([controller, statistics]),
      builder: (context, _) {
        final entries = controller.favoriteRankings;
        final highestCount = entries.isEmpty ? 0 : entries.first.favoriteCount;
        final metrics = DesktopMetricsScope.of(context);
        final error =
            _failed ||
            statistics.loadError != null ||
            !controller.favoriteRankingSourceReady;
        final syncing =
            _loading || statistics.status == GameVoteSyncStatus.syncing;
        return Scaffold(
          key: const ValueKey('game-ranking-screen'),
          appBar: AppBar(
            leading: widget.onBack == null
                ? null
                : BackButton(onPressed: widget.onBack),
            backgroundColor: palette.pageBackground,
            toolbarHeight: metrics.px(64),
            title: Text(
              copy.localized('喜欢榜', 'Most liked'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: metrics.font(28),
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              IconButton(
                key: const ValueKey('ranking-refresh'),
                tooltip: copy.localized('刷新', 'Refresh'),
                onPressed: syncing ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.pageBackground,
                  Color.alphaBlend(
                    palette.primary.withValues(alpha: 0.035),
                    palette.pageBackground,
                  ),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: metrics.px(
                      DesktopResponsive.gamesMaxContentWidth,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (syncing) const LinearProgressIndicator(minHeight: 2),
                      if (!_loading && error)
                        _notice(
                          copy.localized('喜欢统计读取失败', 'Could not load likes'),
                          action: copy.localized('重试', 'Retry'),
                        )
                      else if (statistics.status == GameVoteSyncStatus.pending)
                        _notice(
                          copy.localized(
                            statistics.syncError ?? '同步未完成，显示已保存数据',
                            'Sync incomplete. Showing saved data',
                          ),
                          action: copy.localized('重试', 'Retry'),
                        ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            key: const ValueKey('game-ranking-list'),
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.all(
                              MediaQuery.sizeOf(context).width >= 760
                                  ? metrics.px(UiTokens.sectionGap)
                                  : UiTokens.pageInset,
                            ),
                            itemCount: entries.isEmpty ? 1 : entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: UiTokens.itemGap),
                            itemBuilder: (context, index) {
                              if (entries.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 48,
                                  ),
                                  child: Text(
                                    _loading
                                        ? copy.localized(
                                            '正在读取喜欢统计',
                                            'Loading likes',
                                          )
                                        : error
                                        ? copy.localized(
                                            '重试后查看排名',
                                            'Retry to see the ranking',
                                          )
                                        : copy.localized(
                                            '暂无桌游',
                                            'No games yet',
                                          ),
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }
                              return _RankingRow(
                                entry: entries[index],
                                highestCount: highestCount,
                                controller: controller,
                                onTap: () =>
                                    widget.onOpenGame(entries[index].game),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _notice(String text, {required String action}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(onPressed: _loading ? null : _refresh, child: Text(action)),
      ],
    ),
  );
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.entry,
    required this.highestCount,
    required this.controller,
    required this.onTap,
  });
  final GameRankingEntry entry;
  final int highestCount;
  final AppController controller;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final copy = controller.copy;
    final metrics = DesktopMetricsScope.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final leading = entry.rank == 1 && entry.favoriteCount > 0;
    final progress = highestCount == 0
        ? 0.0
        : entry.favoriteCount / highestCount;
    return Semantics(
      button: true,
      label: copy.localized(
        '第 ${entry.rank} 名，${entry.game.title}，${entry.favoriteCount} 人收藏',
        'Rank ${entry.rank}, ${entry.game.title}, ${entry.favoriteCount} likes',
      ),
      child: Material(
        color: leading
            ? Color.alphaBlend(
                RankingMedal.gold.withValues(alpha: 0.055),
                palette.surface,
              )
            : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.cardRadius),
          side: leading
              ? BorderSide(color: RankingMedal.gold.withValues(alpha: 0.35))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('ranking-game-${entry.game.slug}'),
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 760 &&
                  (textScale < 1.5 || constraints.maxWidth >= 1000);
              final coverWidth = wide ? metrics.px(72) : 44.0;
              final coverHeight = wide ? metrics.px(88) : 64.0;
              final count = Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${entry.favoriteCount}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: wide ? metrics.font(26) : 18,
                        fontWeight: FontWeight.w800,
                        color: palette.primary,
                      ),
                    ),
                    TextSpan(
                      text: copy.localized(
                        controller.favoriteStatistics.hasCachedRemoteCounts
                            ? ' 人收藏'
                            : ' 次喜欢',
                        ' likes',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: wide ? metrics.font(13) : 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
                key: ValueKey('ranking-count-${entry.game.slug}'),
              );
              final bar = ClipRRect(
                borderRadius: BorderRadius.circular(UiTokens.controlRadius),
                child: SizedBox(
                  key: ValueKey('ranking-bar-${entry.game.slug}'),
                  height: wide ? metrics.px(12) : 6,
                  child: ColoredBox(
                    color: palette.surfaceContainer,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        key: ValueKey('ranking-fill-${entry.game.slug}'),
                        widthFactor: progress,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              UiTokens.controlRadius,
                            ),
                            gradient: LinearGradient(
                              colors: [
                                Color.lerp(
                                  palette.primary,
                                  RankingMedal.gold,
                                  0.4,
                                )!,
                                palette.primary,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? metrics.px(UiTokens.sectionGap) : 12,
                  vertical: wide ? metrics.px(leading ? 10 : 3) : 12,
                ),
                child: Row(
                  children: [
                    RankingMedal(
                      rank: entry.rank,
                      decorated: entry.favoriteCount > 0 && entry.rank <= 3,
                      size: wide ? metrics.px(72) : 38,
                      labelKey: ValueKey('ranking-position-${entry.game.slug}'),
                    ),
                    SizedBox(width: wide ? metrics.px(24) : 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: coverWidth,
                        height: coverHeight,
                        child: ColoredBox(
                          color: palette.surfaceContainer,
                          child: MobileGameCover(
                            controller: controller,
                            game: entry.game,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: wide ? metrics.px(28) : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.game.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontSize: wide ? metrics.font(24) : 16,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          SizedBox(height: wide ? 12 : 4),
                          if (!wide) ...[count, const SizedBox(height: 8)],
                          bar,
                        ],
                      ),
                    ),
                    if (wide) ...[
                      SizedBox(width: metrics.px(28)),
                      SizedBox(
                        width: metrics.px(148) * textScale,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: palette.primary.withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.favorite_rounded,
                                color: palette.primary,
                                size: metrics.px(22),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: count),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
