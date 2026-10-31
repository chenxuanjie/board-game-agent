import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webdav_settings/webdav_settings.dart';
import '../../app/state/app_controller.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/ui_tokens.dart';
import '../../features/assistant/models/ai_api_config.dart';
import '../../features/settings/models/configuration_transfer.dart';
import '../../features/settings/services/settings_transfer_service.dart';

class SettingsTransferMenu extends StatelessWidget {
  const SettingsTransferMenu({
    super.key,
    required this.service,
    this.scope = ConfigurationScope.all,
    this.onApplied,
    this.enabled = true,
  });
  final SettingsTransferService service;
  final ConfigurationScope scope;
  final VoidCallback? onApplied;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final copy = service.controller.copy;
    return PopupMenuButton<bool>(
      key: ValueKey('settings-transfer-menu-${scope.name}'),
      enabled: enabled && !service.isBusy,
      tooltip: copy.localized('导入 / 导出', 'Import / Export'),
      icon: Icon(
        scope == ConfigurationScope.all
            ? Icons.import_export_rounded
            : Icons.more_horiz_rounded,
      ),
      onSelected: (export) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsTransferScreen(
            service: service,
            initialScope: scope,
            initialExport: export,
            onApplied: onApplied,
          ),
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: false,
          child: Text(copy.localized('粘贴导入', 'Paste to import')),
        ),
        PopupMenuItem(
          value: true,
          child: Text(copy.localized('复制配置', 'Copy configuration')),
        ),
      ],
    );
  }
}

class SettingsTransferScreen extends StatefulWidget {
  const SettingsTransferScreen({
    super.key,
    required this.service,
    this.initialScope = ConfigurationScope.all,
    this.initialExport = false,
    this.onApplied,
  });
  final SettingsTransferService service;
  final ConfigurationScope initialScope;
  final bool initialExport;
  final VoidCallback? onApplied;
  @override
  State<SettingsTransferScreen> createState() => _SettingsTransferScreenState();
}

class _SettingsTransferScreenState extends State<SettingsTransferScreen> {
  final _input = TextEditingController();
  final _exportText = TextEditingController();
  final _fields = <String, TextEditingController>{};
  final _assignments = <int, String>{};
  ConfigurationImport? _parsed;
  late bool _exporting = widget.initialExport;
  late ConfigurationScope _scope = service.webDav == null
      ? ConfigurationScope.ai
      : widget.initialScope;
  bool _readable = false;
  bool _includeSecrets = false;
  bool _showSecrets = false;
  bool _ai = false;
  bool _dav = false;
  bool _busy = false;
  bool _editInput = true;
  bool _applied = false;
  bool _explicitAiKey = false;
  bool _explicitDavPassword = false;
  bool _explicitDavUsername = false;
  String? _feedback;
  bool _failed = false;
  SettingsTransferService get service => widget.service;

  @override
  void dispose() {
    _input.dispose();
    _exportText.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _notice(String text, {bool error = false}) {
    if (mounted) {
      setState(() {
        _feedback = text;
        _failed = error;
      });
    }
  }

  String _error(Object error) => error is ConfigurationTransferException
      ? error.message(service.controller.copy)
      : service.controller.copy.localized(
          '操作未完成，请重试。',
          'The operation did not complete. Try again.',
        );

  void _recognize() {
    try {
      final parsed = ConfigurationTransfer.parse(_input.text);
      _assignments.clear();
      _parsed = parsed;
      _explicitAiKey = parsed.ai.containsKey('apiKey');
      _explicitDavPassword = parsed.webDav.containsKey('password');
      _explicitDavUsername = parsed.webDav.containsKey('username');
      _populate(
        'ai',
        ConfigurationTransfer.prepareAi(
          parsed.ai,
          service.controller.aiApiConfig,
        ),
      );
      _populate(
        'webdav',
        ConfigurationTransfer.prepareWebDav(
          parsed.webDav,
          service.webDav?.saved ?? const WebDavSettings(),
        ),
      );
      setState(() {
        _ai = parsed.ai.isNotEmpty;
        _dav = service.webDav != null && parsed.webDav.isNotEmpty;
        _editInput = false;
        _applied = false;
        _feedback = null;
      });
    } catch (error) {
      _parsed = null;
      _notice(_error(error), error: true);
    }
  }

  void _populate(String group, Map<String, String> values) {
    for (final entry in values.entries) {
      (_fields['$group.${entry.key}'] ??= TextEditingController()).text =
          entry.value;
    }
  }

  Map<String, String> _values(String group, List<String> keys) => {
    for (final key in keys) key: _fields['$group.$key']!.text,
  };

  Future<void> _paste() async {
    setState(() => _busy = true);
    try {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      if (value?.text?.trim().isNotEmpty != true) {
        _notice(
          service.controller.copy.localized(
            '剪贴板没有文本，也可以手动粘贴。',
            'No clipboard text. You can paste manually.',
          ),
          error: true,
        );
        return;
      }
      _input.text = value!.text!;
      _recognize();
    } catch (_) {
      _notice(
        service.controller.copy.localized(
          '无法读取剪贴板，请手动粘贴。',
          'Clipboard access failed. Paste manually.',
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _assign(int index, String? target) {
    if (target == null) return;
    setState(() {
      final previous = _assignments[index];
      var restoredPrevious = false;
      if (previous != null &&
          previous != 'ignore' &&
          previous != target &&
          _fields[previous]!.text == _parsed!.unassigned[index].value) {
        final parts = previous.split('.');
        final original = parts.first == 'ai'
            ? ConfigurationTransfer.prepareAi(
                _parsed!.ai,
                service.controller.aiApiConfig,
              )
            : ConfigurationTransfer.prepareWebDav(
                _parsed!.webDav,
                service.webDav?.saved ?? const WebDavSettings(),
              );
        _fields[previous]!.text = original[parts.last]!;
        restoredPrevious = true;
      }
      _assignments[index] = target;
      if (restoredPrevious) {
        // Ignoring a previously assigned credential must also remove its
        // explicit-credential status before a later URL edit.
        if (previous == 'ai.apiKey') {
          _explicitAiKey =
              _parsed!.ai.containsKey('apiKey') ||
              _assignments.values.contains('ai.apiKey');
        } else if (previous == 'webdav.password') {
          _explicitDavPassword =
              _parsed!.webDav.containsKey('password') ||
              _assignments.values.contains('webdav.password');
        } else if (previous == 'webdav.username') {
          _explicitDavUsername =
              _parsed!.webDav.containsKey('username') ||
              _assignments.values.contains('webdav.username');
        }
      }
      _applied = false;
      _feedback = null;
      _ai =
          _ai &&
          (_parsed!.ai.isNotEmpty ||
              _assignments.values.any((item) => item.startsWith('ai.')));
      _dav =
          service.webDav != null &&
          _dav &&
          (_parsed!.webDav.isNotEmpty ||
              _assignments.values.any((item) => item.startsWith('webdav.')));
      if (target == 'ignore') return;
      final parts = target.split('.');
      final value = _parsed!.unassigned[index].value;
      _fields[target]!.text = value;
      if (parts.first == 'ai') {
        _ai = true;
      } else {
        _dav = true;
      }
      _fieldChanged(parts.first, parts.last);
    });
  }

  void _fieldChanged(String group, String key) {
    _applied = false;
    _feedback = null;
    if (group == 'ai' && key == 'apiKey') _explicitAiKey = true;
    if (group == 'webdav' && key == 'password') _explicitDavPassword = true;
    if (group == 'webdav' && key == 'username') _explicitDavUsername = true;
    if (key != 'baseUrl') return;
    if (group == 'ai' &&
        !_explicitAiKey &&
        _fields['ai.baseUrl']!.text.trim() !=
            service.controller.aiApiConfig.baseUrl.trim()) {
      _fields['ai.apiKey']!.clear();
    }
    if (group == 'webdav' &&
        _fields['webdav.baseUrl']!.text.trim() !=
            service.webDav?.saved.baseUrl.trim()) {
      if (!_explicitDavPassword) _fields['webdav.password']!.clear();
      if (!_explicitDavUsername) _fields['webdav.username']!.clear();
    }
  }

  Future<void> _apply() async {
    if (_busy || _parsed == null) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final ai = _ai
          ? ConfigurationTransfer.aiConfig(
              _values('ai', ConfigurationTransfer.aiFields),
            )
          : null;
      WebDavSettings? dav;
      if (_dav) {
        final values = _values('webdav', ConfigurationTransfer.webDavFields);
        ConfigurationTransfer.validateUrl(values['baseUrl']!);
        if (values['username']!.trim().isNotEmpty &&
            values['password']!.isEmpty) {
          throw const ConfigurationTransferException(
            '请补充 WebDAV 密码；新地址不会沿用旧密码。',
            'Enter the WebDAV password. Old passwords are not reused for a new URL.',
          );
        }
        dav = WebDavSettings(
          baseUrl: values['baseUrl']!,
          username: values['username']!,
          password: values['password']!,
        );
      }
      await service.apply(ai: ai, dav: dav);
      widget.onApplied?.call();
      if (!mounted) return;
      setState(() => _applied = true);
      _notice(
        service.controller.copy.localized(
          _dav ? '配置已保存。WebDAV 检测后启用。' : 'AI 配置已保存，下次发送生效。',
          _dav
              ? 'Saved. Test WebDAV to enable it.'
              : 'AI settings saved for your next message.',
        ),
      );
    } catch (error) {
      _notice(_error(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test(bool dav) async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      if (dav) {
        final result = await service.webDav!.testConnection();
        if (result.isSuccess) {
          await service.webDav!.enableWebDav();
          widget.onApplied?.call();
          _notice(
            service.controller.copy.localized(
              'WebDAV 已连接并启用。',
              'WebDAV connected and enabled.',
            ),
          );
        } else {
          _notice(
            service.controller.copy.localized(
              'WebDAV 检测失败，配置已保留，可以重试。',
              'WebDAV check failed. Settings were retained; try again.',
            ),
            error: true,
          );
        }
      } else {
        final result = await service.controller.testAiApiConfig(
          service.controller.aiApiConfig,
        );
        _notice(
          result,
          error: result != service.controller.copy.aiApiTestSuccess,
        );
      }
    } catch (_) {
      _notice(
        service.controller.copy.localized(
          '连接检测失败，配置已保留，可以重试。',
          'Connection check failed. Settings were retained; try again.',
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    setState(() => _busy = true);
    try {
      await Clipboard.setData(ClipboardData(text: _exportText.text));
      _notice(
        service.controller.copy.localized('配置已复制。', 'Configuration copied.'),
      );
    } catch (_) {
      _notice(
        service.controller.copy.localized(
          '复制失败，可以选中文本手动复制。',
          'Copy failed. Select the text to copy manually.',
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = service.controller.copy;
    final palette = AppPalette.of(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        key: const ValueKey('settings-transfer-screen'),
        appBar: AppBar(
          title: Text(copy.localized('配置导入 / 导出', 'Import / Export settings')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(UiTokens.pageInset),
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(copy.localized('导入', 'Import')),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(copy.localized('导出', 'Export')),
                    ),
                  ],
                  selected: {_exporting},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _exporting = value.first;
                          _feedback = null;
                        }),
                ),
                const SizedBox(height: 20),
                if (_exporting) ..._exportContent() else ..._importContent(),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_feedback != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _feedback!,
                        key: const ValueKey('transfer-feedback'),
                        style: TextStyle(
                          color: _failed ? palette.error : palette.success,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _importContent() {
    final copy = service.controller.copy;
    final unresolved = _parsed?.unassigned.length ?? 0;
    return [
      if (_editInput) ...[
        TextField(
          key: const ValueKey('transfer-input'),
          controller: _input,
          enabled: !_busy,
          onChanged: (_) => setState(() {
            _parsed = null;
            _assignments.clear();
            _applied = false;
            _feedback = null;
          }),
          minLines: 4,
          maxLines: 8,
          maxLength: ConfigurationTransfer.maxLength,
          decoration: InputDecoration(
            hintText: copy.localized(
              '粘贴配置码，或带地址、模型、账号等字段的文本',
              'Paste a configuration code or labeled connection details',
            ),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('transfer-paste'),
              onPressed: _busy ? null : _paste,
              icon: const Icon(Icons.content_paste_rounded),
              label: Text(copy.localized('从剪贴板粘贴', 'Paste clipboard')),
            ),
            FilledButton(
              key: const ValueKey('transfer-recognize'),
              onPressed: _busy ? null : _recognize,
              child: Text(copy.localized('识别配置', 'Recognize')),
            ),
          ],
        ),
      ] else
        TextButton.icon(
          onPressed: _busy ? null : () => setState(() => _editInput = true),
          icon: const Icon(Icons.edit_outlined),
          label: Text(copy.localized('编辑粘贴内容', 'Edit pasted text')),
        ),
      if (_parsed != null) ...[
        const SizedBox(height: 16),
        Text(
          copy.localized('确认要更新的配置', 'Review settings to update'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _showSecrets,
          onChanged: (value) => setState(() => _showSecrets = value),
          title: Text(copy.localized('显示密钥和密码', 'Show keys and passwords')),
        ),
        if (_parsed!.ai.isNotEmpty ||
            _assignments.values.any((item) => item.startsWith('ai.')))
          _configurationCard(false),
        if (_parsed!.webDav.isNotEmpty ||
            _assignments.values.any((item) => item.startsWith('webdav.')))
          _configurationCard(true),
        for (var index = 0; index < unresolved; index++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${copy.localized('待确认', 'Needs review')} · ${_parsed!.unassigned[index].label}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _showSecrets ? _parsed!.unassigned[index].value : '••••••',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('transfer-assign-$index'),
                    initialValue: _assignments[index],
                    isExpanded: true,
                    hint: Text(
                      copy.localized('指定用途或忽略', 'Assign a field or ignore'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'ignore',
                        child: Text(copy.localized('忽略此项', 'Ignore this item')),
                      ),
                      for (final group in [
                        'ai',
                        if (service.webDav != null) 'webdav',
                      ])
                        for (final key
                            in group == 'ai'
                                ? ConfigurationTransfer.aiFields
                                : ConfigurationTransfer.webDavFields)
                          DropdownMenuItem(
                            value: '$group.$key',
                            child: Text(
                              '${group == 'ai' ? 'AI' : 'WebDAV'} · ${ConfigurationTransfer.label(key, copy)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: _busy
                        ? null
                        : (target) => _assign(index, target),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('transfer-apply'),
          onPressed:
              _busy ||
                  _applied ||
                  (!_ai && !_dav) ||
                  _assignments.length < unresolved
              ? null
              : _apply,
          icon: const Icon(Icons.check_rounded),
          label: Text(copy.localized('应用配置', 'Apply settings')),
        ),
        if (_applied)
          Wrap(
            spacing: 10,
            children: [
              if (_ai)
                TextButton(
                  onPressed: _busy ? null : () => _test(false),
                  child: Text(copy.localized('检测 AI', 'Check AI')),
                ),
              if (_dav)
                TextButton(
                  key: const ValueKey('transfer-test-webdav'),
                  onPressed: _busy ? null : () => _test(true),
                  child: Text(
                    copy.localized('检测并启用 WebDAV', 'Test & enable WebDAV'),
                  ),
                ),
            ],
          ),
      ],
    ];
  }

  Widget _configurationCard(bool dav) {
    final group = dav ? 'webdav' : 'ai';
    final copy = service.controller.copy;
    final available = !dav || service.webDav != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                key: ValueKey('transfer-select-$group'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  dav ? 'WebDAV' : copy.localized('AI 配置', 'AI settings'),
                ),
                subtitle: available
                    ? null
                    : Text(
                        copy.localized(
                          '此入口未连接 WebDAV 设置',
                          'WebDAV settings are unavailable here',
                        ),
                      ),
                value: dav ? _dav : _ai,
                onChanged: _busy || !available
                    ? null
                    : (value) => setState(() {
                        if (dav) {
                          _dav = value!;
                        } else {
                          _ai = value!;
                        }
                        _applied = false;
                      }),
              ),
              if (available && (dav ? _dav : _ai)) ...[
                for (final key
                    in dav
                        ? ConfigurationTransfer.webDavFields
                        : ['name', 'baseUrl', 'apiKey', 'model'])
                  _field(group, key),
                if (!dav)
                  ExpansionTile(
                    title: Text(copy.localized('高级配置', 'Advanced settings')),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      for (final key in [
                        'apiKeyHeader',
                        'chatPath',
                        'reasoningEffort',
                        'responseSpeed',
                      ])
                        _field(group, key),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String group, String key) {
    if (group == 'ai' && ['reasoningEffort', 'responseSpeed'].contains(key)) {
      final copy = service.controller.copy;
      final values = key == 'reasoningEffort'
          ? {
              for (final effort in AiReasoningEffort.values)
                effort.name: copy.aiApiReasoningEffortName(effort),
            }
          : {
              for (final speed in AiResponseSpeed.selectableValues)
                speed.name: copy.aiApiResponseSpeedName(speed),
            };
      final current = _fields['$group.$key']!.text;
      // Preserve unrecognized pasted values until the user explicitly replaces them.
      if (!values.containsKey(current)) {
        values[current] = '$current (${copy.localized('请确认', 'Review')})';
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey('transfer-$group-$key'),
          initialValue: current,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: ConfigurationTransfer.label(key, copy),
          ),
          items: [
            for (final entry in values.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _fields['$group.$key']!.text = value!;
                  _fieldChanged(group, key);
                }),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey('transfer-$group-$key'),
        controller: _fields['$group.$key'],
        enabled: !_busy,
        obscureText: !_showSecrets && ['apiKey', 'password'].contains(key),
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() => _fieldChanged(group, key)),
        decoration: InputDecoration(
          labelText: ConfigurationTransfer.label(key, service.controller.copy),
        ),
      ),
    );
  }

  List<Widget> _exportContent() {
    final copy = service.controller.copy;
    final payload = ConfigurationTransfer.payload(
      service.controller.aiApiConfig,
      service.webDav?.saved,
      _scope,
      includeSecrets: _includeSecrets,
    );
    final text = _readable
        ? ConfigurationTransfer.readable(payload, copy)
        : ConfigurationTransfer.encode(payload);
    if (_exportText.text != text) _exportText.text = text;
    return [
      Text(
        copy.localized('导出已保存配置', 'Export saved settings'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final scope in [
            ConfigurationScope.ai,
            if (service.webDav != null) ConfigurationScope.webDav,
            if (service.webDav != null) ConfigurationScope.all,
          ])
            ChoiceChip(
              key: ValueKey('transfer-export-${scope.name}'),
              label: Text(
                scope == ConfigurationScope.ai
                    ? 'AI'
                    : scope == ConfigurationScope.webDav
                    ? 'WebDAV'
                    : copy.localized('两项一起', 'Both'),
              ),
              selected: _scope == scope,
              onSelected: _busy
                  ? null
                  : (_) => setState(() {
                      _scope = scope;
                      _feedback = null;
                    }),
            ),
        ],
      ),
      SwitchListTile(
        key: const ValueKey('transfer-include-secrets'),
        contentPadding: EdgeInsets.zero,
        title: Text(copy.localized('包含密钥和密码', 'Include keys and passwords')),
        subtitle: _includeSecrets
            ? Text(
                copy.localized(
                  '含凭据，仅分享给可信任的人；配置码不是加密。',
                  'Contains credentials. Share only with trusted people; codes are not encrypted.',
                ),
              )
            : null,
        value: _includeSecrets,
        onChanged: _busy
            ? null
            : (value) => setState(() {
                _includeSecrets = value;
                _feedback = null;
              }),
      ),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: Text(copy.localized('配置码', 'Code')),
          ),
          ButtonSegment(
            value: true,
            label: Text(copy.localized('可读文本', 'Text')),
          ),
        ],
        selected: {_readable},
        onSelectionChanged: _busy
            ? null
            : (value) => setState(() => _readable = value.first),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('transfer-export-preview'),
        controller: _exportText,
        readOnly: true,
        minLines: 4,
        maxLines: 8,
        decoration: const InputDecoration(),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('transfer-copy'),
        onPressed: _busy ? null : _copy,
        icon: const Icon(Icons.copy_rounded),
        label: Text(copy.localized('复制配置', 'Copy configuration')),
      ),
    ];
  }
}
