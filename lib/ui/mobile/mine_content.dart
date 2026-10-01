import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/ui_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/games/models/game_info.dart';
import '../../features/games/models/recent_game_record.dart';
import '../../app/state/app_controller.dart';
import '../../core/localization/app_copy.dart';
import '../shared/content_cards.dart';
import '../shared/hover_horizontal_scrollbar.dart';
import 'game_cover.dart';

const _assetRoot = 'assets/mobile/mine';

class MobileMineContent extends StatefulWidget {
  const MobileMineContent({
    super.key,
    required this.controller,
    required this.onOpenGame,
    required this.onFavorites,
    required this.onRecentAll,
    required this.onExplore,
    required this.onActivities,
    required this.onSettings,
  });

  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onFavorites;
  final VoidCallback onRecentAll;
  final VoidCallback onExplore;
  final VoidCallback onActivities;
  final VoidCallback onSettings;

  @override
  State<MobileMineContent> createState() => _MobileMineContentState();
}

class _ProfileCardClipper extends CustomClipper<Path> {
  const _ProfileCardClipper();

  @override
  Path getClip(Size size) {
    const radius = 24.0;
    final drop = (size.width * 0.13).clamp(50.0, 75.0);
    final start = size.width * 0.49;
    final end = size.width * 0.68;
    return Path()
      ..moveTo(radius, 0)
      ..lineTo(start, 0)
      ..cubicTo(
        start + (end - start) * 0.45,
        0,
        start + (end - start) * 0.55,
        drop,
        end,
        drop,
      )
      ..lineTo(size.width - radius, drop)
      ..quadraticBezierTo(size.width, drop, size.width, drop + radius)
      ..lineTo(size.width, size.height - radius)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - radius,
        size.height,
      )
      ..lineTo(radius, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ProfileCardShadowPainter extends CustomPainter {
  const _ProfileCardShadowPainter({required this.clipper});

  final _ProfileCardClipper clipper;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x147A452B)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawPath(clipper.getClip(size).shift(const Offset(0, 6)), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MobileMineContentState extends State<MobileMineContent> {
  static const _nicknameKey = 'mobile_profile_nickname';
  String _nickname = '';

  @override
  void initState() {
    super.initState();
    _loadNickname();
  }

  Future<void> _loadNickname() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_nicknameKey)?.trim();
    if (mounted && saved != null && saved.isNotEmpty) {
      setState(() => _nickname = saved);
    }
  }

  Future<void> _editProfile() async {
    final input = TextEditingController(text: _nickname);
    final copy = widget.controller.copy;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.localized('编辑资料', 'Edit profile')),
        content: TextField(
          controller: input,
          maxLength: 24,
          autofocus: true,
          decoration: InputDecoration(
            labelText: copy.localized('昵称', 'Nickname'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.localized('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: Text(copy.localized('保存', 'Save')),
          ),
        ],
      ),
    );
    input.dispose();
    if (!mounted || next == null || next.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nicknameKey, next);
    if (mounted) setState(() => _nickname = next);
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.controller.copy;
    final recent = widget.controller.recentlyViewedGames.take(8).toList();
    final recentBySlug = <String, RecentGameRecord>{
      for (final record in widget.controller.recentGameRecords)
        record.normalizedGameSlug: record,
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppPalette.of(context).pageBackground,
            AppPalette.of(context).pageBackground,
          ],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            key: const ValueKey('mobile-mine-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _integratedHeaderSection(copy),
              const SizedBox(height: 16),
              _shortcuts(copy),
              const SizedBox(height: UiTokens.sectionGap),
              _sectionTitle(
                '$_assetRoot/recent_play_gamepad_icon.png',
                copy.localized('最近浏览', 'Recently viewed'),
                action: recent.isEmpty
                    ? null
                    : copy.localized('查看全部', 'See all'),
                onAction: widget.onRecentAll,
              ),
              const SizedBox(height: 12),
              if (recent.isEmpty)
                _emptyRecent(copy)
              else
                _recentGames(recent, recentBySlug, copy),
              const SizedBox(height: UiTokens.sectionGap),
              _sectionTitle(null, copy.localized('我的服务', 'My services')),
              const SizedBox(height: 12),
              _services(copy),
              const SizedBox(height: 16),
              _promo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentGames(
    List<GameInfo> games,
    Map<String, RecentGameRecord> records,
    AppCopy copy,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final width = ((constraints.maxWidth - 24) / 3).clamp(88.0, 112.0);
      final coverHeight = width * 88 / 77;
      final scaler = MediaQuery.textScalerOf(context);
      final titleStyle = ContentCardStyle.title(context).copyWith(fontSize: 13);
      double lineHeight(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout(maxWidth: width);
        final height = painter.height;
        painter.dispose();
        return height;
      }

      final titleHeight = games
          .map((game) => lineHeight(game.title, titleStyle))
          .reduce((a, b) => a > b ? a : b);
      final dateHeight = games
          .map(
            (game) => lineHeight(
              _relativeTime(records[game.slug.toLowerCase()]?.viewedAt, copy),
              ContentCardStyle.body(context),
            ),
          )
          .reduce((a, b) => a > b ? a : b);
      final height = coverHeight + 6 + titleHeight + dateHeight;
      return HoverHorizontalScrollbar(
        keyPrefix: 'mobile-mine-recent',
        builder: (scrollController) => SizedBox(
          height: height.ceilToDouble(),
          child: ListView.separated(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: games.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: ContentCardStyle.gap),
            itemBuilder: (context, index) {
              final game = games[index];
              return SizedBox(
                width: width,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('mobile-mine-recent-${game.id}'),
                    borderRadius: BorderRadius.circular(UiTokens.controlRadius),
                    onTap: () => widget.onOpenGame(game),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            UiTokens.controlRadius,
                          ),
                          child: SizedBox(
                            width: width,
                            height: coverHeight,
                            child: MobileGameCover(
                              controller: widget.controller,
                              game: game,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Tooltip(
                          message: game.title,
                          child: Text(
                            game.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _relativeTime(
                            records[game.slug.toLowerCase()]?.viewedAt,
                            copy,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ContentCardStyle.body(context),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );

  Widget _integratedHeaderSection(AppCopy copy) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Match the artwork to the card width, then cap it on wider Web layouts
      // so the meeple and die stay inside the curved opening.
      final imageWidth = (width + 32).clamp(0.0, 420.0);
      final imageHeight = imageWidth * 763 / 2060;
      final imageRight = width * 0.126 - 55;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: -16,
            right: -16,
            height: imageHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: Theme.of(context).brightness == Brightness.dark
                      ? [
                          AppPalette.of(context).pageBackground,
                          AppPalette.of(context).pageBackground,
                        ]
                      : const [Color(0xFFFFF7EE), Color(0xFFFFE9D0)],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: imageRight,
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.transparent, Colors.black, Colors.black],
                stops: [0, 0.15, 1],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: Opacity(
                opacity: Theme.of(context).brightness == Brightness.dark
                    ? .18
                    : 1,
                child: Image.asset(
                  '$_assetRoot/header_background_card.jpg',
                  width: imageWidth,
                  height: imageHeight,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
          Positioned(
            top: 22,
            left: width * 0.57,
            width: width * 0.26,
            child: Transform.rotate(
              angle: -0.12,
              child: Text(
                copy.localized(
                  '桌游\n让生活多一点\n乐趣 ♡',
                  'Games bring\nmore joy\nto life ♡',
                ),
                maxLines: 3,
                style: TextStyle(
                  color: const Color(0xFFE97536),
                  fontSize: width < 340 ? 9.5 : 13,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  height: 1.2,
                ),
              ),
            ),
          ),
          Column(
            children: [
              _topNavRow(copy),
              const SizedBox(height: 8),
              _profileCard(copy),
            ],
          ),
        ],
      );
    },
  );

  Widget _topNavRow(AppCopy copy) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Row(
      children: [
        Image.asset('assets/desktop/home/logo.png', width: 44, height: 44),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.localized('桌游伙伴', 'Board Game Buddy'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.of(context).textPrimary,
                ),
              ),
            ],
          ),
        ),
        Stack(
          children: [
            IconButton(
              key: const ValueKey('mobile-mine-notifications'),
              tooltip: copy.localized('消息通知', 'Notifications'),
              onPressed: widget.onActivities,
              icon: Image.asset(
                '$_assetRoot/notification_bell_icon.png',
                width: 24,
              ),
            ),
            if (widget.controller.unreadActivityCount > 0)
              Positioned(
                right: 8,
                top: 7,
                child: CircleAvatar(
                  radius: 4,
                  backgroundColor: AppPalette.of(context).primary,
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _profileCard(AppCopy copy) {
    const clipper = _ProfileCardClipper();
    return CustomPaint(
      painter: const _ProfileCardShadowPainter(clipper: clipper),
      child: ClipPath(
        clipper: clipper,
        child: Container(
          key: const ValueKey('mobile-mine-profile'),
          color: AppPalette.of(context).surface,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatarWithBadge(),
                  const SizedBox(width: UiTokens.itemGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: _editProfile,
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _nickname.isEmpty
                                      ? copy.localized('设置昵称', 'Set nickname')
                                      : _nickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ContentCardStyle.section(context),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 19,
                                color: Color(0xFF8B94A4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1DA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                '$_assetRoot/crown_badge_icon.png',
                                width: 13,
                                height: 13,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  copy.localized('桌游伙伴', 'Player'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF8B5A2E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Keep content clear of the lowered right-hand edge.
                  const SizedBox(width: 76),
                ],
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: const ValueKey('mobile-mine-edit-profile'),
                  onPressed: _editProfile,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF9F7F5),
                    foregroundColor: const Color(0xFF6F7788),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                    minimumSize: const Size(0, 30),
                    side: const BorderSide(color: Color(0xFFEADBCE)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    copy.localized('编辑资料', 'Edit'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _stat(
                    '${widget.controller.favoriteCount}',
                    copy.localized('我的喜欢', 'Liked games'),
                    onTap: widget.onFavorites,
                  ),
                  _statDivider(),
                  _stat(
                    '${widget.controller.conversations.length}',
                    copy.localized('AI 对话', 'AI chats'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarWithBadge() => SizedBox(
    width: 64,
    height: 64,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFFE8D1), width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x187A452B),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/desktop/warmwood/avatar.png',
              fit: BoxFit.cover,
              width: 64,
              height: 64,
            ),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 21,
            height: 21,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFC654), Color(0xFFFFA21E)],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppPalette.of(context).surface,
                width: 1.8,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Image.asset(
              '$_assetRoot/crown_badge_icon.png',
              width: 12,
              height: 12,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _statDivider() =>
      Container(width: 1, height: 24, color: const Color(0xFFF1E5DC));

  Widget _stat(String value, String label, {VoidCallback? onTap}) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 19.5,
              fontWeight: FontWeight.w700,
              color: AppPalette.of(context).textPrimary,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _shortcuts(AppCopy copy) {
    final palette = AppPalette.of(context);
    final entries = <(IconData, String, VoidCallback)>[
      (
        Icons.favorite_rounded,
        copy.localized('我的喜欢', 'My likes'),
        widget.onFavorites,
      ),
      (
        Icons.history_rounded,
        copy.localized('最近浏览', 'Recent'),
        widget.onRecentAll,
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const SizedBox(width: UiTokens.itemGap),
          Expanded(
            child: Material(
              color: palette.surfaceContainer,
              borderRadius: BorderRadius.circular(ContentCardStyle.radius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('mobile-mine-shortcut-$index'),
                onTap: entries[index].$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 22,
                  ),
                  child: Row(
                    children: [
                      Icon(entries[index].$1, size: 24, color: palette.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entries[index].$2,
                          maxLines: 2,
                          style: ContentCardStyle.title(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(
    String? asset,
    String title, {
    String? action,
    VoidCallback? onAction,
  }) => Row(
    children: [
      Icon(
        asset == null ? Icons.grid_view_rounded : Icons.history_rounded,
        size: 24,
        color: AppPalette.of(context).primary,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: ContentCardStyle.section(context))),
      if (action != null)
        TextButton.icon(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: AppPalette.of(context).textSecondary,
            padding: EdgeInsets.zero,
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.chevron_right_rounded, size: 16),
          label: Text(action, style: ContentCardStyle.body(context)),
        ),
    ],
  );

  Widget _emptyRecent(AppCopy copy) => Container(
    height: 105,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: TextButton(
      onPressed: widget.onExplore,
      child: Text(
        copy.localized('还没有浏览记录，去发现桌游', 'No recent games. Explore now'),
      ),
    ),
  );

  String _relativeTime(DateTime? date, AppCopy copy) {
    if (date == null) return '-';
    return ContentCardStyle.relativeDate(
      date,
      copy.localized('zh', 'en') == 'zh',
    );
  }

  Widget _services(AppCopy copy) {
    final entries = <(IconData, String, String, VoidCallback)>[
      (
        Icons.notifications_rounded,
        copy.localized('消息通知', 'Notifications'),
        copy.localized('活动、评论、系统消息等', 'Activities and updates'),
        widget.onActivities,
      ),
      (
        Icons.settings_rounded,
        copy.localized('设置', 'Settings'),
        copy.localized('语言、偏好设置', 'Language and preferences'),
        widget.onSettings,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        borderRadius: BorderRadius.circular(UiTokens.groupRadius),
        border: Border.all(color: AppPalette.of(context).outline),
      ),
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 50,
                endIndent: 15,
                color: AppPalette.of(context).outline,
              ),
            InkWell(
              key: ValueKey('mobile-mine-service-$index'),
              onTap: entries[index].$4,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      entries[index].$1,
                      size: 22,
                      color: AppPalette.of(context).primary,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[index].$2,
                            style: ContentCardStyle.title(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entries[index].$3,
                            style: ContentCardStyle.body(context),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppPalette.of(context).textSecondary,
                      size: 19,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _promo() => AspectRatio(
    aspectRatio: 3,
    child: InkWell(
      key: const ValueKey('mobile-mine-promo'),
      onTap: widget.onExplore,
      borderRadius: BorderRadius.circular(17),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Image.asset('$_assetRoot/promo.png', fit: BoxFit.cover),
      ),
    ),
  );
}
