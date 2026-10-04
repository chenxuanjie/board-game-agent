import 'package:flutter/material.dart';

import '../../core/theme/ui_tokens.dart';
import 'account_scope.dart';

/// Shared account entry for compact and desktop settings.
class AccountEntry extends StatelessWidget {
  const AccountEntry({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.maybeOf(context);
    if (account == null) return const SizedBox.shrink();
    final english = Localizations.localeOf(context).languageCode == 'en';
    return ListTile(
      key: const ValueKey('account-settings-entry'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_circle_outlined),
      title: Text(title),
      subtitle: Text(
        account.isSignedIn
            ? account.displayName
            : (english ? 'Sign in with Synology' : '登录群晖账号'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const AccountScreen())),
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _working = false;
  String? _failure;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : zh;

  Future<void> _run(Future<void> Function() operation, String failure) async {
    if (_working || AccountScope.maybeOf(context)?.isBusy == true) return;
    setState(() {
      _working = true;
      _failure = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = AccountScope.maybeOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _working || service?.isBusy == true;
    final awaiting = service?.isAwaitingBrowser == true;
    final signedIn = service?.isSignedIn == true;
    final error = _failure ?? service?.error;
    return Scaffold(
      key: const ValueKey('account-screen'),
      appBar: AppBar(title: Text(_text('账户', 'Account'))),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              key: const ValueKey('account-scroll'),
              padding: const EdgeInsets.all(UiTokens.sectionGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                      child: const Icon(Icons.person_outline_rounded, size: 32),
                    ),
                  ),
                  const SizedBox(height: UiTokens.sectionGap),
                  Text(
                    signedIn
                        ? service!.displayName
                        : _text('登录你的账户', 'Sign in to your account'),
                    key: const ValueKey('account-display-name'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: UiTokens.itemGap),
                  Text(
                    service == null
                        ? _text(
                            '账户服务暂不可用，请返回后重试。',
                            'Account service is unavailable. Go back and retry.',
                          )
                        : awaiting
                        ? _text(
                            '请在群晖登录页完成验证，然后返回这里。',
                            'Complete verification on the Synology sign-in page, then return here.',
                          )
                        : signedIn
                        ? service.isOffline
                              ? _text(
                                  '当前离线，联网后可重新连接。',
                                  'You are offline. Reconnect when online.',
                                )
                              : _text('已登录', 'Signed in')
                        : busy
                        ? _text('正在连接登录服务…', 'Connecting to sign-in…')
                        : service.isConfigured
                        ? _text(
                            '使用群晖账号登录，完成验证后自动返回。',
                            'Sign in with your Synology account and return after verification.',
                          )
                        : _text(
                            '登录服务尚未就绪，请稍后重试。',
                            'Sign-in is not ready yet. Please retry later.',
                          ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: UiTokens.sectionGap),
                  if (busy || awaiting) ...[
                    const LinearProgressIndicator(
                      key: ValueKey('account-loading'),
                    ),
                    if (awaiting) ...[
                      const SizedBox(height: UiTokens.itemGap),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('account-cancel'),
                          onPressed: service!.cancelSignIn,
                          child: Text(_text('取消登录', 'Cancel sign-in')),
                        ),
                      ),
                    ],
                    const SizedBox(height: UiTokens.itemGap),
                  ],
                  if (error != null && error.isNotEmpty) ...[
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        key: const ValueKey('account-error'),
                        padding: const EdgeInsets.all(UiTokens.pageInset),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(
                            UiTokens.controlRadius,
                          ),
                        ),
                        child: Text(
                          error,
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ),
                    const SizedBox(height: UiTokens.itemGap),
                  ],
                  if (service != null) ...[
                    FilledButton.icon(
                      key: ValueKey(
                        signedIn ? 'account-sign-out' : 'account-sign-in',
                      ),
                      onPressed: busy || awaiting
                          ? null
                          : signedIn
                          ? () => _run(
                              service.signOut,
                              _text('退出失败，请重试。', 'Could not sign out. Retry.'),
                            )
                          : () => _run(
                              service.signIn,
                              _text('登录失败，请重试。', 'Could not sign in. Retry.'),
                            ),
                      icon: Icon(
                        signedIn ? Icons.logout_rounded : Icons.login_rounded,
                      ),
                      label: Text(
                        _text(
                          signedIn ? '退出登录' : '登录',
                          signedIn ? 'Sign out' : 'Sign in',
                        ),
                      ),
                    ),
                    if (service.isOffline ||
                        error != null && service.isConfigured)
                      TextButton(
                        key: const ValueKey('account-restore'),
                        onPressed: busy || awaiting
                            ? null
                            : () => _run(
                                service.restore,
                                _text(
                                  '连接失败，请重试。',
                                  'Could not reconnect. Retry.',
                                ),
                              ),
                        child: Text(_text('重试连接', 'Reconnect')),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
