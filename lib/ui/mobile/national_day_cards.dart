part of 'national_day_screen.dart';

class _HolidayGameCard extends StatelessWidget {
  const _HolidayGameCard({
    required this.controller,
    required this.game,
    required this.featured,
    required this.onOpen,
    required this.onVote,
    required this.onRemove,
  });
  final AppController controller;
  final GameInfo game;
  final bool featured;
  final VoidCallback onOpen;
  final VoidCallback onVote;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final voted = controller.gameVotes.hasVoted(game.slug);
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('mobile-national-day-open-${game.slug}'),
        onTap: onOpen,
        child: Semantics(
          button: true,
          label: '查看${game.title}',
          child: featured && game.bannerAssetPath.isNotEmpty
              ? Image.asset(
                  game.bannerAssetPath,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, _, _) =>
                      MobileGameCover(controller: controller, game: game),
                )
              : MobileGameCover(controller: controller, game: game),
        ),
      ),
    );
    return Material(
      color: _cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: voted ? _orange : Colors.white.withValues(alpha: .85),
          width: voted ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(5),
            child: featured
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 126),
                            child: Stack(
                              children: [Positioned.fill(child: image)],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 25, 0, 10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  game.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    height: 1.25,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF342217),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _voteButton(context, voted),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      AspectRatio(aspectRatio: .84, child: image),
                      const SizedBox(height: 6),
                      Text(
                        game.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF342217),
                        ),
                      ),
                      _voteButton(context, voted),
                    ],
                  ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              key: ValueKey('mobile-national-day-remove-${game.slug}'),
              tooltip: '从清单移除${game.title}',
              onPressed: onRemove,
              iconSize: 18,
              icon: const DecoratedBox(
                decoration: BoxDecoration(
                  color: _cream,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close_rounded, color: _brown, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voteButton(BuildContext context, bool voted) => Semantics(
    toggled: voted,
    child: Tooltip(
      message: voted ? '取消想玩投票' : '投票想玩',
      child: TextButton.icon(
        key: ValueKey('mobile-national-day-vote-${game.slug}'),
        onPressed: controller.gameVotes.ready && !controller.gameVotes.saving
            ? onVote
            : null,
        style: TextButton.styleFrom(
          foregroundColor: _orange,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 2),
        ),
        icon: Icon(
          voted ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
          size: featured ? 23 : 17,
        ),
        label: Text(
          '${controller.gameVotes.count(game.slug)}',
          style: TextStyle(
            fontFamily: 'Noto Sans SC',
            fontSize: featured ? 21 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class _AddGameCard extends StatelessWidget {
  const _AddGameCard({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: .55,
    child: Material(
      color: _cream.withValues(alpha: .7),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const ValueKey('mobile-national-day-add'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: const _DashedFrame(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFAD7B5),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(Icons.add_rounded, size: 33, color: _brown),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '添加桌游',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: _brown),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
