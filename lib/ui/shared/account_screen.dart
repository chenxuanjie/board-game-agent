import 'app_modals.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/ui_tokens.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/color_scheme_option.dart';
import 'account_scope.dart';
import '../../features/identity/services/account_service.dart';
import '../../features/identity/services/saved_login_store.dart';
import '../../features/identity/models/service_configuration.dart';

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
                  ? (english ? 'Knowledge library connections' : '知识库连接')
                  : (english ? 'Account and personal data' : '账号与个人数据')),
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
  const AccountScreen({super.key, this.onBack});
  final VoidCallback? onBack;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _customServer = TextEditingController();
  bool _working = false, _showPassword = false, _otpShown = false;
  bool _signingIn = false, _canceling = false;
  int _loginGeneration = 0;
  bool _savePassword = false, _credentialsEdited = false;
  String? _formEnvironment, _prefilledUsername;
  AccountService? _historyService;
  String? _failure;
  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : zh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = AccountScope.maybeOf(context);
    if (service != null && service != _historyService) {
      _historyService = service;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(service.loadSavedLogins());
      });
    }
  }

  void _fillSavedLogin(SavedLogin entry, AccountService service) {
    _account.text = entry.username;
    _password.text = entry.password ?? '';
    _savePassword = entry.hasPassword;
    _prefilledUsername = entry.username;
    _showPassword = false;
  }

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
    if (service == null ||
        _working ||
        _canceling ||
        service.isBusy ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    final username = _account.text, password = _password.text;
    final verification = _otpShown || service.needsOtp ? _otp.text : null;
    final generation = ++_loginGeneration;
    setState(() => _signingIn = true);
    try {
      await _run(() async {
        if (!service.usesWebAccount &&
            _customServer.text.trim() != service.serviceAddress) {
          await service.configureService(_customServer.text);
        }
        if (!mounted || generation != _loginGeneration) return;
        await service.signIn(
          account: username,
          password: password,
          savePassword: _savePassword,
          otp: verification,
        );
      }, _text('登录失败，请重试。', 'Could not sign in. Retry.'));
      if (!mounted) return;
      if (service.isSignedIn) {
        _password.clear();
        _prefilledUsername = null;
        _credentialsEdited = false;
        _otp.clear();
        TextInput.finishAutofillContext(shouldSave: false);
      }
      setState(() => _otpShown = service.needsOtp);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _cancel() async {
    if (_canceling) return;
    ++_loginGeneration;
    final service = AccountScope.maybeOf(context);
    setState(() {
      _canceling = true;
      _failure = null;
      _credentialsEdited = true;
    });
    _password.clear();
    _otp.clear();
    try {
      await service?.cancelSignIn();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failure = _text('取消未完成，请重试', 'Could not cancel. Retry.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _canceling = false;
          _otpShown = service?.needsOtp ?? false;
        });
      }
    }
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _otp.dispose();
    _customServer.dispose();
    super.dispose();
  }

  Future<void> _editNickname(AccountService service) async {
    final value = await showAppDialog<String>(
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
    final busy = _working || _canceling || (service?.isBusy ?? false);
    final signingIn = (_signingIn || _canceling) && !signedIn;
    final otp = _otpShown || (service?.needsOtp ?? false);
    final error = _failure ?? service?.error;
    final environment = service?.serviceConfiguration?.environmentId;
    if (!signedIn &&
        !otp &&
        environment != null &&
        _formEnvironment != environment) {
      _formEnvironment = environment;
      _customServer.text = service!.serviceAddress;
      _account.clear();
      _password.clear();
      _savePassword = false;
      _credentialsEdited = false;
      _prefilledUsername = null;
    }
    if (!signedIn &&
        !_credentialsEdited &&
        _prefilledUsername == null &&
        service != null &&
        service.savedLogins.isNotEmpty) {
      _fillSavedLogin(service.savedLogins.first, service);
    }
    final fieldDecoration = InputDecoration(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiTokens.controlRadius),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
    final accountCard = Card(
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
                    child: const Icon(Icons.person_outline_rounded, size: 30),
                  ),
                ),
                const SizedBox(height: UiTokens.sectionGap),
                Text(
                  signedIn
                      ? service!.displayName
                      : service?.supportsSignIn == false
                      ? _text('访客', 'Guest')
                      : _text('登录账号', 'Sign in'),
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
                          '网页版暂不支持账号登录，知识库不可用。',
                          'Web sign-in is unavailable. The knowledge library requires sign-in.',
                        )
                      : _text('使用你的账号和密码。', 'Use your account and password.'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: UiTokens.sectionGap),
                if (signedIn && service != null)
                  TextButton.icon(
                    onPressed: busy ? null : () => _editNickname(service),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(_text('修改昵称', 'Edit nickname')),
                  ),
                if (signedIn && service?.personalSyncError != null)
                  Text(
                    service!.personalSyncError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.error,
                    ),
                  ),
                if (service?.publicSyncError != null)
                  TextButton.icon(
                    onPressed: busy ? null : service!.retryPublicSync,
                    icon: const Icon(Icons.refresh),
                    label: Text(_text('公共数据更新未完成，重试', 'Retry public updates')),
                  ),
                if (!signedIn && service != null && service.supportsSignIn) ...[
                  if (!service.usesWebAccount) ...[
                    TextFormField(
                      key: const ValueKey('account-service-address'),
                      controller: _customServer,
                      readOnly: busy || otp,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: fieldDecoration.copyWith(
                        labelText: _text('应用服务地址', 'Application service URL'),
                        hintText: 'https://service.example',
                        suffixIcon: IconButton(
                          tooltip: _text('保存服务地址', 'Save service URL'),
                          icon: const Icon(Icons.check_rounded),
                          onPressed: busy || otp
                              ? null
                              : () => _run(
                                  () => service.configureService(
                                    _customServer.text,
                                  ),
                                  _text(
                                    '服务地址未保存，请检查后重试',
                                    'Could not save service URL.',
                                  ),
                                ),
                        ),
                      ),
                      validator: (value) {
                        try {
                          ServiceConfiguration(Uri.parse(value?.trim() ?? ''));
                          return null;
                        } catch (_) {
                          return _text(
                            '请输入有效的 HTTPS 服务地址',
                            'Enter a valid HTTPS service URL',
                          );
                        }
                      },
                    ),
                    const SizedBox(height: UiTokens.itemGap),
                  ],
                  TextFormField(
                    key: const ValueKey('account-username'),
                    controller: _account,
                    readOnly: busy || otp,
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: fieldDecoration.copyWith(
                      labelText: _text('账号', 'Account'),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      suffixIcon: service.savedLogins.isEmpty
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (service.savedLogins.any(
                                  (e) => e.username == _account.text.trim(),
                                ))
                                  IconButton(
                                    key: const ValueKey('account-forget-login'),
                                    tooltip: _text(
                                      '移除已保存账号',
                                      'Remove saved account',
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    onPressed: busy || otp
                                        ? null
                                        : () async {
                                            final entry = service.savedLogins
                                                .firstWhere(
                                                  (e) =>
                                                      e.username ==
                                                      _account.text.trim(),
                                                );
                                            await service.forgetSavedLogin(
                                              entry,
                                            );
                                            if (!mounted) return;
                                            if (_account.text.trim() ==
                                                    entry.username &&
                                                _formEnvironment ==
                                                    entry.environment &&
                                                !service.savedLogins.any(
                                                  (e) =>
                                                      e.username ==
                                                      entry.username,
                                                )) {
                                              setState(() {
                                                _password.clear();
                                                _savePassword = false;
                                                _credentialsEdited = true;
                                              });
                                            }
                                          },
                                  ),
                                PopupMenuButton<SavedLogin>(
                                  key: const ValueKey('account-saved-logins'),
                                  tooltip: _text('已保存账号', 'Saved accounts'),
                                  enabled: !busy && !otp,
                                  icon: const Icon(
                                    Icons.arrow_drop_down_rounded,
                                  ),
                                  onSelected: (entry) => setState(() {
                                    _credentialsEdited = true;
                                    _fillSavedLogin(entry, service);
                                  }),
                                  itemBuilder: (_) => [
                                    for (final entry in service.savedLogins)
                                      PopupMenuItem(
                                        value: entry,
                                        child: Text(entry.username),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                    onChanged: (_) => setState(() {
                      _credentialsEdited = true;
                      if (_prefilledUsername != null &&
                          _account.text.trim() != _prefilledUsername) {
                        _password.clear();
                        _savePassword = false;
                        _prefilledUsername = null;
                      }
                    }),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? _text('请输入账号', 'Enter your account')
                        : null,
                  ),
                  const SizedBox(height: UiTokens.itemGap),
                  TextFormField(
                    key: const ValueKey('account-password'),
                    controller: _password,
                    readOnly: busy,
                    onChanged: (_) => _credentialsEdited = true,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.password],
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: otp
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: fieldDecoration.copyWith(
                      labelText: _text('密码', 'Password'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _text(
                          _showPassword ? '隐藏密码' : '显示密码',
                          _showPassword ? 'Hide password' : 'Show password',
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
                    validator: (value) => value == null || value.isEmpty
                        ? _text('请输入密码', 'Enter your password')
                        : null,
                    onFieldSubmitted: (_) {
                      if (!otp && !busy) _signIn();
                    },
                  ),
                  if (!service.usesWebAccount)
                    CheckboxListTile(
                      key: const ValueKey('account-save-password'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(_text('保存密码', 'Save password')),
                      value: _savePassword,
                      onChanged: busy || otp
                          ? null
                          : (value) => setState(() {
                              _credentialsEdited = true;
                              _savePassword = value ?? false;
                            }),
                    ),
                  if (otp) ...[
                    const SizedBox(height: UiTokens.itemGap),
                    TextFormField(
                      key: const ValueKey('account-otp'),
                      controller: _otp,
                      readOnly: busy,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      textInputAction: TextInputAction.done,
                      decoration: fieldDecoration.copyWith(
                        labelText: _text('验证码', 'Verification code'),
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                      ),
                      validator: (value) =>
                          value == null || !RegExp(r'^\d{6,8}$').hasMatch(value)
                          ? _text('请输入有效验证码', 'Enter a valid code')
                          : null,
                      onFieldSubmitted: (_) {
                        if (!busy) _signIn();
                      },
                    ),
                  ],
                ],
                if ((!signedIn && service?.supportsSignIn == true) || busy)
                  SizedBox(
                    height: UiTokens.sectionGap,
                    child: busy
                        ? Align(
                            child: LinearProgressIndicator(
                              key: const ValueKey('account-loading'),
                              semanticsLabel: _canceling
                                  ? _text('正在取消登录', 'Canceling sign-in')
                                  : signingIn
                                  ? _text('正在登录', 'Signing in')
                                  : _text('正在处理', 'Working'),
                            ),
                          )
                        : null,
                  ),
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
                if (service != null && service.supportsSignIn) ...[
                  if (otp && !busy)
                    TextButton(
                      key: const ValueKey('account-cancel-otp'),
                      onPressed: () => _run(
                        _cancel,
                        _text('取消未完成，请重试', 'Could not cancel. Retry.'),
                      ),
                      child: Text(_text('取消验证', 'Cancel verification')),
                    ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: Size(
                        0,
                        48 *
                            math.max(
                              1.0,
                              MediaQuery.textScalerOf(context).scale(14) / 14,
                            ),
                      ),
                    ),
                    key: ValueKey(
                      signedIn ? 'account-sign-out' : 'account-sign-in',
                    ),
                    onPressed: _canceling
                        ? null
                        : signingIn
                        ? _cancel
                        : busy
                        ? null
                        : signedIn
                        ? () => _run(
                            service.signOut,
                            _text('退出失败，请重试。', 'Could not sign out. Retry.'),
                          )
                        : _signIn,
                    icon: signingIn
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              key: const ValueKey('account-login-spinner'),
                              strokeWidth: 2,
                              color: _canceling
                                  ? colors.onSurfaceVariant
                                  : colors.onPrimary,
                            ),
                          )
                        : Icon(
                            signedIn
                                ? Icons.logout_rounded
                                : Icons.login_rounded,
                          ),
                    label: Text(
                      _text(
                        signedIn
                            ? '退出登录'
                            : _canceling
                            ? '正在取消…'
                            : signingIn
                            ? '取消登录'
                            : otp
                            ? '验证并登录'
                            : '登录',
                        signedIn
                            ? 'Sign out'
                            : _canceling
                            ? 'Canceling…'
                            : signingIn
                            ? 'Cancel sign-in'
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
                              _text('连接失败，请重试。', 'Could not reconnect. Retry.'),
                            ),
                      child: Text(_text('重试连接', 'Reconnect')),
                    ),
                ],
                if (service != null && !service.supportsSignIn && error != null)
                  TextButton(
                    key: const ValueKey('account-restore'),
                    onPressed: busy
                        ? null
                        : () => _run(
                            service.restore,
                            _text('连接失败，请重试。', 'Could not reconnect. Retry.'),
                          ),
                    child: Text(_text('重试连接', 'Reconnect')),
                  ),
                if (service?.savedLoginError != null) ...[
                  Text(
                    service!.savedLoginError!,
                    style: TextStyle(color: colors.error),
                  ),
                  if (service.savedLoginNeedsReload)
                    TextButton(
                      onPressed: busy ? null : service.loadSavedLogins,
                      child: Text(_text('重试', 'Retry')),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    const Widget? resources = null;
    return Scaffold(
      key: const ValueKey('account-screen'),
      appBar: AppBar(
        title: Text(_text('账户', 'Account')),
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final spatial =
                Theme.of(
                  context,
                ).extension<AppPaletteThemeExtension>()?.palette.scheme ==
                ColorSchemeOption.spatialCinema;
            final wide =
                (!spatial || resources != null) &&
                box.maxWidth >= (spatial ? 840 : 1000) &&
                MediaQuery.textScalerOf(context).scale(1) < 1.5;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(UiTokens.pageInset),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1180 : 600),
                  child: wide && resources != null
                      ? Row(
                          key: const ValueKey('account-wide-layout'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 4, child: accountCard),
                            const SizedBox(width: UiTokens.sectionGap),
                            Expanded(flex: 6, child: resources),
                          ],
                        )
                      : Column(
                          key: const ValueKey('account-compact-layout'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            accountCard,
                            if (resources != null) ...[
                              const SizedBox(height: UiTokens.itemGap),
                              resources,
                            ],
                          ],
                        ),
                ),
              ),
            );
          },
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
