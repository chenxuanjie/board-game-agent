import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/identity/models/account_configuration.dart';
import '../../features/identity/services/account_service.dart';

/// Public NAS connection options shared by sign-in and knowledge access.
class NasConnectionSection extends StatefulWidget {
  const NasConnectionSection({
    super.key,
    required this.service,
    this.expanded = false,
  });
  final AccountService service;
  final bool expanded;
  @override
  State<NasConnectionSection> createState() => _NasConnectionSectionState();
}

class _AddressDraft {
  _AddressDraft(NasServerAddress server)
    : id = server.id,
      name = server.name,
      address = TextEditingController(text: server.address),
      login = TextEditingController(text: '${server.loginPort}'),
      dav = TextEditingController(text: '${server.webDavPort}');
  final String id, name;
  final TextEditingController address, login, dav;
  NasServerAddress get value => NasServerAddress(
    id: id,
    name: name,
    address: address.text,
    loginPort: int.parse(login.text),
    webDavPort: int.parse(dav.text),
  );
  void dispose() {
    address.dispose();
    login.dispose();
    dav.dispose();
  }
}

class _NasConnectionSectionState extends State<NasConnectionSection> {
  final _form = GlobalKey<FormState>();
  final _folder = TextEditingController();
  List<_AddressDraft>? _drafts;
  bool _busy = false;
  String? _feedback;
  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : zh;
  @override
  void dispose() {
    for (final d in _drafts ?? <_AddressDraft>[]) {
      d.dispose();
    }
    _folder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || widget.service.isBusy || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await widget.service.saveConfiguration(
        widget.service.configuration!.edited(
          servers: _drafts!.map((d) => d.value).toList(),
          folder: _folder.text,
        ),
      );
      if (widget.service.error != null) throw StateError('Connection pending');
      if (mounted) {
        setState(() => _feedback = _text('连接设置已保存', 'Connection saved'));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback = _text(
            '保存未完成，请检查地址后重试',
            'Could not save. Check addresses and retry',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_busy || widget.service.isBusy) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;
    final before = List<_AddressDraft>.from(_drafts!);
    final next = List<_AddressDraft>.from(before);
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() {
      _drafts = next;
      _busy = true;
      _feedback = null;
    });
    try {
      final saved = widget.service.configuration!;
      await widget.service.saveConfiguration(
        saved.edited(
          servers: next
              .map((d) => saved.servers.firstWhere((s) => s.id == d.id))
              .toList(),
          folder: saved.storageFolder,
        ),
      );
      if (widget.service.error != null) throw StateError('Connection pending');
    } catch (_) {
      if (mounted) {
        setState(() {
          _drafts = before;
          _feedback = _text('顺序保存失败，请重试', 'Could not save order. Retry');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final config = service.configuration;
    if (config == null) return const SizedBox.shrink();
    _drafts ??= config.servers.map(_AddressDraft.new).toList();
    if (_folder.text.isEmpty) _folder.text = config.storageFolder;
    final locked = _busy || service.isBusy;
    return ExpansionTile(
      key: const ValueKey('account-connections'),
      initiallyExpanded: widget.expanded,
      tilePadding: EdgeInsets.zero,
      maintainState: true,
      title: Text(_text('NAS 与 WebDAV', 'NAS & WebDAV')),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (service.isSignedIn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _text(
                      '若要修改 NAS 基地址，请退出登录或切换账号。',
                      'To change the NAS base URL, sign out or switch accounts.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ReorderableListView.builder(
                key: const ValueKey('nas-address-order'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _drafts!.length,
                onReorder: _reorder,
                itemBuilder: (context, index) {
                  final d = _drafts![index];
                  return Padding(
                    key: ValueKey(d.id),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${index + 1}. ${d.name}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              enabled: !locked,
                              child: Tooltip(
                                message: _text('拖动排序', 'Drag to reorder'),
                                child: SizedBox.square(
                                  dimension: 48,
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            PopupMenuButton<int>(
                              enabled: !locked,
                              tooltip: _text('移动地址', 'Move address'),
                              onSelected: (destination) => _reorder(
                                index,
                                destination > index
                                    ? destination + 1
                                    : destination,
                              ),
                              itemBuilder: (_) => [
                                if (index > 0)
                                  PopupMenuItem(
                                    value: index - 1,
                                    child: Text(_text('上移', 'Move up')),
                                  ),
                                if (index < _drafts!.length - 1)
                                  PopupMenuItem(
                                    value: index + 1,
                                    child: Text(_text('下移', 'Move down')),
                                  ),
                              ],
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        TextFormField(
                          key: ValueKey('nas-address-${d.id}'),
                          controller: d.address,
                          enabled: !locked,
                          readOnly: service.isSignedIn,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          validator: (value) {
                            try {
                              NasServerAddress.normalizeAddress(value ?? '');
                              return null;
                            } catch (_) {
                              return _text(
                                '只填地址，不含端口和目录',
                                'Address only, without port or folder',
                              );
                            }
                          },
                          decoration: InputDecoration(
                            labelText: _text('NAS 基地址', 'NAS base URL'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, box) {
                            Widget port(
                              TextEditingController input,
                              String label,
                              String key,
                              bool enabled,
                            ) => TextFormField(
                              key: ValueKey(key),
                              controller: input,
                              enabled: enabled,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) {
                                final n = int.tryParse(value ?? '');
                                return n != null && n > 0 && n <= 65535
                                    ? null
                                    : _text('端口 1–65535', 'Port 1–65535');
                              },
                              decoration: InputDecoration(labelText: label),
                            );
                            final login = port(
                              d.login,
                              _text('登录端口', 'Sign-in port'),
                              'nas-login-port-${d.id}',
                              !locked && !service.isSignedIn,
                            );
                            final dav = port(
                              d.dav,
                              _text('WebDAV 端口', 'WebDAV port'),
                              'nas-dav-port-${d.id}',
                              !locked,
                            );
                            return box.maxWidth < 280
                                ? Column(
                                    children: [
                                      login,
                                      const SizedBox(height: 12),
                                      dav,
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: login),
                                      const SizedBox(width: 12),
                                      Expanded(child: dav),
                                    ],
                                  );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
              TextFormField(
                key: const ValueKey('nas-resource-folder'),
                controller: _folder,
                enabled: !locked,
                autocorrect: false,
                validator: (value) {
                  try {
                    AccountConfiguration.normalizeFolder(value ?? '');
                    return null;
                  } catch (_) {
                    return _text(
                      '请输入有效目录，例如 friend',
                      'Enter a valid folder, e.g. friend',
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: _text('WebDAV 目录', 'WebDAV folder'),
                  hintText: 'friend',
                ),
              ),
              if (_feedback != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_feedback!),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('nas-connections-save'),
                onPressed: locked ? null : _save,
                child: Text(
                  _busy
                      ? _text('保存中', 'Saving')
                      : _text('保存连接', 'Save connection'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
