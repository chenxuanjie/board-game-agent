import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/ui_tokens.dart';
import 'account_scope.dart';
import '../../features/identity/services/account_cloud_sync.dart';
import '../../features/identity/services/account_service.dart';

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

  Future<void> _editNickname(AccountService service) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _AccountNicknameDialog(
        nickname: service.displayName,
        title: _text('修改昵称', 'Edit nickname'),
        cancel: _text('取消', 'Cancel'),
        save: _text('保存', 'Save'),
      ),
    );
    if (value != null && mounted) {
      await _run(
        () => service.saveNickname(value),
        _text('昵称保存失败，请重试', 'Could not save nickname. Retry.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = AccountScope.maybeOf(context);
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final signedIn = service?.isSignedIn ?? false;
    final cloud = service?.cloud;
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
                          if (signedIn && cloud != null) ...[
                            SwitchListTile.adaptive(
                              key: const ValueKey('account-cloud-enabled'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(_text('账号云同步', 'Account cloud sync')),
                              subtitle: Text(
                                _text(
                                  '收藏、浏览记录、AI 对话和个人偏好',
                                  'Favorites, history, AI chats and preferences',
                                ),
                              ),
                              value: cloud.enabled,
                              onChanged: busy
                                  ? null
                                  : (value) => _run(
                                      () => cloud.setEnabled(value),
                                      _text(
                                        '同步设置保存失败，请重试',
                                        'Could not save sync setting. Retry.',
                                      ),
                                    ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  cloud.status == AccountCloudStatus.synced
                                      ? Icons.cloud_done_outlined
                                      : Icons.cloud_sync_outlined,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(switch (cloud.status) {
                                    AccountCloudStatus.syncing => _text(
                                      '正在同步…',
                                      'Syncing…',
                                    ),
                                    AccountCloudStatus.synced => _text(
                                      '已同步',
                                      'Synced',
                                    ),
                                    AccountCloudStatus.pending => _text(
                                      '等待重试',
                                      'Retry needed',
                                    ),
                                    AccountCloudStatus.paused => _text(
                                      '已暂停',
                                      'Paused',
                                    ),
                                    AccountCloudStatus.idle => _text(
                                      '等待同步',
                                      'Ready to sync',
                                    ),
                                  }),
                                ),
                                TextButton(
                                  key: const ValueKey('account-cloud-sync'),
                                  onPressed:
                                      !cloud.enabled ||
                                          cloud.status ==
                                              AccountCloudStatus.syncing
                                      ? null
                                      : cloud.synchronize,
                                  child: Text(_text('立即同步', 'Sync now')),
                                ),
                              ],
                            ),
                            if (cloud.error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  cloud.error!,
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                            TextButton.icon(
                              key: const ValueKey('account-edit-nickname'),
                              onPressed: busy
                                  ? null
                                  : () => _editNickname(service!),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: Text(_text('修改昵称', 'Edit nickname')),
                            ),
                            const SizedBox(height: UiTokens.itemGap),
                          ],
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

class _AccountNicknameDialog extends StatefulWidget {
  const _AccountNicknameDialog({
    required this.nickname,
    required this.title,
    required this.cancel,
    required this.save,
  });
  final String nickname, title, cancel, save;
  @override
  State<_AccountNicknameDialog> createState() => _AccountNicknameDialogState();
}

class _AccountNicknameDialogState extends State<_AccountNicknameDialog> {
  late final _input = TextEditingController(text: widget.nickname);
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _input,
      maxLength: 80,
      autofocus: true,
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text.trim()),
        child: Text(widget.save),
      ),
    ],
  );
}
