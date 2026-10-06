import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/ui_tokens.dart';
import '../../features/identity/services/account_service.dart';
import '../../features/settings/models/configuration_transfer.dart';
import '../../features/settings/services/settings_transfer_service.dart';
import 'nas_connection_section.dart';
import 'resource_access_summary.dart';
import 'settings_transfer_screen.dart';

/// Resource actions share the account service; layout belongs to AccountScreen.
class AccountResourcesSection extends StatefulWidget {
  const AccountResourcesSection({
    super.key,
    required this.service,
    this.expanded = false,
  });
  final AccountService service;
  final bool expanded;

  @override
  State<AccountResourcesSection> createState() =>
      _AccountResourcesSectionState();
}

class _AccountResourcesSectionState extends State<AccountResourcesSection> {
  late final _transfer = SettingsTransferService(
    controller: widget.service.controller,
    account: widget.service,
    webDav: widget.service.webDav,
  );
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false, _checking = false, _showPassword = false;
  String? _feedback;
  bool _failed = false;
  int _connectionsRevision = 0;
  bool _waitingForCredentials = false;
  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : zh;

  @override
  void initState() {
    super.initState();
    _waitingForCredentials = !widget.service.resourceCredentialsReady;
    _username.text = !widget.service.isSignedIn && !_waitingForCredentials
        ? widget.service.webDav?.saved.username ?? ''
        : '';
    // Passwords remain in secure storage until explicitly replaced.
  }

  @override
  void didUpdateWidget(covariant AccountResourcesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_waitingForCredentials && widget.service.resourceCredentialsReady) {
      _waitingForCredentials = false;
      if (!widget.service.isSignedIn && !_saving && _username.text.isEmpty) {
        _username.text = widget.service.webDav?.saved.username ?? '';
      }
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    final service = widget.service;
    if (_saving || _checking || service.isBusy) return;
    if (!clear && !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      await service.saveGuestResourceCredentials(
        username: clear ? '' : _username.text,
        password: clear ? '' : _password.text,
      );
      if (!mounted) return;
      _password.clear();
      if (clear) _username.clear();
      setState(() {
        _failed = false;
        _feedback = clear
            ? _text('已清除 WebDAV 凭据', 'WebDAV credentials cleared')
            : _text('WebDAV 凭据已保存', 'WebDAV credentials saved');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _feedback = _text('凭据保存失败，请重试', 'Could not save credentials. Retry.');
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _check() async {
    if (_checking || _saving || widget.service.isBusy) return;
    setState(() => _checking = true);
    try {
      await widget.service.controller.refreshAssetAccessStatus();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _feedback = _text('检测失败，请重试', 'Could not check access. Retry.');
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final locked = _saving || _checking || service.isBusy;
    return Column(
      key: const ValueKey('account-resources'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _text('知识库连接', 'Knowledge library'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (service.webDav != null)
              SettingsTransferMenu(
                service: _transfer,
                scope: ConfigurationScope.webDav,
                enabled: !locked,
                onApplied: () {
                  if (mounted) {
                    setState(() {
                      _feedback = null;
                      _connectionsRevision++;
                    });
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: UiTokens.itemGap),
        ResourceAccessSummary(controller: service.controller),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('account-check-resources'),
            onPressed: locked ? null : _check,
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check_rounded),
            label: Text(_text('检测资源访问', 'Check resource access')),
          ),
        ),
        NasConnectionSection(
          key: ValueKey('nas-$_connectionsRevision'),
          service: service,
          expanded: widget.expanded,
        ),
        if (!service.isSignedIn && service.webDav != null)
          ExpansionTile(
            key: const ValueKey('account-guest-webdav'),
            title: Text(_text('仅使用 WebDAV', 'Use WebDAV only')),
            subtitle: Text(_text('无需登录群晖账号', 'No Synology sign-in needed')),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: UiTokens.itemGap),
            maintainState: true,
            children: [
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const ValueKey('account-webdav-username'),
                      controller: _username,
                      enabled: !locked,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: _text('WebDAV 账号', 'WebDAV username'),
                      ),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? _text('请输入账号', 'Enter a username')
                          : null,
                    ),
                    const SizedBox(height: UiTokens.itemGap),
                    TextFormField(
                      key: const ValueKey('account-webdav-password'),
                      controller: _password,
                      enabled: !locked,
                      obscureText: !_showPassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: _text('WebDAV 密码', 'WebDAV password'),
                        suffixIcon: IconButton(
                          tooltip: _text(
                            _showPassword ? '隐藏密码' : '显示密码',
                            _showPassword ? 'Hide password' : 'Show password',
                          ),
                          onPressed: locked
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
                      validator: (v) => (v?.isEmpty ?? true)
                          ? _text('请输入密码', 'Enter a password')
                          : null,
                    ),
                    const SizedBox(height: UiTokens.itemGap),
                    Wrap(
                      spacing: UiTokens.itemGap,
                      children: [
                        FilledButton(
                          key: const ValueKey('account-save-webdav'),
                          onPressed: locked ? null : () => _save(),
                          child: Text(
                            _text('保存 WebDAV 凭据', 'Save WebDAV credentials'),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('account-clear-webdav'),
                          onPressed:
                              locked ||
                                  (!service.resourceCredentialsReady &&
                                      service.error == null)
                              ? null
                              : () => _save(clear: true),
                          child: Text(_text('清除凭据', 'Clear credentials')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (_feedback != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _feedback!,
              style: TextStyle(
                color: _failed ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
      ],
    );
  }
}
