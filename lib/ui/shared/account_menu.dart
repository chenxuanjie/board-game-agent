import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/color_scheme_option.dart';
import '../../core/theme/ui_tokens.dart';
import '../../features/identity/services/account_service.dart';
import 'account_scope.dart';
import 'app_failure_notice.dart';
import 'app_modals.dart';

enum _AccountAction { account, notifications, signOut }

// Motion Prompt #055, MIT License (c) 2026 Shohei Ohtaki.
// https://showheyohtaki.github.io/motion-prompt/#055
class _AccountPopoverRoute extends PopupRoute<_AccountAction> {
  _AccountPopoverRoute({
    required this.anchor,
    required this.items,
    required this.reduced,
    required this.barrierText,
    required this.themes,
  });
  final Rect Function() anchor;
  final List<PopupMenuEntry<_AccountAction>> items;
  final bool reduced;
  final String barrierText;
  final CapturedThemes themes;
  late final AnimationController _motion;
  late final CurvedAnimation _curve;
  bool _finishing = false;
  bool _pendingClose = false;
  bool _allowReopen = true;
  _AccountAction? _pendingResult;
  Offset? _barrierPointer;

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => barrierText;
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  void install() {
    super.install();
    _motion =
        AnimationController(
          vsync: navigator!,
          duration: reduced ? Duration.zero : const Duration(milliseconds: 280),
          reverseDuration: reduced
              ? Duration.zero
              : const Duration(milliseconds: 200),
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed &&
              _pendingClose &&
              isActive) {
            _finishing = true;
            if (isCurrent) {
              navigator?.pop(_pendingResult);
            } else {
              navigator?.removeRoute(this, _pendingResult);
            }
          }
        });
    _curve = CurvedAnimation(
      parent: _motion,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _motion.forward();
  }

  @override
  bool didPop(_AccountAction? result) {
    if (_finishing || reduced) return super.didPop(result);
    if (!_pendingClose) {
      _pendingClose = true;
      _pendingResult = result;
      _motion.reverse();
    }
    return false;
  }

  @override
  Widget buildModalBarrier() => Listener(
    onPointerDown: (event) => _barrierPointer = event.position,
    child: ModalBarrier(
      dismissible: true,
      semanticsLabel: barrierText,
      onDismiss: () {
        final pointer = _barrierPointer;
        _barrierPointer = null;
        if (_allowReopen &&
            _pendingClose &&
            pointer != null &&
            anchor().contains(pointer)) {
          _pendingClose = false;
          _pendingResult = null;
          _motion.forward();
        } else {
          navigator?.maybePop();
        }
      },
    ),
  );

  @override
  void dispose() {
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          final size = MediaQuery.sizeOf(context);
          final origin = anchor();
          final below = math.max(0.0, size.height - origin.bottom - 12);
          final above = math.max(0.0, origin.top - 12);
          final placeBelow = below >= 260 || below >= above;
          return AnimatedBuilder(
            animation: _curve,
            builder: (context, child) => Opacity(
              opacity: _curve.value,
              child: Transform.translate(
                offset: Offset(0, (placeBelow ? 6 : -6) * (1 - _curve.value)),
                child: child,
              ),
            ),
            child: CustomMultiChildLayout(
              delegate: _AccountPopoverLayout(origin),
              children: [
                LayoutId(
                  id: _PopoverPart.panel,
                  child: Material(
                    key: const ValueKey('account-popover-panel'),
                    type: MaterialType.card,
                    color: colors.surfaceContainerHigh,
                    elevation:
                        PopupMenuTheme.of(context).elevation ??
                        (Theme.of(context).useMaterial3 ? 3 : 8),
                    shadowColor: PopupMenuTheme.of(context).shadowColor,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(UiTokens.cardRadius),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    child: IntrinsicWidth(
                      stepWidth: 56,
                      child: Semantics(
                        role: SemanticsRole.menu,
                        scopesRoute: true,
                        namesRoute: true,
                        explicitChildNodes: true,
                        label: MaterialLocalizations.of(context).popupMenuLabel,
                        child: SingleChildScrollView(
                          padding:
                              PopupMenuTheme.of(context).menuPadding ??
                              const EdgeInsets.symmetric(vertical: 8),
                          child: ListBody(children: items),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _PopoverPart { panel }

class _AccountPopoverLayout extends MultiChildLayoutDelegate {
  _AccountPopoverLayout(this.origin);
  final Rect origin;
  @override
  void performLayout(Size size) {
    final below = math.max(0.0, size.height - origin.bottom - 12);
    final above = math.max(0.0, origin.top - 12);
    final placeBelow = below >= 260 || below >= above;
    final available = math.max(0.0, placeBelow ? below : above);
    final maxWidth = math.max(0.0, math.min(320.0, size.width - 32));
    final minWidth = math.min(272.0, maxWidth);
    final panel = layoutChild(
      _PopoverPart.panel,
      BoxConstraints(
        maxWidth: maxWidth,
        minWidth: minWidth,
        maxHeight: available,
      ),
    );
    final left = (origin.right - panel.width)
        .clamp(16.0, math.max(16.0, size.width - panel.width - 16))
        .toDouble();
    final top = placeBelow ? origin.bottom + 4 : origin.top - panel.height - 4;
    positionChild(_PopoverPart.panel, Offset(left, top));
  }

  @override
  bool shouldRelayout(covariant _AccountPopoverLayout oldDelegate) =>
      origin != oldDelegate.origin;
}

/// Shared account entry; authentication and data-scope changes remain owned by
/// AccountService. Opening the menu never starts a connection or sync request.
class AccountMenuButton extends StatefulWidget {
  const AccountMenuButton({
    super.key,
    required this.onOpenAccount,
    required this.onOpenNotifications,
    this.unreadCount = 0,
  });

  final VoidCallback onOpenAccount;
  final VoidCallback onOpenNotifications;
  final int unreadCount;

  @override
  State<AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState extends State<AccountMenuButton> {
  final _focus = FocusNode();
  AccountService? _account;
  (String?, bool, bool)? _identity;
  ModalRoute<dynamic>? _menuRoute;
  bool _opening = false, _signingOut = false;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : zh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = AccountScope.maybeOf(context);
    if (_account != account) {
      _closeMenu();
      _account?.removeListener(_accountChanged);
      _account = account;
      _identity = null;
      account?.addListener(_accountChanged);
    }
    _accountChanged();
  }

  void _accountChanged() {
    final identity = (
      _account?.user?.id,
      _account?.isOffline ?? false,
      _account?.isBusy ?? false,
    );
    if (_identity != null && _identity != identity) {
      // A different identity must not inherit actions from an already open menu.
      _closeMenu();
    }
    _identity = identity;
  }

  void _closeMenu() {
    final route = _menuRoute;
    if (route == null) return;
    if (route is _AccountPopoverRoute) route._allowReopen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isCurrent) route.navigator?.pop();
    });
  }

  @override
  void dispose() {
    _closeMenu();
    _account?.removeListener(_accountChanged);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _signOut(AccountService account) async {
    if (_signingOut || account.isBusy || !account.isSignedIn) return;
    final fallback = _text('退出失败，请重试', 'Could not sign out. Retry.');
    setState(() => _signingOut = true);
    String? failure;
    try {
      await account.signOut();
      failure = account.error;
    } catch (_) {
      failure = fallback;
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
    if (mounted && failure != null) showAppFailureNotice(context, failure);
  }

  Future<void> _open() async {
    if (_opening) return;
    _focus.requestFocus();
    setState(() => _opening = true);
    final account = _account;
    final signedIn = account?.isSignedIn == true;
    final userId = account?.user?.id;
    final busy = _signingOut || account?.isBusy == true;
    final lifetime = AppMenuLifetime();
    final overlay = Navigator.of(context, rootNavigator: true).overlay!;
    RelativeRect position() {
      final box = context.findRenderObject()! as RenderBox;
      final bounds = overlay.context.findRenderObject()! as RenderBox;
      final origin = box.localToGlobal(Offset.zero, ancestor: bounds);
      return RelativeRect.fromRect(
        Rect.fromLTWH(
          origin.dx,
          origin.dy + box.size.height + 4,
          box.size.width,
          0,
        ),
        Offset.zero & bounds.size,
      );
    }

    final initialPosition = position();
    Rect anchor() {
      final box = context.findRenderObject()! as RenderBox;
      final bounds = overlay.context.findRenderObject()! as RenderBox;
      return box.localToGlobal(Offset.zero, ancestor: bounds) & box.size;
    }

    final initialAnchor = anchor();
    final warm =
        Theme.of(
          context,
        ).extension<AppPaletteThemeExtension>()?.palette.scheme ==
        ColorSchemeOption.warmwoodStudy;
    final items = <PopupMenuEntry<_AccountAction>>[
      PopupMenuItem<_AccountAction>(
        enabled: false,
        child: Builder(
          builder: (menuContext) {
            lifetime.capture(menuContext);
            _menuRoute = ModalRoute.of(menuContext);
            return _AccountMenuSummary(account: account);
          },
        ),
      ),
      const PopupMenuDivider(),
      _item(
        _AccountAction.account,
        signedIn ? Icons.manage_accounts_outlined : Icons.login_rounded,
        signedIn ? _text('账户管理', 'Manage account') : _text('登录', 'Sign in'),
        enabled: !busy,
      ),
      _item(
        _AccountAction.notifications,
        Icons.notifications_outlined,
        _text('消息通知', 'Notifications'),
        count: widget.unreadCount,
      ),
      if (signedIn) ...[
        const PopupMenuDivider(),
        _item(
          _AccountAction.signOut,
          Icons.logout_rounded,
          _text('退出登录', 'Sign out'),
          enabled: !busy,
        ),
      ],
    ];
    _AccountAction? action;
    try {
      if (warm) {
        final route = _AccountPopoverRoute(
          anchor: () => mounted ? anchor() : initialAnchor,
          items: items,
          reduced: AppMotion.reduced(context),
          barrierText: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
          themes: InheritedTheme.capture(
            from: context,
            to: Navigator.of(context, rootNavigator: true).context,
          ),
        );
        action = await Navigator.of(context, rootNavigator: true).push(route);
      } else {
        action = await showMenu<_AccountAction>(
          context: context,
          useRootNavigator: true,
          requestFocus: true,
          positionBuilder: (_, _) => mounted ? position() : initialPosition,
          constraints: BoxConstraints(
            minWidth: math.min(272, MediaQuery.sizeOf(context).width - 32),
            maxWidth: math.min(320, MediaQuery.sizeOf(context).width - 32),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UiTokens.cardRadius),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          popUpAnimationStyle: AppMotion.menuStyle(context),
          items: items,
        );
      }
      await lifetime.closed;
    } finally {
      _menuRoute = null;
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted) return;
    switch (action) {
      case _AccountAction.account:
        if (_account?.isBusy != true && !_signingOut) widget.onOpenAccount();
      case _AccountAction.notifications:
        widget.onOpenNotifications();
      case _AccountAction.signOut:
        if (account != null &&
            identical(account, _account) &&
            account.user?.id == userId) {
          await _signOut(account);
        }
      case null:
        break;
    }
  }

  PopupMenuItem<_AccountAction> _item(
    _AccountAction action,
    IconData icon,
    String title, {
    bool enabled = true,
    int count = 0,
  }) => PopupMenuItem(
    key: ValueKey('account-menu-${action.name}'),
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: UiTokens.itemGap),
        Expanded(child: Text(title)),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Badge(label: Text(count > 99 ? '99+' : '$count')),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.maybeOf(context);
    final busy = _signingOut || account?.isBusy == true;
    final signedIn = account?.isSignedIn == true;
    var label = signedIn
        ? '${_text('账户', 'Account')} · ${account!.displayName}'
        : _text('账户 · 未登录', 'Account · Signed out');
    if (widget.unreadCount > 0) {
      label += _text(
        '，${widget.unreadCount} 条未读通知',
        ', ${widget.unreadCount} unread notifications',
      );
    }
    return Semantics(
      expanded: _opening,
      child: IconButton(
        key: const ValueKey('account-menu-button'),
        tooltip: label,
        focusNode: _focus,
        onPressed: () => unawaited(_open()),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Badge(
          isLabelVisible: widget.unreadCount > 0,
          child: SizedBox(
            width: 44,
            height: 28,
            child: busy
                ? SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: _text('账号处理中', 'Account busy'),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        signedIn
                            ? Icons.account_circle
                            : Icons.account_circle_outlined,
                        size: 28,
                      ),
                      const Icon(Icons.expand_more_rounded, size: 16),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _AccountMenuSummary extends StatelessWidget {
  const _AccountMenuSummary({required this.account});
  final AccountService? account;

  @override
  Widget build(BuildContext context) {
    if (account case final service?) {
      return AnimatedBuilder(
        animation: service,
        builder: (context, _) => _summary(context),
      );
    }
    return _summary(context);
  }

  Widget _summary(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    String text(String zh, String en) => english ? en : zh;
    final signedIn = account?.isSignedIn == true;
    final colors = Theme.of(context).colorScheme;
    final status = account == null
        ? text('账户服务暂不可用', 'Account service unavailable')
        : account!.isBusy
        ? text('账号处理中…', 'Working…')
        : signedIn
        ? (account!.isOffline
              ? text('离线', 'Offline')
              : text('已登录', 'Signed in'))
        : text('未登录', 'Signed out');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            signedIn ? account!.displayName : text('访客', 'Guest'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (account?.error case final error?) ...[
            const SizedBox(height: 4),
            Text(
              error,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}
