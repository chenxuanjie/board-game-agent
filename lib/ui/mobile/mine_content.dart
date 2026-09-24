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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          key: const ValueKey('mobile-mine-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _header(copy),
            _profileCard(copy),
            const SizedBox(height: 13),
            _shortcuts(copy),
            const SizedBox(height: 21),
            _sectionTitle(
              '$_assetRoot/recent_play_gamepad_icon.png',
              copy.localized('最近浏览', 'Recently viewed'),
              action: recent.isEmpty ? null : copy.localized('查看全部', 'See all'),
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
    );
  }

  Widget _header(AppCopy copy) => SizedBox(
    height: 105,
    child: Stack(
      children: [
        const Positioned.fill(
          child: Image(
            image: AssetImage('$_assetRoot/header_background.png'),
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 22,
          child: Row(
            children: [
              Image.asset(
                'assets/desktop/home/logo.png',
                width: 44,
                height: 44,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.localized('桌游伙伴', 'Board Game Buddy'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    Text(
                      copy.localized(
                        '好游戏 · 好伙伴 · 好时光',
                        'Good games · Better people',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFAC8068),
                      ),
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
        ),
      ],
    ),
  );

  Widget _profileCard(AppCopy copy) => Container(
    key: const ValueKey('mobile-mine-profile'),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFDFC),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0C9F5637),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD9B7),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 43,
                color: Color(0xFFB86A42),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0D8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          '$_assetRoot/crown_badge_icon.png',
                          width: 16,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          copy.localized('桌游伙伴', 'Player'),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF8B5A2E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              key: const ValueKey('mobile-mine-edit-profile'),
              onPressed: _editProfile,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                side: const BorderSide(color: Color(0xFFF2D9C8)),
              ),
              child: Text(
                copy.localized('编辑资料', 'Edit'),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            copy.localized('好桌游，让平凡的日子闪闪发光！', 'Good games brighten every day!'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              _stat(
                '${widget.controller.favoriteCount}',
                copy.localized('收藏游戏', 'Liked games'),
              ),
              _stat('-', copy.localized('游玩次数', 'Plays')),
              _stat('-', copy.localized('想玩清单', 'Wishlist')),
              _stat('-', copy.localized('最爱分类', 'Favorite genre')),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: _muted),
        ),
      ],
    ),
  );

  Widget _shortcuts(AppCopy copy) {
    final entries = <(String, String, String, Color, VoidCallback)>[
      (
        'heart_icon.png',
        copy.localized('我的收藏', 'My likes'),
        copy.localized(
          '${widget.controller.favoriteCount} 个游戏',
          '${widget.controller.favoriteCount} games',
        ),
        const Color(0xFFFFEBED),
        widget.onFavorites,
      ),
      (
        'wishlist_list_icon.png',
        copy.localized('想玩清单', 'Wishlist'),
        copy.localized('未开放', 'Coming soon'),
        const Color(0xFFFFF3DC),
        () => _notAvailable(copy.localized('想玩清单', 'Wishlist')),
      ),
      (
        'recent_play_gamepad_icon.png',
        copy.localized('最近浏览', 'Recent'),
        copy.localized('继续发现', 'Keep exploring'),
        const Color(0xFFFFECE7),
        widget.onRecentAll,
      ),
      (
        'history_clock_icon.png',
        copy.localized('历史记录', 'History'),
        copy.localized('未开放', 'Coming soon'),
        const Color(0xFFFFF1E8),
        () => _notAvailable(copy.localized('历史记录', 'History')),
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              key: ValueKey('mobile-mine-shortcut-$index'),
              onTap: entries[index].$5,
              borderRadius: BorderRadius.circular(17),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 7, 4, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 47,
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: entries[index].$4,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Image.asset(
                        '$_assetRoot/${entries[index].$1}',
                        width: 30,
                        height: 30,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entries[index].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      entries[index].$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: _muted),
                    ),
                  ],
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
        Icons.accessibility_new_rounded,
        copy.localized('我的桌游', 'My games'),
        copy.localized('未开放', 'Coming soon'),
        () => _notAvailable(copy.localized('我的桌游', 'My games')),
      ),
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
                      color: index == 0 ? _orange : const Color(0xFF5B677D),
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
