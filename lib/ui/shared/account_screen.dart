import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/ui_tokens.dart';
import 'account_scope.dart';

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
            : (!account.supportsSignIn
                  ? (english
                        ? 'Sign-in is available in the app'
                        : '请使用 App 或桌面端登录')
                  : (english ? 'Sign in with Synology' : '登录群晖账号')),
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
  final _form = GlobalKey<FormState>();
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  bool _working = false, _showPassword = false, _otpShown = false;
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

  Future<void> _signIn() async {
    final service = AccountScope.maybeOf(context);
    if (service == null || !(_form.currentState?.validate() ?? false)) return;
    await _run(
      () => service.signIn(
        account: _account.text,
        password: _password.text,
        otp: _otpShown || service.needsOtp ? _otp.text : null,
      ),
      _text('登录失败，请重试。', 'Could not sign in. Retry.'),
    );
    if (!mounted) return;
    if (service.isSignedIn) {
      _password.clear();
      _otp.clear();
      TextInput.finishAutofillContext(shouldSave: false);
    }
    setState(() {
      _otpShown = service.needsOtp;
    });
  }

  Future<void> _cancel() async {
    final service = AccountScope.maybeOf(context);
    _password.clear();
    _otp.clear();
    await service?.cancelSignIn();
    if (mounted) {
      setState(() {
        _otpShown = false;
      });
    }
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = AccountScope.maybeOf(context);
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final signedIn = service?.isSignedIn ?? false;
    final busy = _working || (service?.isBusy ?? false);
    final otp = _otpShown || (service?.needsOtp ?? false);
    final error = _failure ?? service?.error;
    final fieldDecoration = InputDecoration(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiTokens.controlRadius),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
    return Scaffold(
      key: const ValueKey('account-screen'),
      appBar: AppBar(title: Text(_text('账户', 'Account'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(UiTokens.pageInset),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(UiTokens.sectionGap),
                  child: Form(
                    key: _form,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: colors.secondaryContainer,
                              foregroundColor: colors.onSecondaryContainer,
                              child: const Icon(
                                Icons.person_outline_rounded,
                                size: 30,
                              ),
                            ),
                          ),
                          const SizedBox(height: UiTokens.sectionGap),
                          Text(
                            signedIn
                                ? service!.displayName
                                : _text('登录群晖账号', 'Sign in with Synology'),
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
                                : signedIn
                                ? (service.isOffline
                                      ? _text(
                                          '当前离线，联网后可重新连接。',
                                          'You are offline. Reconnect when online.',
                                        )
                                      : _text('已登录', 'Signed in'))
                                : !service.supportsSignIn
                                ? _text(
                                    '网页版暂不支持账号登录，可继续以访客使用。',
                                    'Web sign-in is unavailable. You can continue as a guest.',
                                  )
                                : _text(
                                    '使用你的群晖账号和密码。',
                                    'Use your Synology account and password.',
                                  ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: UiTokens.sectionGap),
                          if (!signedIn &&
                              service != null &&
                              service.supportsSignIn) ...[
                            TextFormField(
                              key: const ValueKey('account-username'),
                              controller: _account,
                              readOnly: busy,
                              autofillHints: const [AutofillHints.username],
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.next,
                              decoration: fieldDecoration.copyWith(
                                labelText: _text('账号', 'Account'),
                                prefixIcon: const Icon(
                                  Icons.person_outline_rounded,
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? _text('请输入账号', 'Enter your account')
                                  : null,
                            ),
                            const SizedBox(height: UiTokens.itemGap),
                            TextFormField(
                              key: const ValueKey('account-password'),
                              controller: _password,
                              readOnly: busy,
                              obscureText: !_showPassword,
                              autofillHints: const [AutofillHints.password],
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: otp
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              decoration: fieldDecoration.copyWith(
                                labelText: _text('密码', 'Password'),
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _text(
                                    _showPassword ? '隐藏密码' : '显示密码',
                                    _showPassword
                                        ? 'Hide password'
                                        : 'Show password',
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => setState(
                                          () => _showPassword = !_showPassword,
                                        ),
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? _text('请输入密码', 'Enter your password')
                                  : null,
                              onFieldSubmitted: (_) {
                                if (!otp && !busy) _signIn();
                              },
                            ),
                            if (otp) ...[
                              const SizedBox(height: UiTokens.itemGap),
                              TextFormField(
                                key: const ValueKey('account-otp'),
                                controller: _otp,
                                readOnly: busy,
                                keyboardType: TextInputType.number,
                                autofillHints: const [
                                  AutofillHints.oneTimeCode,
                                ],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(8),
                                ],
                                textInputAction: TextInputAction.done,
                                decoration: fieldDecoration.copyWith(
                                  labelText: _text('验证码', 'Verification code'),
                                  prefixIcon: const Icon(
                                    Icons.verified_user_outlined,
                                  ),
                                ),
                                validator: (value) =>
                                    value == null ||
                                        !RegExp(r'^\d{6,8}$').hasMatch(value)
                                    ? _text('请输入有效验证码', 'Enter a valid code')
                                    : null,
                                onFieldSubmitted: (_) {
                                  if (!busy) _signIn();
                                },
                              ),
                            ],
                            const SizedBox(height: UiTokens.sectionGap),
                          ],
                          if (busy) ...[
                            const LinearProgressIndicator(
                              key: ValueKey('account-loading'),
                            ),
                            if (_working && !signedIn)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  key: const ValueKey('account-cancel'),
                                  onPressed: _cancel,
                                  child: Text(_text('取消登录', 'Cancel sign-in')),
                                ),
                              ),
                            const SizedBox(height: UiTokens.itemGap),
                          ],
                          if (error != null && error.isNotEmpty) ...[
                            Semantics(
                              liveRegion: true,
                              child: Container(
                                key: const ValueKey('account-error'),
                                padding: const EdgeInsets.all(
                                  UiTokens.pageInset,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.errorContainer,
                                  borderRadius: BorderRadius.circular(
                                    UiTokens.controlRadius,
                                  ),
                                ),
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: UiTokens.itemGap),
                          ],
                          if (service != null && service.supportsSignIn) ...[
                            FilledButton.icon(
                              key: ValueKey(
                                signedIn
                                    ? 'account-sign-out'
                                    : 'account-sign-in',
                              ),
                              onPressed: busy
                                  ? null
                                  : signedIn
                                  ? () => _run(
                                      service.signOut,
                                      _text(
                                        '退出失败，请重试。',
                                        'Could not sign out. Retry.',
                                      ),
                                    )
                                  : _signIn,
                              icon: Icon(
                                signedIn
                                    ? Icons.logout_rounded
                                    : Icons.login_rounded,
                              ),
                              label: Text(
                                _text(
                                  signedIn
                                      ? '退出登录'
                                      : otp
                                      ? '验证并登录'
                                      : '登录',
                                  signedIn
                                      ? 'Sign out'
                                      : otp
                                      ? 'Verify and sign in'
                                      : 'Sign in',
                                ),
                              ),
                            ),
                            if (service.isOffline || error != null)
                              TextButton(
                                key: const ValueKey('account-restore'),
                                onPressed: busy
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
            ),
          ),
        ),
      ),
    );
  }
}
