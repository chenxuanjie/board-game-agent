import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/ui_tokens.dart';
import '../../core/theme/app_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/games/models/game_info.dart';
import '../../features/games/models/recent_game_record.dart';
import '../../app/state/app_controller.dart';
import '../../core/localization/app_copy.dart';
import '../shared/content_cards.dart';
import '../shared/account_scope.dart';
import '../shared/account_screen.dart';
import '../shared/game_ranking_screen.dart';
import '../shared/hover_horizontal_scrollbar.dart';
import 'game_cover.dart';

const _assetRoot = 'assets/mobile/mine';

/// The lowered right shoulder reveals the header artwork. Content in the
/// raised portion must stay to the left of the beginning of this curve.
class _ProfilePanelShape extends ShapeBorder {
  const _ProfilePanelShape({required this.outline});

  final Color outline;

  static double shoulderDrop(double width) => (width * .15).clamp(44.0, 64.0);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    const radius = 24.0;
    final drop = shoulderDrop(rect.width);
    final start = rect.width * .62;
    final end = rect.width * .80;
    return (Path()
          ..moveTo(radius, 0)
          ..lineTo(start, 0)
          ..cubicTo(
            start + (end - start) * .48,
            0,
            start + (end - start) * .52,
            drop,
            end,
            drop,
          )
          ..lineTo(rect.width - radius, drop)
          ..quadraticBezierTo(rect.width, drop, rect.width, drop + radius)
          ..lineTo(rect.width, rect.height - radius)
          ..quadraticBezierTo(
            rect.width,
            rect.height,
            rect.width - radius,
            rect.height,
          )
          ..lineTo(radius, rect.height)
          ..quadraticBezierTo(0, rect.height, 0, rect.height - radius)
          ..lineTo(0, radius)
          ..quadraticBezierTo(0, 0, radius, 0)
          ..close())
        .shift(rect.topLeft);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(
      getOuterPath(rect.deflate(.5), textDirection: textDirection),
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  ShapeBorder scale(double t) =>
      _ProfilePanelShape(outline: outline.withValues(alpha: outline.a * t));
}

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
    this.onConversations,
  });

  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onFavorites;
  final VoidCallback onRecentAll;
  final VoidCallback onExplore;
  final VoidCallback onActivities;
  final VoidCallback onSettings;
  final VoidCallback? onConversations;

  @override
  State<MobileMineContent> createState() => _MobileMineContentState();
}

class _GuestNicknameDialog extends StatefulWidget {
  const _GuestNicknameDialog({required this.nickname, required this.copy});

  final String nickname;
  final AppCopy copy;

  @override
  State<_GuestNicknameDialog> createState() => _GuestNicknameDialogState();
}

class _GuestNicknameDialogState extends State<_GuestNicknameDialog> {
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.nickname);
  }

  @override
  void dispose() {
    // The route keeps this widget mounted throughout its exit transition.
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.copy.localized('编辑资料', 'Edit profile')),
    content: TextField(
      controller: _input,
      maxLength: 24,
      autofocus: true,
      decoration: InputDecoration(
        labelText: widget.copy.localized('昵称', 'Nickname'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.copy.localized('取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text.trim()),
        child: Text(widget.copy.localized('保存', 'Save')),
      ),
    ],
  );
}

class _MobileMineContentState extends State<MobileMineContent> {
  static const _nicknameKey = 'mobile_profile_nickname';
  String _nickname = '';
  String? _activeNicknameKey;
  bool _signedIn = false;
  int _nicknameGeneration = 0;
  BuildContext? _profileDialogContext;
  bool _profileRouteOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = AccountScope.maybeOf(context);
    final key = account?.nicknameKey ?? _nicknameKey;
    final signedIn = account?.isSignedIn ?? false;
    if (_activeNicknameKey == key && _signedIn == signedIn) return;
    _activeNicknameKey = key;
    _signedIn = signedIn;
    _nickname = '';
    final generation = ++_nicknameGeneration;
    if (_profileDialogContext != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final dialog = _profileDialogContext;
        if (mounted &&
            dialog != null &&
            dialog.mounted &&
            ModalRoute.of(dialog)?.isCurrent == true) {
          _profileDialogContext = null;
          Navigator.of(dialog).pop();
        }
      });
    }
    if (!signedIn) _loadNickname(key, generation);
  }

  Future<void> _loadNickname(String key, int generation) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(key)?.trim() ?? '';
      if (mounted && generation == _nicknameGeneration && !_signedIn) {
        setState(() => _nickname = saved);
      }
    } catch (_) {
      // A device nickname must not prevent the account entry from opening.
    }
  }

  Future<void> _openProfile() async {
    if (_profileRouteOpen) return;
    _profileRouteOpen = true;
    try {
      if (AccountScope.maybeOf(context) == null) {
        await _editProfile();
      } else {
        await Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => const AccountScreen()));
      }
    } finally {
      _profileRouteOpen = false;
    }
  }

  Future<void> _editProfile() async {
    final key = _activeNicknameKey ?? _nicknameKey;
    final generation = _nicknameGeneration;
    final copy = widget.controller.copy;
    final next = await showDialog<String>(
      context: context,
      animationStyle: AppMotion.menuStyle(context),
      builder: (context) {
        _profileDialogContext = context;
        return _GuestNicknameDialog(nickname: _nickname, copy: copy);
      },
    );
    _profileDialogContext = null;
    if (!mounted ||
        next == null ||
        next.isEmpty ||
        _signedIn ||
        generation != _nicknameGeneration) {
      return;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted || _signedIn || generation != _nicknameGeneration) return;
      final saved = await preferences.setString(key, next);
      if (mounted && !_signedIn && generation == _nicknameGeneration) {
        if (saved) {
          setState(() => _nickname = next);
        } else {
          _nicknameFailure(copy);
        }
      }
    } catch (_) {
      if (mounted && generation == _nicknameGeneration) _nicknameFailure(copy);
    }
  }

  void _nicknameFailure(AppCopy copy) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copy.localized('昵称未保存，请重试', 'Could not save nickname. Retry.'),
        ),
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
      final palette = AppPalette.of(context);
      final dark = Theme.of(context).brightness == Brightness.dark;
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
            height: imageHeight + 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    dark ? palette.surfaceContainer : const Color(0xFFFFF3E3),
                    dark ? palette.pageBackground : const Color(0xFFFFEDD8),
                    palette.pageBackground,
                  ],
                  stops: const [0, .45, 1],
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
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Colors.black, Colors.transparent],
                    stops: [0, .68, 1],
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
            ),
          ),
          if (MediaQuery.textScalerOf(context).scale(16) <= 20)
            Positioned(
              top: 48,
              left: width * 0.57,
              width: width * 0.23,
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
                    fontSize: width < 340 ? 9 : 11,
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
              const SizedBox(height: 24),
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
    final account = AccountScope.maybeOf(context);
    final palette = AppPalette.of(context);
    final signedIn = account?.isSignedIn == true;
    final name = signedIn
        ? account!.displayName
        : _nickname.isNotEmpty
        ? _nickname
        : copy.localized('未登录', 'Not signed in');
    final status = signedIn
        ? copy.localized('已登录', 'Signed in')
        : account == null || !account.supportsSignIn
        ? copy.localized('本机资料', 'Local profile')
        : copy.localized('点击登录', 'Tap to sign in');
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = Color.lerp(palette.surface, palette.secondaryContainer, .10)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
        final drop = _ProfilePanelShape.shoulderDrop(constraints.maxWidth);
        return Material(
          key: const ValueKey('mobile-mine-profile'),
          color: Colors.transparent,
          elevation: 2,
          surfaceTintColor: Colors.transparent,
          shadowColor: palette.shadow.withValues(alpha: .12),
          shape: _ProfilePanelShape(
            outline: palette.surface.withValues(alpha: dark ? .10 : .70),
          ),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.surface.withValues(alpha: .92),
                  tint.withValues(alpha: .88),
                ],
              ),
            ),
            child: Column(
              children: [
                Semantics(
                  button: true,
                  label: copy.localized(
                    '$name，${signedIn ? '账户详情' : status}',
                    '$name, ${signedIn ? 'Account details' : status}',
                  ),
                  child: InkWell(
                    key: const ValueKey('mobile-mine-account-entry'),
                    onTap: _openProfile,
                    child: Padding(
                      // At normal sizes the name stays on the raised shoulder.
                      // Enlarged text uses the full width below the curved opening.
                      padding: EdgeInsets.fromLTRB(
                        16,
                        largeText ? drop + 12 : 18,
                        largeText ? 16 : constraints.maxWidth * .40,
                        14,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            key: const ValueKey('mobile-mine-avatar'),
                            radius: constraints.maxWidth < 340 ? 28 : 32,
                            backgroundColor: palette.secondaryContainer,
                            foregroundColor: palette.onSecondaryContainer,
                            child: const Icon(
                              Icons.person_outline_rounded,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        key: const ValueKey(
                                          'mobile-mine-profile-name',
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: ContentCardStyle.section(
                                          context,
                                        ).copyWith(fontSize: 22),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: palette.textSecondary,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  status,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: palette.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  key: const ValueKey('mobile-mine-statistics-panel'),
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (dark
                                ? Color.lerp(
                                    palette.surface,
                                    palette.surfaceContainer,
                                    .8,
                                  )!
                                : palette.surface)
                            .withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      _stat(
                        '${widget.controller.favoriteCount}',
                        copy.localized('我的喜欢', 'Liked games'),
                        key: const ValueKey('mobile-mine-favorites-stat'),
                        onTap: widget.onFavorites,
                      ),
                      _statDivider(),
                      _stat(
                        '${widget.controller.conversations.length}',
                        copy.localized('AI 对话', 'AI chats'),
                        key: const ValueKey('mobile-mine-conversations-stat'),
                        onTap: widget.onConversations,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statDivider() => Container(
    width: 1,
    height: 24,
    color: AppPalette.of(context).outline.withValues(alpha: .35),
  );

  Widget _stat(String value, String label, {Key? key, VoidCallback? onTap}) =>
      Expanded(
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
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
              color: Color.lerp(
                palette.surface,
                index == 0
                    ? palette.primaryContainer
                    : palette.secondaryContainer,
                .65,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ContentCardStyle.radius),
                side: BorderSide(color: palette.outline.withValues(alpha: .45)),
              ),
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
                      Icon(
                        entries[index].$1,
                        size: 24,
                        color: index == 0
                            ? palette.onPrimaryContainer
                            : palette.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entries[index].$2,
                          maxLines: 2,
                          style: ContentCardStyle.title(context).copyWith(
                            color: index == 0
                                ? palette.onPrimaryContainer
                                : palette.onSecondaryContainer,
                          ),
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
    key: const ValueKey('mobile-mine-empty-recent'),
    height: 105,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppPalette.of(context).outline),
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
      (
        Icons.leaderboard_rounded,
        copy.localized('排行榜', 'Rankings'),
        copy.localized('收藏人数排名', 'Ranked by likes'),
        () => Navigator.of(context).pushNamed(GameRankingScreen.routeName),
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
