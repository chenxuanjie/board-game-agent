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
import 'inline_status_notice.dart';

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
  bool _loading = true, _failed = false, _refreshRunning = false;
  int _attempt = 0;
  Object? _dismissedNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh({bool userInitiated = false}) async {
    if (_refreshRunning) {
      if (userInitiated) {
        try {
          await widget.controller.refreshFavoriteRankings();
        } catch (_) {
          if (mounted) setState(() => _failed = true);
        }
      }
      return;
    }
    _refreshRunning = true;
    setState(() {
      _loading = true;
      _failed = false;
      if (userInitiated) ++_attempt;
    });
    try {
      await widget.controller.refreshFavoriteRankingPage();
    } catch (_) {
      _failed = true;
    } finally {
      _refreshRunning = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ListenableBuilder(
      listenable: widget.controller.favoriteStatistics,
      builder: (context, _) => _content(context),
    ),
  );

  Widget _content(BuildContext context) {
    final controller = widget.controller;
    final copy = controller.copy;
    final statistics = controller.favoriteStatistics;
    final palette = AppPalette.of(context);
    final compact = MediaQuery.sizeOf(context).width < 760;
    final metrics = DesktopMetricsScope.of(context);
    final hasData = controller.favoriteRankingHasData;
    final entries = hasData
        ? controller.favoriteRankings
        : <GameRankingEntry>[];
    final highestCount = entries.isEmpty ? 0 : entries.first.favoriteCount;
    final syncing = _loading || statistics.status == GameVoteSyncStatus.syncing;
    final readError =
        _failed ||
        statistics.loadError != null ||
        !controller.favoriteRankingSourceReady ||
        statistics.status == GameVoteSyncStatus.pending ||
        controller.gameCatalogFailed;
    final blocked = !hasData && !syncing && (readError || controller.hasGames);
    String? notice;
    if (hasData && !syncing) {
      if (readError) {
        notice = copy.localized(
          '更新未完成，显示上次排名',
          'Update incomplete; showing saved rankings',
        );
      } else if (statistics.publicationStatus ==
          GameVotePublicationStatus.failed) {
        notice = copy.localized(
          '喜欢已保存在本机，暂未同步',
          'Likes saved on this device; sync incomplete',
        );
      } else if (controller.favoriteRankingRealtimeError != null) {
        notice = copy.localized(
          '实时更新暂不可用',
          'Live updates are temporarily unavailable',
        );
      } else if (statistics.status == GameVoteSyncStatus.paused) {
        notice = copy.localized(
          '实时更新已暂停，显示上次排名',
          'Live updates paused; showing saved rankings',
        );
      }
    }
    final noticeRevision = (controller.identityUserId, _attempt, notice);
    return Scaffold(
      key: const ValueKey('game-ranking-screen'),
      appBar: AppBar(
        leading: widget.onBack != null
            ? BackButton(onPressed: widget.onBack)
            : null,
        backgroundColor: palette.pageBackground,
        toolbarHeight: metrics.px(64),
        centerTitle: compact,
        title: Text(
          copy.localized(
            compact ? '排行' : '喜欢榜',
            compact ? 'Rankings' : 'Most liked',
          ),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: compact ? 24 : metrics.font(28),
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (hasData || (!syncing && !blocked))
            IconButton(
              key: const ValueKey('ranking-refresh'),
              tooltip: copy.localized('刷新', 'Refresh'),
              onPressed: () => unawaited(_refresh(userInitiated: true)),
              icon: syncing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
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
                palette.primary.withValues(alpha: .035),
                palette.pageBackground,
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: metrics.px(DesktopResponsive.gamesMaxContentWidth),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (syncing && hasData)
                    const LinearProgressIndicator(minHeight: 2),
                  if (notice != null && _dismissedNotice != noticeRevision)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: InlineStatusNotice(
                        key: const ValueKey('ranking-status'),
                        keyPrefix: 'ranking-status',
                        message: notice,
                        revision: noticeRevision,
                        dismissLabel: copy.localized('关闭提示', 'Dismiss notice'),
                        onDismiss: () =>
                            setState(() => _dismissedNotice = noticeRevision),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _refresh(userInitiated: true),
                      child: ListView.separated(
                        key: const ValueKey('game-ranking-list'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(
                          compact
                              ? UiTokens.pageInset
                              : metrics.px(UiTokens.sectionGap),
                        ),
                        itemCount: entries.isEmpty ? 1 : entries.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: UiTokens.itemGap),
                        itemBuilder: (context, index) {
                          if (entries.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 48),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (syncing) ...[
                                    const SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  Text(
                                    copy.localized(
                                      syncing
                                          ? '正在加载喜欢榜…'
                                          : blocked
                                          ? '暂时无法加载喜欢榜'
                                          : '暂无桌游',
                                      syncing
                                          ? 'Loading rankings…'
                                          : blocked
                                          ? 'Rankings are unavailable'
                                          : 'No games yet',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (blocked)
                                    TextButton.icon(
                                      key: const ValueKey('ranking-retry'),
                                      onPressed: () => unawaited(
                                        _refresh(userInitiated: true),
                                      ),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: Text(
                                        copy.localized('重试', 'Retry'),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }
                          return _RankingRow(
                            entry: entries[index],
                            highestCount: highestCount,
                            controller: controller,
                            onTap: () => widget.onOpenGame(entries[index].game),
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
  }
}

class _MobileRankingContent extends StatelessWidget {
  const _MobileRankingContent({
    required this.entry,
    required this.controller,
    required this.progress,
  });
  final GameRankingEntry entry;
  final AppController controller;
  final double progress;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final copy = controller.copy;
    final title = Text(
      entry.game.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
    final count = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.favorite_rounded, color: palette.primary, size: 18),
        const SizedBox(width: 5),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${entry.favoriteCount}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: copy.localized(
                  controller.favoriteStatistics.hasCachedRemoteCounts
                      ? ' 人收藏'
                      : ' 次喜欢',
                  ' likes',
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
          key: ValueKey('ranking-count-${entry.game.slug}'),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          RankingMedal(
            rank: entry.rank,
            decorated: entry.favoriteCount > 0 && entry.rank <= 3,
            size: 34,
            crownOnly: true,
            labelKey: ValueKey('ranking-position-${entry.game.slug}'),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            height: 68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: MobileGameCover(
                controller: controller,
                game: entry.game,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final inline =
                    constraints.maxWidth >= 190 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 20;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (inline)
                      Row(
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: 6),
                          count,
                        ],
                      )
                    else ...[
                      title,
                      const SizedBox(height: 4),
                      count,
                    ],
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        UiTokens.controlRadius,
                      ),
                      child: SizedBox(
                        key: ValueKey('ranking-bar-${entry.game.slug}'),
                        height: 7,
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
                                  gradient: LinearGradient(
                                    colors: [
                                      palette.primary,
                                      RankingMedal.gold,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
    final mobile = MediaQuery.sizeOf(context).width < 760;
    final accented =
        leading || (mobile && entry.rank == 3 && entry.favoriteCount > 0);
    final accent = entry.rank == 3 ? RankingMedal.bronze : RankingMedal.gold;
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
        color: accented
            ? Color.alphaBlend(accent.withValues(alpha: 0.055), palette.surface)
            : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.cardRadius),
          side: accented
              ? BorderSide(color: accent.withValues(alpha: 0.35))
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
              if (!wide) {
                return _MobileRankingContent(
                  entry: entry,
                  controller: controller,
                  progress: progress,
                );
              }
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
