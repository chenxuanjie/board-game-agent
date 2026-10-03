import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/ui_tokens.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_ranking_entry.dart';
import '../../features/games/services/game_vote_service.dart';
import '../mobile/game_cover.dart';

/// Fully wired, but intentionally absent from public navigation.
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
            title: Text(copy.localized('喜欢榜', 'Most liked')),
            actions: [
              IconButton(
                key: const ValueKey('ranking-refresh'),
                tooltip: copy.localized('刷新', 'Refresh'),
                onPressed: syncing ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
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
                          '同步未完成，显示已保存数据',
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
                          padding: const EdgeInsets.all(UiTokens.pageInset),
                          itemCount: entries.isEmpty ? 1 : entries.length + 1,
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
                                          '还没有喜欢记录',
                                          'No likes yet',
                                        ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }
                            if (index == 0) {
                              return Text(
                                statistics.hasCachedRemoteCounts
                                    ? copy.localized(
                                        '按喜欢总数排序 · 同数并列',
                                        'Total likes · Ties share a rank',
                                      )
                                    : copy.localized(
                                        '本机喜欢 · 同数并列',
                                        'Local likes · Ties share a rank',
                                      ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.textSecondary),
                              );
                            }
                            return _RankingRow(
                              entry: entries[index - 1],
                              controller: controller,
                              onTap: () =>
                                  widget.onOpenGame(entries[index - 1].game),
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
    required this.controller,
    required this.onTap,
  });
  final GameRankingEntry entry;
  final AppController controller;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final copy = controller.copy;
    final top = entry.rank <= 3;
    return Semantics(
      button: true,
      label: copy.localized(
        '第 ${entry.rank} 名，${entry.game.title}，${entry.favoriteCount} 次喜欢',
        'Rank ${entry.rank}, ${entry.game.title}, ${entry.favoriteCount} likes',
      ),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.cardRadius),
          side: BorderSide(color: palette.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('ranking-game-${entry.game.slug}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${entry.rank}',
                    key: ValueKey('ranking-position-${entry.game.slug}'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: top ? palette.primary : palette.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    height: 88,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: MobileGameCover(
                        controller: controller,
                        game: entry.game,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.game.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        copy.localized(
                          '${entry.favoriteCount} 次喜欢',
                          '${entry.favoriteCount} likes',
                        ),
                        key: ValueKey('ranking-count-${entry.game.slug}'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
