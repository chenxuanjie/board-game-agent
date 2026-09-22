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
            child: DropdownButtonFormField<AppLanguage>(
              key: const ValueKey<String>('desktop-settings-language'),
              initialValue: controller.language,
              isExpanded: true,
              decoration: _fieldDecoration(context),
              style: TextStyle(
                fontSize: _font(context, 13),
                color: DesktopColors.text,
              ),
              items: AppLanguage.values
                  .map(
                    (AppLanguage language) => DropdownMenuItem<AppLanguage>(
                      value: language,
                      child: Text(language.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) onLanguage(value);
                    },
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
                ? copy.localized('可按设备能力启用', 'Available on this device')
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
    const List<ColorSchemeOption> schemes = ColorSchemeOption.values;
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
          SizedBox(height: _px(context, 12)),
          Row(
            children: <Widget>[
              Expanded(
                child: _FieldLabel(
                  label: copy.localized('主题色', 'Accent color'),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _UnavailableLabel(
                    label: copy.localized(
                      '当前版本不可调整',
                      'Not adjustable in this version',
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: _px(context, 6)),
          _DisabledAccentColors(copy: copy),
          SizedBox(height: _px(context, 8)),
          Row(
            children: <Widget>[
              _FieldLabel(label: copy.localized('界面缩放', 'Interface scale')),
              SizedBox(width: _px(context, 8)),
              Text(
                '100%',
                style: TextStyle(
                  fontSize: _font(context, 12),
                  fontWeight: FontWeight.w600,
                  color: DesktopColors.secondaryText,
                ),
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _UnavailableLabel(
                    label: copy.localized(
                      '当前版本不可调整',
                      'Not adjustable in this version',
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: _px(context, 24),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                disabledActiveTrackColor: const Color(0xFFDCD5CD),
                disabledInactiveTrackColor: const Color(0xFFEAE4DD),
                disabledThumbColor: const Color(0xFFCFC7BE),
                trackHeight: _px(context, 3),
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: _px(context, 6),
                  disabledThumbRadius: _px(context, 6),
                ),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: const Slider(
                value: 1,
                min: 0.8,
                max: 1.2,
                onChanged: null,
              ),
            ),
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
              duration: const Duration(milliseconds: 160),
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

class _DisabledAccentColors extends StatelessWidget {
  const _DisabledAccentColors({required this.copy});

  final AppCopy copy;

  static const List<Color> _colors = <Color>[
    Color(0xFFFF6846),
    Color(0xFFFFB427),
    Color(0xFF46BE72),
    Color(0xFF3489E8),
    Color(0xFFA555D8),
    Color(0xFFEF4A7A),
  ];

  @override
  Widget build(BuildContext context) => Tooltip(
    message: copy.localized('当前版本不可调整', 'Not adjustable in this version'),
    child: Semantics(
      enabled: false,
      label: copy.localized(
        '主题色，当前版本不可调整',
        'Accent color, not adjustable in this version',
      ),
      child: IgnorePointer(
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: Opacity(
            opacity: 0.38,
            child: Row(
              children: <Widget>[
                for (
                  int index = 0;
                  index < _colors.length;
                  index++
                ) ...<Widget>[
                  if (index > 0) SizedBox(width: _px(context, 9)),
                  Container(
                    key: index == 0
                        ? const ValueKey<String>(
                            'desktop-settings-disabled-accent',
                          )
                        : null,
                    width: _px(context, 19),
                    height: _px(context, 19),
                    decoration: BoxDecoration(
                      color: _colors[index],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({required this.copy});

  final AppCopy copy;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    icon: Icons.notifications_none_rounded,
    title: copy.localized('通知设置', 'Notification Settings'),
    child: Column(
      children: <Widget>[
        _UnavailableSettingRow(
          icon: Icons.new_releases_outlined,
          title: copy.localized('游戏上新通知', 'New Game Notifications'),
          subtitle: copy.localized(
            '关注的桌游有新内容时提醒',
            'Notify me when followed games get new content',
          ),
          unavailableLabel: copy.localized('暂不可用', 'Unavailable'),
        ),
        const _SettingsDivider(),
        _UnavailableSettingRow(
          icon: Icons.article_outlined,
          title: copy.localized('桌游资讯推送', 'Board Game News'),
          subtitle: copy.localized(
            '精选桌游文章、测评和资讯',
            'Curated articles, reviews, and news',
          ),
          unavailableLabel: copy.localized('暂不可用', 'Unavailable'),
        ),
      ],
    ),
  );
}
