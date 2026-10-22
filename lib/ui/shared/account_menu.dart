import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/ui_tokens.dart';
import '../../features/identity/services/account_service.dart';
import 'account_scope.dart';
import 'app_failure_notice.dart';
import 'app_modals.dart';

enum _AccountAction { account, notifications, signOut }

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
    _AccountAction? action;
    try {
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
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        popUpAnimationStyle: AppMotion.menuStyle(context),
        items: [
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
        ],
      );
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
