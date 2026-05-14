import 'package:flutter/material.dart';

import '../../models/ai_api_config.dart';
import '../../models/asset_source_config.dart';
import '../../models/app_language.dart';
import '../../models/connectivity_status.dart';
import '../../models/color_scheme_option.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';

class LanguageSheet extends StatefulWidget {
  const LanguageSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<LanguageSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late List<AssetSourceConfig> _assetSourceConfigs;
  bool _isTesting = false;
  bool _isTestingAssets = false;
  String? _lastTestMessage;
  bool? _lastTestSucceeded;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.aiApiConfig;
    _nameController = TextEditingController(text: config.name);
    _urlController = TextEditingController(text: config.baseUrl);
    _keyController = TextEditingController(text: config.apiKey);
    _assetSourceConfigs = widget.controller.assetSourceConfigs;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final copy = controller.copy;
        final palette = controller.palette;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: palette.homeTextPrimary.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.languageTitle),
                  const SizedBox(height: 12),
                  _SectionCard(
                    palette: palette,
                    child: Column(
                      children: <Widget>[
                        _ChoiceTile(
                          palette: palette,
                          title: '简体中文',
                          subtitle: '默认语言，适合这版首发原型',
                          selected: controller.language == AppLanguage.zhHans,
                          onTap: () =>
                              controller.setLanguage(AppLanguage.zhHans),
                        ),
                        const SizedBox(height: 12),
                        _ChoiceTile(
                          palette: palette,
                          title: 'English',
                          subtitle:
                              'Useful for demos, sharing, and API testing later',
                          selected: controller.language == AppLanguage.en,
                          onTap: () => controller.setLanguage(AppLanguage.en),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.colorSchemeTitle),
                  const SizedBox(height: 12),
                  _SectionCard(
                    palette: palette,
                    child: Column(
                      children: <Widget>[
                        _ChoiceTile(
                          palette: palette,
                          title: copy.colorSchemeName(
                            ColorSchemeOption.classic,
                          ),
                          subtitle: '保留当前默认深色方案',
                          selected:
                              controller.colorScheme ==
                              ColorSchemeOption.classic,
                          onTap: () => controller.setColorScheme(
                            ColorSchemeOption.classic,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ChoiceTile(
                          palette: palette,
                          title: copy.colorSchemeName(
                            ColorSchemeOption.gradientBluePink,
                          ),
                          subtitle: '使用蓝粉渐变参考图风格',
                          selected:
                              controller.colorScheme ==
                              ColorSchemeOption.gradientBluePink,
                          onTap: () => controller.setColorScheme(
                            ColorSchemeOption.gradientBluePink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.assetPriorityTitle),
                  const SizedBox(height: 8),
                  Text(
                    copy.assetPriorityHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.homeTextPrimary.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    palette: palette,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _assetSourceConfigs.length,
                          onReorder: _reorderSources,
                          itemBuilder: (context, index) {
                            final item = _assetSourceConfigs[index];
                            return Container(
                              key: ValueKey(item.id),
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: palette.homeSurface,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: palette.accentPrimary
                                      .withValues(alpha: 0.16),
                                  foregroundColor: palette.accentPrimary,
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  item.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                subtitle: Text(
                                  item.address,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: palette.homeTextPrimary
                                            .withValues(alpha: 0.72),
                                      ),
                                ),
                                trailing: ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: palette.homeTextPrimary.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isTestingAssets ? null : _testAssets,
                            child: Text(
                              _isTestingAssets ? '...' : copy.assetTest,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.aiApiTitle),
                  const SizedBox(height: 12),
                  _SectionCard(
                    palette: palette,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _ApiField(
                          label: copy.aiApiNameLabel,
                          controller: _nameController,
                        ),
                        const SizedBox(height: 12),
                        _ApiField(
                          label: copy.aiApiUrlLabel,
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 12),
                        _ApiField(
                          label: copy.aiApiKeyLabel,
                          controller: _keyController,
                          obscureText: true,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: FilledButton(
                                onPressed: _saveConfig,
                                child: Text(copy.aiApiSave),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _resetDefault,
                                child: Text(copy.aiApiReset),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isTesting ? null : _testConfig,
                            child: Text(_isTesting ? '...' : copy.aiApiTest),
                          ),
                        ),
                        if (_lastTestMessage != null) ...<Widget>[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (_lastTestSucceeded ?? false)
                                  ? Colors.green.withValues(alpha: 0.14)
                                  : Colors.red.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: (_lastTestSucceeded ?? false)
                                    ? Colors.green.withValues(alpha: 0.32)
                                    : Colors.red.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Text(
                              _lastTestMessage!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: palette.homeTextPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveConfig() async {
    final controller = widget.controller;
    final copy = controller.copy;
    final next = AiApiConfig.defaultMimo.copyWith(
      name: _nameController.text.trim().isEmpty
          ? AiApiConfig.defaultMimo.name
          : _nameController.text.trim(),
      baseUrl: _urlController.text.trim().isEmpty
          ? AiApiConfig.defaultMimo.baseUrl
          : _urlController.text.trim(),
      apiKey: _keyController.text.trim().isEmpty
          ? AiApiConfig.defaultMimo.apiKey
          : _keyController.text.trim(),
    );
    await controller.saveAiApiConfig(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastTestMessage = null;
      _lastTestSucceeded = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(copy.aiApiSaved)));
  }

  void _resetDefault() {
    final config = AiApiConfig.defaultMimo;
    _nameController.text = config.name;
    _urlController.text = config.baseUrl;
    _keyController.text = config.apiKey;
    _saveConfig();
  }

  Future<void> _testConfig() async {
    final controller = widget.controller;
    final config = AiApiConfig.defaultMimo.copyWith(
      name: _nameController.text.trim().isEmpty
          ? AiApiConfig.defaultMimo.name
          : _nameController.text.trim(),
      baseUrl: _urlController.text.trim().isEmpty
          ? AiApiConfig.defaultMimo.baseUrl
          : _urlController.text.trim(),
      apiKey: _keyController.text.trim().isEmpty
          ? AiApiConfig.defaultMimo.apiKey
          : _keyController.text.trim(),
    );
    setState(() => _isTesting = true);
    try {
      final result = await controller.testAiApiConfig(config);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastTestMessage = result;
        _lastTestSucceeded = result == controller.copy.aiApiTestSuccess;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastTestMessage = '$error';
        _lastTestSucceeded = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _reorderSources(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final next = List<AssetSourceConfig>.from(_assetSourceConfigs);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    setState(() {
      _assetSourceConfigs = next;
    });
    await widget.controller.saveAssetSourceConfigs(next);
  }

  Future<void> _testAssets() async {
    setState(() => _isTestingAssets = true);
    try {
      await widget.controller.refreshAssetAccessStatus();
      if (!mounted) {
        return;
      }
      final statuses = widget.controller.assetSourceStatuses;
      final lines = _assetSourceConfigs
          .map((source) {
            final status = statuses[source.id];
            final stateLabel = _stateLabel(status?.state);
            return '${source.name}: $stateLabel${status == null ? '' : ' · ${status.message}'}';
          })
          .join('\n');
      final hasFailure = _assetSourceConfigs.any((source) {
        final status = statuses[source.id];
        return status == null || status.state == ConnectivityState.failure;
      });
      final hasSuccess = _assetSourceConfigs.any((source) {
        final status = statuses[source.id];
        return status?.state == ConnectivityState.success;
      });
      showDialog<void>(
        context: context,
        builder: (context) {
          final palette = widget.controller.palette;
          return AlertDialog(
            title: Text(widget.controller.copy.assetStatusDialogTitle),
            content: Text(
              lines,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.homeTextPrimary.withValues(alpha: 0.88),
                height: 1.5,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.controller.copy.dialogClose),
              ),
            ],
          );
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.controller.copy.assetTestDone),
          backgroundColor: hasFailure
              ? (hasSuccess ? Colors.orange.shade700 : Colors.red.shade600)
              : Colors.green,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isTestingAssets = false);
      }
    }
  }

  String _stateLabel(ConnectivityState? state) {
    if (state == null) {
      return '未检测';
    }
    if (state == ConnectivityState.success) {
      return '成功';
    }
    if (state == ConnectivityState.failure) {
      return '失败';
    }
    if (state == ConnectivityState.warning) {
      return '受限';
    }
    return '未检测';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.palette, required this.child});

  final AppPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.cardBorder),
      ),
      child: child,
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedBackground = selected
        ? palette.accentPrimary.withValues(alpha: 0.16)
        : palette.homeSurface;
    final selectedForeground =
        ThemeData.estimateBrightnessForColor(selectedBackground) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF173D57);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selectedBackground,
          border: Border.all(
            color: selected ? palette.accentPrimary : palette.cardBorder,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selected
                          ? selectedForeground
                          : palette.homeTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? selectedForeground.withValues(alpha: 0.84)
                          : palette.homeTextPrimary.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected
                  ? palette.accentPrimary
                  : palette.homeTextPrimary.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiField extends StatelessWidget {
  const _ApiField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFB1C6D8),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: const TextStyle(
            color: Color(0xFF183D57),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: const InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintStyle: TextStyle(color: Color(0xFF7B99AD)),
          ),
        ),
      ],
    );
  }
}
