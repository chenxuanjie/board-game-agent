import 'package:flutter/material.dart';

import '../../models/ai_api_config.dart';
import '../../models/app_language.dart';
import '../../models/color_scheme_option.dart';
import '../../state/app_controller.dart';

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
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.aiApiConfig;
    _nameController = TextEditingController(text: config.name);
    _urlController = TextEditingController(text: config.baseUrl);
    _keyController = TextEditingController(text: config.apiKey);
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
    final controller = widget.controller;
    final copy = controller.copy;
    final palette = controller.palette;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              Text(
                copy.languageTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _LanguageOption(
                controller: controller,
                title: '简体中文',
                subtitle: '默认语言，适合这版首发原型',
                selected: controller.language == AppLanguage.zhHans,
                onTap: () => controller.setLanguage(AppLanguage.zhHans),
              ),
              const SizedBox(height: 12),
              _LanguageOption(
                controller: controller,
                title: 'English',
                subtitle: 'Useful for demos, sharing, and API testing later',
                selected: controller.language == AppLanguage.en,
                onTap: () => controller.setLanguage(AppLanguage.en),
              ),
              const SizedBox(height: 20),
              Text(
                copy.colorSchemeTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _LanguageOption(
                controller: controller,
                title: copy.colorSchemeName(ColorSchemeOption.classic),
                subtitle: '保留当前默认深色方案',
                selected: controller.colorScheme == ColorSchemeOption.classic,
                onTap: () =>
                    controller.setColorScheme(ColorSchemeOption.classic),
              ),
              const SizedBox(height: 12),
              _LanguageOption(
                controller: controller,
                title: copy.colorSchemeName(ColorSchemeOption.gradientBluePink),
                subtitle: '使用蓝粉渐变参考图风格',
                selected:
                    controller.colorScheme ==
                    ColorSchemeOption.gradientBluePink,
                onTap: () => controller.setColorScheme(
                  ColorSchemeOption.gradientBluePink,
                ),
              ),
              const SizedBox(height: 20),
              SwitchListTile.adaptive(
                value: controller.voiceReplyEnabled,
                contentPadding: EdgeInsets.zero,
                activeThumbColor: palette.accentPrimary,
                activeTrackColor: palette.accentPrimary.withValues(alpha: 0.5),
                title: Text(copy.voiceReplyTitle),
                subtitle: Text(
                  copy.voiceReplyHint,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.homeTextPrimary.withValues(alpha: 0.72),
                  ),
                ),
                onChanged: controller.setVoiceReplyEnabled,
              ),
              const SizedBox(height: 20),
              Text(
                copy.aiApiTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
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
            ],
          ),
        ),
      ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final AppController controller;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = controller.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: selected
              ? palette.accentPrimary.withValues(alpha: 0.12)
              : palette.cardSurface,
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
                      color: palette.homeTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.homeTextPrimary.withValues(alpha: 0.72),
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
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(labelText: label),
    );
  }
}
