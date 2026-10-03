import 'package:flutter/material.dart';
import 'package:webdav_settings/webdav_settings.dart';

import '../../core/theme/ui_tokens.dart';
import '../../features/library/models/asset_source_config.dart';
import '../../features/settings/models/configuration_transfer.dart';
import '../../features/settings/services/settings_transfer_service.dart';

/// Editable connection, shared with resource access, sync and APK updates.
class ResourceConnectionScreen extends StatefulWidget {
  const ResourceConnectionScreen({
    super.key,
    required this.service,
    this.source,
  });
  final SettingsTransferService service;
  final AssetSourceConfig? source;
  @override
  State<ResourceConnectionScreen> createState() =>
      _ResourceConnectionScreenState();
}

class _ResourceConnectionScreenState extends State<ResourceConnectionScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  bool _busy = false;
  bool _showPassword = false;
  String? _feedback;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.service.webDav!.saved;
    _url = TextEditingController(text: widget.source?.testUrl ?? saved.baseUrl);
    _username = TextEditingController(text: saved.username);
    _password = TextEditingController(text: saved.password);
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  WebDavSettings get _draft => WebDavSettings(
    mode: ExternalStorageMode.webDav,
    baseUrl: _url.text.trim(),
    username: _username.text.trim(),
    password: _password.text,
  );
  String? _validateUrl(String? value) {
    try {
      ConfigurationTransfer.validateUrl(value ?? '');
      return null;
    } catch (_) {
      return widget.service.controller.copy.localized(
        '请输入有效的 HTTP 或 HTTPS 地址',
        'Enter a valid HTTP or HTTPS URL',
      );
    }
  }

  Future<void> _act({required bool test}) async {
    if (_busy || widget.service.isBusy || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      if (test) {
        final dav = widget.service.webDav!;
        dav.updateDraft(_draft);
        final result = await dav.testConnection();
        if (mounted) {
          setState(() {
            _success = result.isSuccess;
            _feedback = result.message;
          });
        }
      } else {
        await widget.service.apply(
          dav: _draft,
          activateWebDav: true,
          resourceSource: widget.source,
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _success = false;
          _feedback = widget.service.controller.copy.localized(
            test ? '连接检测失败，请检查地址与账号后重试。' : '保存失败，请重试。',
            test
                ? 'Connection failed. Check the URL and account, then retry.'
                : 'Could not save. Retry.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.service.controller.copy;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        key: const ValueKey('resource-connection-screen'),
        appBar: AppBar(
          title: Text(
            widget.source?.name ??
                copy.localized('WebDAV 连接设置', 'WebDAV connection'),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(UiTokens.pageInset),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('resource-connection-url'),
                        controller: _url,
                        enabled: !_busy,
                        validator: _validateUrl,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: copy.localized('WebDAV 地址', 'WebDAV URL'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const ValueKey('resource-connection-username'),
                        controller: _username,
                        enabled: !_busy,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: copy.localized('账号', 'Username'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const ValueKey('resource-connection-password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: (_) =>
                            _username.text.trim().isEmpty !=
                                _password.text.isEmpty
                            ? copy.localized(
                                '账号与密码需同时填写或同时留空',
                                'Provide both username and password, or neither',
                              )
                            : null,
                        decoration: InputDecoration(
                          labelText: copy.localized('密码', 'Password'),
                          suffixIcon: IconButton(
                            tooltip: copy.localized(
                              '显示或隐藏密码',
                              'Show or hide password',
                            ),
                            onPressed: _busy
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
                      ),
                      const SizedBox(height: 16),
                      Text(
                        copy.localized(
                          '保存后用于资料访问、同步与应用更新。',
                          'Used for resources, sync and app updates after saving.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_feedback != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _feedback!,
                            key: const ValueKey('resource-connection-feedback'),
                            style: TextStyle(
                              color: _success
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const ValueKey('resource-connection-save'),
                        onPressed: _busy ? null : () => _act(test: false),
                        child: Text(
                          _busy
                              ? copy.localized('处理中', 'Working')
                              : copy.localized('保存', 'Save'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const ValueKey('resource-connection-test'),
                        onPressed: _busy ? null : () => _act(test: true),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.network_check_rounded),
                        label: Text(copy.localized('检测连接', 'Test connection')),
                      ),
                    ],
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
