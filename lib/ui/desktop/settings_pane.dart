import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/ai_api_config.dart';
import '../../models/app_language.dart';
import '../../models/asset_source_config.dart';
import '../../models/color_scheme_option.dart';
import '../../models/connectivity_status.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../../theme/palette_registry.dart';
import 'desktop_responsive.dart';
import 'theme.dart';

class DesktopSettingsPane extends StatefulWidget {
  const DesktopSettingsPane({
    super.key,
    required this.controller,
    required this.onOpenExistingSettings,
    required this.onOpenAbout,
  });

  final AppController controller;
  final VoidCallback onOpenExistingSettings;
  final VoidCallback onOpenAbout;

  @override
  State<DesktopSettingsPane> createState() => _DesktopSettingsPaneState();
}

class _DesktopSettingsPaneState extends State<DesktopSettingsPane> {
  late final Future<String> _version = _loadVersion();
  bool _saving = false;
  bool _checkingSources = false;
  bool _showApiKey = false;
  String? _failure;

  Future<String> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String build = info.buildNumber.trim();
      return build.isEmpty ? info.version : '${info.version} ($build)';
    } catch (_) {
      return '暂不可读取';
    }
  }

  Future<void> _save(Future<void> Function() operation) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _failure = '设置未能保存，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkResourceSources() async {
    if (_checkingSources) return;
    setState(() {
      _checkingSources = true;
      _failure = null;
    });
    try {
      await widget.controller.refreshAssetAccessStatus();
    } catch (_) {
      if (mounted) setState(() => _failure = '资料源检测失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _checkingSources = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final DesktopMetrics metrics = DesktopMetricsScope.of(context);
      final List<Widget> cards = <Widget>[
        _GeneralCard(
          controller: widget.controller,
          saving: _saving,
          onLanguage: (AppLanguage language) =>
              unawaited(_save(() => widget.controller.setLanguage(language))),
          onStartupUpdates: (bool enabled) => unawaited(
            _save(() => widget.controller.setCheckForUpdates(enabled)),
          ),
          onVoiceReply: (bool enabled) => unawaited(
            _save(() => widget.controller.setVoiceReplyEnabled(enabled)),
          ),
        ),
        _AiServiceCard(
          controller: widget.controller,
          showApiKey: _showApiKey,
          onToggleApiKey: () => setState(() => _showApiKey = !_showApiKey),
          onOpenDetails: widget.onOpenExistingSettings,
        ),
        _AppearanceCard(
          controller: widget.controller,
          saving: _saving,
          onSelectTheme: (ColorSchemeOption scheme) =>
              unawaited(_save(() => widget.controller.setColorScheme(scheme))),
        ),
        const _NotificationsCard(),
        _SyncBackupCard(
          controller: widget.controller,
          checking: _checkingSources,
          onCheckSources: _checkResourceSources,
        ),
        _AboutUpdatesCard(
          controller: widget.controller,
          version: _version,
          onOpenAbout: widget.onOpenAbout,
        ),
      ];

      return Padding(
        padding: metrics.insets(const EdgeInsets.only(top: 12, bottom: 16)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final int columns = DesktopResponsive.settingsColumnsFor(
              constraints.maxWidth,
            );
            final double gap = metrics.px(16);
            final List<Widget> rows = <Widget>[];
            for (int start = 0; start < cards.length; start += columns) {
              final int end = (start + columns).clamp(0, cards.length);
              rows.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int index = start; index < end; index++) ...<Widget>[
                        if (index > start) SizedBox(width: gap),
                        Expanded(child: cards[index]),
                      ],
                    ],
                  ),
                ),
              );
              if (end < cards.length) rows.add(SizedBox(height: gap));
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '设置',
                            style: TextStyle(
                              fontSize: metrics.font(28),
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: DesktopColors.text,
                            ),
                          ),
                          SizedBox(height: metrics.px(5)),
                          Text(
                            '应用偏好与服务',
                            style: TextStyle(
                              fontSize: metrics.font(13),
                              color: DesktopColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_saving)
                      SizedBox(
                        width: metrics.px(20),
                        height: metrics.px(20),
                        child: CircularProgressIndicator(
                          strokeWidth: metrics.px(2),
                          color: DesktopColors.orange,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: metrics.px(16)),
                ...rows,
                if (_failure != null) ...<Widget>[
                  SizedBox(height: metrics.px(10)),
                  Text(
                    _failure!,
                    style: TextStyle(
                      fontSize: metrics.font(12),
                      color: const Color(0xFF9F4D5D),
                    ),
                  ),
                ],
                SizedBox(height: metrics.px(14)),
                Row(
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'desktop-settings-restore-defaults',
                      ),
                      onPressed: null,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('恢复默认设置'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(0, metrics.px(40)),
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.px(14),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            metrics.radius(9),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '大多数设置会自动保存',
                      style: TextStyle(
                        fontSize: metrics.font(12),
                        color: DesktopColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DesktopMetrics metrics = DesktopMetricsScope.of(context);
    return Container(
      key: ValueKey<String>('desktop-settings-card-$title'),
      padding: EdgeInsets.all(metrics.px(17)),
      decoration: BoxDecoration(
        color: DesktopColors.card,
        borderRadius: BorderRadius.circular(metrics.radius(13)),
        border: Border.all(color: const Color(0x1AA76D48)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0x0A704728),
            blurRadius: metrics.px(12),
            offset: Offset(0, metrics.px(3)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: DesktopColors.orange, size: metrics.px(23)),
              SizedBox(width: metrics.px(9)),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: metrics.font(16),
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: DesktopColors.text,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.px(13)),
          child,
        ],
      ),
    );
  }
}

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
    return _SettingsCard(
      icon: Icons.tune_rounded,
      title: '通用',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _FieldLabel(label: '语言'),
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
            title: '启动时检查更新',
            subtitle: '当前更新源仅支持 Android APK',
            value: controller.checkForUpdates,
            onChanged: saving ? null : onStartupUpdates,
          ),
          SizedBox(height: _px(context, 4)),
          _SettingSwitchRow(
            key: const ValueKey<String>('desktop-settings-voice-reply'),
            title: '语音朗读',
            subtitle: controller.voiceReplyAvailable ? '可按设备能力启用' : '当前设备不可用',
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

class _AiServiceCard extends StatelessWidget {
  const _AiServiceCard({
    required this.controller,
    required this.showApiKey,
    required this.onToggleApiKey,
    required this.onOpenDetails,
  });

  final AppController controller;
  final bool showApiKey;
  final VoidCallback onToggleApiKey;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final AiApiConfig config = controller.aiApiConfig;
    final bool hasKey = config.apiKey.trim().isNotEmpty;
    final String keyValue = !hasKey
        ? '未配置'
        : showApiKey
        ? config.apiKey
        : '••••••••';
    final String endpoint = config.baseUrl.trim().isEmpty
        ? '未配置'
        : config.baseUrl.trim();

    return _SettingsCard(
      icon: Icons.auto_awesome_rounded,
      title: 'AI 服务',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _ValueField(
                  label: '供应商',
                  value: config.name.trim().isEmpty ? '未配置' : config.name,
                ),
              ),
              SizedBox(width: _px(context, 9)),
              Expanded(
                child: _ValueField(
                  label: '模型',
                  value: config.model.trim().isEmpty ? '未选择' : config.model,
                ),
              ),
            ],
          ),
          SizedBox(height: _px(context, 8)),
          _ValueField(
            label: 'API Key',
            value: keyValue,
            trailing: hasKey
                ? IconButton(
                    tooltip: showApiKey ? '隐藏 API Key' : '显示 API Key',
                    onPressed: onToggleApiKey,
                    icon: Icon(
                      showApiKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: _px(context, 18),
                    ),
                    visualDensity: VisualDensity.compact,
                  )
                : null,
          ),
          SizedBox(height: _px(context, 8)),
          _ValueField(label: '接口地址', value: endpoint),
          SizedBox(height: _px(context, 10)),
          Row(
            children: <Widget>[
              Expanded(
                child: _AiStatusLabel(
                  status: controller.aiConnectivityStatus,
                  hasKey: hasKey,
                ),
              ),
              SizedBox(width: _px(context, 8)),
              OutlinedButton.icon(
                key: const ValueKey<String>('desktop-settings-ai-details'),
                onPressed: onOpenDetails,
                icon: Icon(
                  Icons.settings_suggest_outlined,
                  size: _px(context, 17),
                ),
                label: const Text('详细设置'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, _px(context, 38)),
                  padding: EdgeInsets.symmetric(horizontal: _px(context, 11)),
                  foregroundColor: DesktopColors.brown,
                  side: const BorderSide(color: Color(0x1FA76D48)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_px(context, 9)),
                  ),
                ),
              ),
            ],
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
    return _SettingsCard(
      icon: Icons.palette_outlined,
      title: '外观与主题',
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
              Expanded(child: _FieldLabel(label: '主题色')),
              const _UnavailableLabel(label: '当前版本不可调整'),
            ],
          ),
          SizedBox(height: _px(context, 6)),
          const _DisabledAccentColors(),
          SizedBox(height: _px(context, 8)),
          Row(
            children: <Widget>[
              _FieldLabel(label: '界面缩放'),
              SizedBox(width: _px(context, 8)),
              Text(
                '100%',
                style: TextStyle(
                  fontSize: _font(context, 12),
                  fontWeight: FontWeight.w600,
                  color: DesktopColors.secondaryText,
                ),
              ),
              const Spacer(),
              const _UnavailableLabel(label: '当前版本不可调整'),
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
  const _DisabledAccentColors();

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
    message: '当前版本不可调整',
    child: Semantics(
      enabled: false,
      label: '主题色，当前版本不可调整',
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
                SizedBox(width: _px(context, 8)),
                const _UnavailableLabel(label: '当前版本不可调整'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard();

  @override
  Widget build(BuildContext context) => const _SettingsCard(
    icon: Icons.notifications_none_rounded,
    title: '通知设置',
    child: Column(
      children: <Widget>[
        _UnavailableSettingRow(
          icon: Icons.new_releases_outlined,
          title: '游戏上新通知',
          subtitle: '关注的桌游有新内容时提醒',
        ),
        _SettingsDivider(),
        _UnavailableSettingRow(
          icon: Icons.article_outlined,
          title: '桌游资讯推送',
          subtitle: '精选桌游文章、测评和资讯',
        ),
      ],
    ),
  );
}

class _SyncBackupCard extends StatelessWidget {
  const _SyncBackupCard({
    required this.controller,
    required this.checking,
    required this.onCheckSources,
  });

  final AppController controller;
  final bool checking;
  final VoidCallback onCheckSources;

  @override
  Widget build(BuildContext context) {
    final List<AssetSourceConfig> sources = controller.assetSourceConfigs;
    final Map<String, ConnectivityStatus> statuses =
        controller.assetSourceStatuses;
    final int connected = sources.where((source) {
      return statuses[source.id]?.state == ConnectivityState.success;
    }).length;
    final bool isLoading =
        checking ||
        sources.any((source) {
          return statuses[source.id]?.state == ConnectivityState.loading;
        });
    final String stateLabel;
    final Color stateColor;
    if (sources.isEmpty) {
      stateLabel = '未配置';
      stateColor = DesktopColors.secondaryText;
    } else if (isLoading) {
      stateLabel = '检测中';
      stateColor = DesktopColors.brown;
    } else if (connected > 0) {
      stateLabel = '已连接 $connected/${sources.length}';
      stateColor = const Color(0xFF497461);
    } else if (statuses.isEmpty ||
        sources.every((source) {
          return statuses[source.id] == null ||
              statuses[source.id]?.state == ConnectivityState.unknown;
        })) {
      stateLabel = '尚未检测';
      stateColor = DesktopColors.secondaryText;
    } else {
      stateLabel = '连接失败';
      stateColor = const Color(0xFF9F4D5D);
    }

    return _SettingsCard(
      icon: Icons.cloud_outlined,
      title: '同步与备份',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '桌游资料 WebDAV',
                      style: TextStyle(
                        fontSize: _font(context, 13),
                        fontWeight: FontWeight.w600,
                        color: DesktopColors.text,
                      ),
                    ),
                    SizedBox(height: _px(context, 3)),
                    Text(
                      '${sources.length} 个资料源；只用于游戏资源，不同步个人数据',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _font(context, 11),
                        height: 1.25,
                        color: DesktopColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: _px(context, 8)),
              _StatusPill(label: stateLabel, color: stateColor),
            ],
          ),
          SizedBox(height: _px(context, 8)),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey<String>(
                'desktop-settings-check-resource-sources',
              ),
              onPressed: checking ? null : onCheckSources,
              icon: checking
                  ? SizedBox.square(
                      dimension: _px(context, 15),
                      child: CircularProgressIndicator(
                        strokeWidth: _px(context, 1.8),
                      ),
                    )
                  : Icon(Icons.network_check_rounded, size: _px(context, 17)),
              label: Text(checking ? '正在检测' : '检测资料源'),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, _px(context, 36)),
                padding: EdgeInsets.symmetric(horizontal: _px(context, 10)),
                foregroundColor: DesktopColors.brown,
                side: const BorderSide(color: Color(0x1FA76D48)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_px(context, 8)),
                ),
              ),
            ),
          ),
          SizedBox(height: _px(context, 5)),
          _SettingsDivider(height: _px(context, 9)),
          _UnavailableSettingRow(
            icon: Icons.sync_rounded,
            title: '个人数据自动同步',
            subtitle: '当前版本不包含个人数据同步',
            compact: true,
          ),
          SizedBox(height: _px(context, 6)),
          Row(
            children: <Widget>[
              Expanded(
                child: _DisabledButton(
                  label: '立即同步',
                  icon: Icons.sync_rounded,
                  key: const ValueKey<String>('desktop-settings-sync-disabled'),
                ),
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: _DisabledButton(
                  label: '导入备份',
                  icon: Icons.file_download_outlined,
                ),
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: _DisabledButton(
                  label: '导出备份',
                  icon: Icons.file_upload_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutUpdatesCard extends StatelessWidget {
  const _AboutUpdatesCard({
    required this.controller,
    required this.version,
    required this.onOpenAbout,
  });

  final AppController controller;
  final Future<String> version;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    icon: Icons.info_outline_rounded,
    title: '关于与更新',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _FieldLabel(label: '当前版本')),
            FutureBuilder<String>(
              future: version,
              builder: (context, snapshot) => Text(
                snapshot.data ?? '读取中…',
                key: const ValueKey<String>('desktop-settings-app-version'),
                style: TextStyle(
                  fontSize: _font(context, 13),
                  fontWeight: FontWeight.w600,
                  color: DesktopColors.text,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: _px(context, 8)),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: _px(context, 11),
            vertical: _px(context, 9),
          ),
          decoration: BoxDecoration(
            color: DesktopColors.soft,
            borderRadius: BorderRadius.circular(_px(context, 8)),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                controller.checkForUpdates
                    ? Icons.update_rounded
                    : Icons.update_disabled_rounded,
                size: _px(context, 18),
                color: DesktopColors.orange,
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: Text(
                  controller.checkForUpdates
                      ? '启动检查已开启（更新源仅支持 Android APK）'
                      : '启动检查已关闭',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _font(context, 11.5),
                    height: 1.25,
                    color: DesktopColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: _px(context, 11)),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey<String>('desktop-settings-check-updates'),
                onPressed: onOpenAbout,
                icon: Icon(
                  Icons.system_update_alt_rounded,
                  size: _px(context, 17),
                ),
                label: const Text('检查更新'),
                style: _settingsButtonStyle(context),
              ),
            ),
            SizedBox(width: _px(context, 9)),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey<String>('desktop-settings-open-about'),
                onPressed: onOpenAbout,
                icon: Icon(Icons.open_in_new_rounded, size: _px(context, 17)),
                label: const Text('关于应用'),
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, _px(context, 39)),
                  backgroundColor: DesktopColors.orange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: _px(context, 8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_px(context, 9)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AiStatusLabel extends StatelessWidget {
  const _AiStatusLabel({required this.status, required this.hasKey});

  final ConnectivityStatus status;
  final bool hasKey;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (!hasKey) {
      label = '未配置';
      color = DesktopColors.secondaryText;
    } else {
      switch (status.state) {
        case ConnectivityState.success:
          label = '连接正常';
          color = const Color(0xFF497461);
        case ConnectivityState.loading:
          label = '检测中';
          color = DesktopColors.brown;
        case ConnectivityState.warning:
          label = '需要留意';
          color = const Color(0xFF945D31);
        case ConnectivityState.failure:
          label = '连接失败';
          color = const Color(0xFF9F4D5D);
        case ConnectivityState.unknown:
          label = '尚未检测';
          color = DesktopColors.secondaryText;
      }
    }
    return Row(
      children: <Widget>[
        Container(
          width: _px(context, 7),
          height: _px(context, 7),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: _px(context, 6)),
        Flexible(
          child: Text(
            'AI 服务 · $label',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _font(context, 11),
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ValueField extends StatelessWidget {
  const _ValueField({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _FieldLabel(label: label),
      SizedBox(height: _px(context, 4)),
      Container(
        height: _px(context, 39),
        padding: EdgeInsets.only(left: _px(context, 10)),
        decoration: BoxDecoration(
          color: DesktopColors.soft,
          borderRadius: BorderRadius.circular(_px(context, 8)),
          border: Border.all(color: const Color(0x10A76D48)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _font(context, 12),
                  color: value == '未配置' || value == '未选择'
                      ? DesktopColors.secondaryText
                      : DesktopColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ?trailing,
            SizedBox(width: _px(context, 4)),
          ],
        ),
      ),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize: _font(context, 12),
      height: 1.15,
      fontWeight: FontWeight.w500,
      color: DesktopColors.secondaryText,
    ),
  );
}

class _SettingSwitchRow extends StatelessWidget {
  const _SettingSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: _font(context, 13),
                fontWeight: FontWeight.w600,
                color: DesktopColors.text,
              ),
            ),
            SizedBox(height: _px(context, 2)),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _font(context, 11),
                color: DesktopColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
      SizedBox(width: _px(context, 5)),
      Transform.scale(
        scale: 0.86,
        alignment: Alignment.centerRight,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: DesktopColors.orange,
        ),
      ),
    ],
  );
}

class _UnavailableSettingRow extends StatelessWidget {
  const _UnavailableSettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    enabled: false,
    child: Opacity(
      opacity: 0.72,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: _px(context, compact ? 2 : 8)),
        child: Row(
          children: <Widget>[
            Icon(icon, size: _px(context, 20), color: DesktopColors.brown),
            SizedBox(width: _px(context, 10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: _font(context, 13),
                      fontWeight: FontWeight.w600,
                      color: DesktopColors.text,
                    ),
                  ),
                  SizedBox(height: _px(context, 2)),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: _font(context, 11),
                      height: 1.25,
                      color: DesktopColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: _px(context, 8)),
            const _UnavailableLabel(label: '暂不可用'),
          ],
        ),
      ),
    ),
  );
}

class _UnavailableLabel extends StatelessWidget {
  const _UnavailableLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: _font(context, 11),
      color: const Color(0xFF9B928A),
    ),
  );
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider({this.height = 8});

  final double height;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: height / 2),
    child: const Divider(height: 1, color: Color(0x16A76D48)),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: _px(context, 8),
      vertical: _px(context, 5),
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _font(context, 11),
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _DisabledButton extends StatelessWidget {
  const _DisabledButton({super.key, required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '当前版本不可用',
    child: OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icon, size: _px(context, 15)),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, _px(context, 35)),
        padding: EdgeInsets.symmetric(horizontal: _px(context, 5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_px(context, 8)),
        ),
      ),
    ),
  );
}

InputDecoration _fieldDecoration(BuildContext context) => InputDecoration(
  isDense: true,
  contentPadding: EdgeInsets.symmetric(
    horizontal: _px(context, 10),
    vertical: _px(context, 10),
  ),
  filled: true,
  fillColor: DesktopColors.soft,
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(_px(context, 8)),
    borderSide: const BorderSide(color: Color(0x10A76D48)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(_px(context, 8)),
    borderSide: const BorderSide(color: DesktopColors.orange, width: 1.2),
  ),
);

ButtonStyle _settingsButtonStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      minimumSize: Size(0, _px(context, 39)),
      foregroundColor: DesktopColors.brown,
      side: const BorderSide(color: Color(0x1FA76D48)),
      padding: EdgeInsets.symmetric(horizontal: _px(context, 8)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_px(context, 9)),
      ),
    );

double _px(BuildContext context, double value) =>
    DesktopMetricsScope.of(context).px(value);

double _font(BuildContext context, double value) =>
    DesktopMetricsScope.of(context).font(value);
