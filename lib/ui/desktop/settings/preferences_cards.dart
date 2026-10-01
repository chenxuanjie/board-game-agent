part of '../settings_pane.dart';

class _GeneralCard extends StatelessWidget {
  const _GeneralCard({
    required this.controller,
    required this.saving,
    required this.onLanguage,
    required this.onStartupUpdates,
    required this.onVoiceReply,
  });

  final AppController controller;
  final bool saving;
  final ValueChanged<AppLanguage> onLanguage;
  final ValueChanged<bool> onStartupUpdates;
  final ValueChanged<bool> onVoiceReply;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    return _SettingsCard(
      icon: Icons.tune_rounded,
      title: copy.localized('通用', 'General'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _FieldLabel(label: copy.localized('语言', 'Language')),
          SizedBox(height: _px(context, 5)),
          SizedBox(
            height: _px(context, 42),
            child: Theme(
              data: _dropdownTheme(context),
              child: DropdownButtonFormField<AppLanguage>(
                key: const ValueKey<String>('desktop-settings-language'),
                initialValue: controller.language,
                isExpanded: true,
                borderRadius: BorderRadius.circular(_px(context, 12)),
                dropdownColor: DesktopColors.card,
                decoration: _fieldDecoration(context),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: _font(context, 13),
                  color: DesktopColors.text,
                ),
                items: AppLanguage.values
                    .map(
                      (AppLanguage language) => DropdownMenuItem<AppLanguage>(
                        value: language,
                        child: _dropdownOption(
                          context,
                          language.label,
                          selected: language == controller.language,
                        ),
                      ),
                    )
                    .toList(growable: false),
                selectedItemBuilder: (context) => <Widget>[
                  for (final language in AppLanguage.values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(language.label),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) onLanguage(value);
                      },
              ),
            ),
          ),
          SizedBox(height: _px(context, 7)),
          _SettingSwitchRow(
            key: const ValueKey<String>(
              'desktop-settings-startup-update-check',
            ),
            title: copy.localized('启动时检查更新', 'Check for updates on startup'),
            subtitle: copy.localized(
              '当前更新源仅支持 Android APK',
              'The current update source supports Android APK only',
            ),
            value: controller.checkForUpdates,
            onChanged: saving ? null : onStartupUpdates,
          ),
          SizedBox(height: _px(context, 4)),
          _SettingSwitchRow(
            key: const ValueKey<String>('desktop-settings-voice-reply'),
            title: copy.localized('语音朗读', 'Voice output'),
            subtitle: controller.voiceReplyAvailable
                ? ''
                : copy.localized('当前设备不可用', 'Unavailable on this device'),
            value: controller.voiceReplyEnabled,
            onChanged: !saving && controller.voiceReplyAvailable
                ? onVoiceReply
                : null,
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.controller,
    required this.saving,
    required this.onSelectTheme,
  });

  final AppController controller;
  final bool saving;
  final ValueChanged<ColorSchemeOption> onSelectTheme;

  @override
  Widget build(BuildContext context) {
    const List<ColorSchemeOption> schemes = [
      ColorSchemeOption.warmwoodStudy,
      ColorSchemeOption.classic,
      ColorSchemeOption.sunsetCoast,
    ];
    final AppCopy copy = controller.copy;
    return _SettingsCard(
      icon: Icons.palette_outlined,
      title: copy.localized('外观与主题', 'Appearance & Theme'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (int index = 0; index < schemes.length; index++) ...<Widget>[
                if (index > 0) SizedBox(width: _px(context, 7)),
                Expanded(
                  child: _ThemePreview(
                    scheme: schemes[index],
                    selected: controller.colorScheme == schemes[index],
                    enabled: !saving,
                    label: controller.copy.colorSchemeName(schemes[index]),
                    onTap: () => onSelectTheme(schemes[index]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.scheme,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final ColorSchemeOption scheme;
  final bool selected;
  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DesktopMetrics metrics = DesktopMetricsScope.of(context);
    final AppPalette palette = PaletteRegistry.of(scheme);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: label,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(metrics.radius(9)),
            child: AnimatedContainer(
              key: ValueKey<String>('desktop-settings-theme-${scheme.code}'),
              duration: AppMotion.duration(context),
              padding: EdgeInsets.all(metrics.px(5)),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFF2E9) : DesktopColors.card,
                borderRadius: BorderRadius.circular(metrics.radius(9)),
                border: Border.all(
                  color: selected
                      ? DesktopColors.orange
                      : const Color(0x1AA76D48),
                  width: selected ? metrics.px(1.5) : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    height: metrics.px(45),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(metrics.radius(5)),
                      child: _ThemeMiniature(palette: palette),
                    ),
                  ),
                  SizedBox(height: metrics.px(4)),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: metrics.font(11),
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: DesktopColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeMiniature extends StatelessWidget {
  const _ThemeMiniature({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.pageBackground,
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 5,
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Spacer(),
              Container(width: 7, height: 4, color: palette.textSecondary),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: <Widget>[
                Container(
                  width: 16,
                  decoration: BoxDecoration(
                    color: palette.surfaceContainer,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: palette.outline),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: ColoredBox(
                                color: palette.primaryContainer,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: ColoredBox(
                                color: palette.secondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
