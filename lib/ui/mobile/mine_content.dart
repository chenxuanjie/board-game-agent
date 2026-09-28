import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/games/models/game_info.dart';
import '../../features/games/models/recent_game_record.dart';
import '../../app/state/app_controller.dart';
import '../../core/localization/app_copy.dart';
import 'game_cover.dart';

const _ink = Color(0xFF222730);
const _muted = Color(0xFF778297);
const _orange = Color(0xFFFF643E);
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
  String _nickname = '小桌友';

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

  void _notAvailable(String title) {
    final copy = widget.controller.copy;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copy.localized('$title · 暂未开放', '$title · Coming soon')),
      ),
    );
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF7F0), Color(0xFFFAF3EC), Color(0xFFF7EFE7)],
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
              const SizedBox(height: 13),
              _shortcuts(copy),
              const SizedBox(height: 21),
              _sectionTitle(
                '$_assetRoot/recent_play_gamepad_icon.png',
                copy.localized('最近浏览', 'Recently viewed'),
                action: recent.isEmpty
                    ? null
                    : copy.localized('查看全部', 'See all'),
                onAction: widget.onRecentAll,
              ),
              const SizedBox(height: 10),
              if (recent.isEmpty)
                _emptyRecent(copy)
              else
                SizedBox(
                  height: 134,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recent.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => _recentCard(
                      recent[index],
                      recentBySlug[recent[index].slug.toLowerCase()]?.viewedAt,
                      copy,
                    ),
                  ),
                ),
              const SizedBox(height: 21),
              _sectionTitle(null, copy.localized('我的服务', 'My services')),
              const SizedBox(height: 10),
              _services(copy),
              const SizedBox(height: 16),
              _promo(),
            ],
          ),
        ),
      ),
    );
  }

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
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFF7EE), Color(0xFFFFE9D0)],
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
              child: Image.asset(
                '$_assetRoot/header_background_card.jpg',
                width: imageWidth,
                height: imageHeight,
                fit: BoxFit.fill,
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              Text(
                copy.localized('好游戏 · 好伙伴 · 好时光', 'Good games · Better people'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF9E7259)),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('mobile-mine-scan'),
          tooltip: copy.localized('扫一扫', 'Scan'),
          onPressed: () => _notAvailable(copy.localized('扫一扫', 'Scan')),
          icon: Image.asset('$_assetRoot/scan_icon.png', width: 24),
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
              const Positioned(
                right: 8,
                top: 7,
                child: CircleAvatar(radius: 4, backgroundColor: _orange),
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
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatarWithBadge(),
                  const SizedBox(width: 12),
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
                                  _nickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: _ink,
                                  ),
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
                              Text(
                                copy.localized('桌游伙伴', 'Player'),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF8B5A2E),
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
                      fontSize: 11,
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
                    copy.localized('收藏游戏', 'Liked games'),
                    onTap: widget.onFavorites,
                  ),
                  _statDivider(),
                  _stat('-', copy.localized('游玩次数', 'Plays')),
                  _statDivider(),
                  _stat('-', copy.localized('想玩清单', 'Wishlist')),
                  _statDivider(),
                  _stat('-', copy.localized('最爱分类', 'Favorite genre')),
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
              border: Border.all(color: Colors.white, width: 1.8),
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
            style: const TextStyle(
              fontSize: 19.5,
              fontWeight: FontWeight.w900,
              color: _ink,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _shortcuts(AppCopy copy) {
    final entries = <(String, IconData, String, Color, VoidCallback)>[
      (
        'heart_icon.png',
        Icons.favorite_rounded,
        copy.localized('我的收藏', 'My likes'),
        const Color(0xFFFFEDF0),
        widget.onFavorites,
      ),
      (
        'wishlist_list_icon.png',
        Icons.bookmark_rounded,
        copy.localized('想玩清单', 'Wishlist'),
        const Color(0xFFFFF4DE),
        () => _notAvailable(copy.localized('想玩清单', 'Wishlist')),
      ),
      (
        'recent_play_gamepad_icon.png',
        Icons.sports_esports_rounded,
        copy.localized('最近浏览', 'Recent'),
        const Color(0xFFFFEDE6),
        widget.onRecentAll,
      ),
      (
        'history_clock_icon.png',
        Icons.history_rounded,
        copy.localized('历史记录', 'History'),
        const Color(0xFFFFF0E8),
        () => _notAvailable(copy.localized('历史记录', 'History')),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 340 ? 6.0 : 8.0;
        final cardWidth = (constraints.maxWidth - gap * 3) / 4;
        final iconSize = (cardWidth * 0.33).clamp(22.0, 42.0);
        final labelSize = cardWidth < 75
            ? 9.0
            : cardWidth < 105
            ? 10.5
            : 12.5;
        return Row(
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              if (index > 0) SizedBox(width: gap),
              Expanded(
                child: InkWell(
                  key: ValueKey('mobile-mine-shortcut-$index'),
                  onTap: entries[index].$5,
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0C7A452B),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: entries[index].$4,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              '$_assetRoot/${entries[index].$1}',
                              width: iconSize,
                              height: iconSize,
                              errorBuilder: (_, _, _) => Icon(
                                entries[index].$2,
                                size: iconSize,
                                color: _orange,
                              ),
                            ),
                            SizedBox(height: cardWidth * 0.06),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      entries[index].$3,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: labelSize,
                                        fontWeight: FontWeight.w800,
                                        color: _ink,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: labelSize + 2,
                                    color: const Color(0xFF778297),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _sectionTitle(
    String? asset,
    String title, {
    String? action,
    VoidCallback? onAction,
  }) => Row(
    children: [
      asset == null
          ? const Icon(Icons.star_rounded, color: _orange, size: 25)
          : Image.asset(asset, width: 25, height: 25),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
      ),
      if (action != null)
        TextButton.icon(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: _muted,
            padding: EdgeInsets.zero,
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.chevron_right_rounded, size: 16),
          label: Text(action, style: const TextStyle(fontSize: 11)),
        ),
    ],
  );

  Widget _emptyRecent(AppCopy copy) => Container(
    height: 105,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: TextButton(
      onPressed: widget.onExplore,
      child: Text(
        copy.localized('还没有浏览记录，去发现桌游', 'No recent games. Explore now'),
      ),
    ),
  );

  Widget _recentCard(GameInfo game, DateTime? viewedAt, AppCopy copy) =>
      SizedBox(
        width: 77,
        child: InkWell(
          onTap: () => widget.onOpenGame(game),
          borderRadius: BorderRadius.circular(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 77,
                  height: 88,
                  child: MobileGameCover(
                    controller: widget.controller,
                    game: game,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              Text(
                _relativeTime(viewedAt, copy),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: _muted),
              ),
            ],
          ),
        ),
      );

  String _relativeTime(DateTime? date, AppCopy copy) {
    if (date == null) return '-';
    final days = DateTime.now().difference(date.toLocal()).inDays;
    if (days < 1) return copy.localized('今天', 'Today');
    if (days < 7) return copy.localized('$days 天前', '${days}d ago');
    return copy.localized(
      '${(days / 7).floor()} 周前',
      '${(days / 7).floor()}w ago',
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
      (
        Icons.support_agent_rounded,
        copy.localized('帮助与反馈', 'Help & feedback'),
        copy.localized('有问题？我们来帮你', 'How can we help?'),
        () => _notAvailable(copy.localized('帮助与反馈', 'Help & feedback')),
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF4EBE5)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                indent: 50,
                endIndent: 15,
                color: Color(0xFFF1EEF0),
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
                      color: const Color(0xFF5B677D),
                    ),
                    const SizedBox(width: 13),
                    SizedBox(
                      width: 83,
                      child: Text(
                        entries[index].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entries[index].$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: _muted),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _muted,
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
