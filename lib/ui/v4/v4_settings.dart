import 'package:flutter/material.dart';

import '../../models/app_language.dart';
import '../../state/app_controller.dart';

// Scoped reference colors: tmp/board_game_assistant_v4/lib/theme/app_theme.dart.
abstract final class _SettingsColors {
  static const card = Color(0xFFFFFEFC);
  static const text = Color(0xFF171412);
  static const secondaryText = Color(0xFF7D756D);
  static const orange = Color(0xFFFF6846);
}

class V4SettingsPane extends StatefulWidget {
  const V4SettingsPane({
    super.key,
    required this.controller,
    required this.onOpenExistingSettings,
    required this.onOpenAbout,
  });

  final AppController controller;
  final VoidCallback onOpenExistingSettings;
  final VoidCallback onOpenAbout;

  @override
  State<V4SettingsPane> createState() => _V4SettingsPaneState();
}

class _V4SettingsPaneState extends State<V4SettingsPane> {
  bool _saving = false;
  String? _failure;

  Future<void> _setLanguage(String label) async {
    if (_saving) return;
    final language = AppLanguage.values.firstWhere(
      (value) => value.label == label,
    );
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      await widget.controller.setLanguage(language);
    } catch (_) {
      if (mounted) setState(() => _failure = '语言设置未能保存，请打开完整设置检查并重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Material(
      color: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: _SettingsColors.text),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Same helpers, ordering, dimensions and 13px gutters as the source.
              final cards = <Widget>[
                const _AccountCard(onUnavailable: null),
                const _NotificationCard(
                  gameUpdate: null,
                  activity: null,
                  community: null,
                  recommendation: null,
                  onGameUpdate: null,
                  onActivity: null,
                  onCommunity: null,
                  onRecommendation: null,
                ),
                const _AppearanceCard(
                  selected: -1,
                  accent: -1,
                  zoom: 1,
                  onSelected: null,
                  onAccent: null,
                  onZoom: null,
                ),
                _LanguageCard(
                  language: widget.controller.language.label,
                  onLanguage: _saving ? null : _setLanguage,
                ),
                const _PrivacyCard(onUnavailable: null),
                const _SyncCard(
                  autoSync: null,
                  onAutoSync: null,
                  onUnavailable: null,
                ),
                const _StorageCard(onUnavailable: null),
                const _PreferenceCard(preferences: {}, onPreference: null),
              ];
              final wide = constraints.maxWidth >= 1050;
              final columnWidth = (constraints.maxWidth - 26) / 3;
              Widget row(int start) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = start; i < start + 3; i++) ...[
                    if (i != start) const SizedBox(width: 13),
                    SizedBox(width: columnWidth, child: cards[i]),
                  ],
                ],
              );
              final reset = const _OutlineButton(
                icon: Icons.undo_rounded,
                label: '恢复默认设置',
                width: 156,
                onTap: null,
              );
              final logout = const _OutlineButton(
                icon: Icons.logout_rounded,
                label: '退出登录',
                width: 146,
                onTap: null,
              );
              final advanced = _PrimaryButton(
                label: '完整设置',
                width: 148,
                onTap: widget.onOpenExistingSettings,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) ...[
                    row(0),
                    const SizedBox(height: 13),
                    row(3),
                    const SizedBox(height: 13),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: columnWidth, child: cards[6]),
                        const SizedBox(width: 13),
                        Expanded(child: cards[7]),
                      ],
                    ),
                  ] else ...[
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 13),
                    ],
                  ],
                  const SizedBox(height: 11),
                  if (_saving)
                    const LinearProgressIndicator(
                      color: _SettingsColors.orange,
                    ),
                  if (_failure != null)
                    Text(
                      _failure!,
                      style: const TextStyle(
                        color: Color(0xFF9F4D5D),
                        fontSize: 12,
                      ),
                    ),
                  if (wide)
                    Row(
                      children: [
                        reset,
                        const Spacer(),
                        logout,
                        const SizedBox(width: 12),
                        advanced,
                      ],
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [reset, logout, advanced],
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    '完整设置：模型 · WebDAV · 下载 · 旧版/Web 配色（不影响 V4）',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10,
                      color: _SettingsColors.secondaryText,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.onOpenAbout,
                      child: const Text('关于'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

const _accentColors = <Color>[
  Color(0xFFFF6846),
  Color(0xFFFFB427),
  Color(0xFF46BE72),
  Color(0xFF3489E8),
  Color(0xFFA555D8),
  Color(0xFFEF4A7A),
];

// Geometry below is copied from the read-only V4 settings reference.
// Null callbacks mean unavailable, never a locally simulated saved value.
class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double height;
  final Widget child;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(17, 14, 17, 14),
      decoration: BoxDecoration(
        color: _SettingsColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x16A76D48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFE94B2D), size: 24),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _SettingsColors.secondaryText,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final ValueChanged<String>? onUnavailable;

  const _AccountCard({required this.onUnavailable});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.person_rounded,
      title: '账号信息',
      subtitle: '',
      height: 286,
      child: Column(
        children: [
          Row(
            children: [
              ClipOval(
                child: const SizedBox(
                  width: 70,
                  height: 70,
                  child: ColoredBox(
                    color: Color(0xFFF8F3EC),
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 36,
                      color: _SettingsColors.secondaryText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '-',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    _LevelBadge(),
                    SizedBox(height: 7),
                    Text(
                      '未开放',
                      style: TextStyle(
                        color: _SettingsColors.secondaryText,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Divider(height: 1),
          const SizedBox(height: 11),
          const _InfoLine(label: '邮箱', value: '-', trailing: _VerifiedBadge()),
          const SizedBox(height: 10),
          const _InfoLine(label: '注册时间', value: '-'),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 66,
                child: Text(
                  '会员类型',
                  style: TextStyle(
                    fontSize: 11,
                    color: _SettingsColors.secondaryText,
                  ),
                ),
              ),
              const Icon(
                Icons.workspace_premium_rounded,
                size: 17,
                color: Color(0xFFF1A000),
              ),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  '-',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              _MiniOutlineButton(label: '编辑资料', onTap: null),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDD1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Text(
        '-',
        style: TextStyle(
          color: Color(0xFFC47719),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F7E7),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Text(
        '未开放',
        style: TextStyle(
          fontSize: 9,
          color: Color(0xFF3E9E63),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoLine({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: _SettingsColors.secondaryText,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF514943)),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final bool? gameUpdate;
  final bool? activity;
  final bool? community;
  final bool? recommendation;
  final ValueChanged<bool>? onGameUpdate;
  final ValueChanged<bool>? onActivity;
  final ValueChanged<bool>? onCommunity;
  final ValueChanged<bool>? onRecommendation;

  const _NotificationCard({
    required this.gameUpdate,
    required this.activity,
    required this.community,
    required this.recommendation,
    required this.onGameUpdate,
    required this.onActivity,
    required this.onCommunity,
    required this.onRecommendation,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.notifications_rounded,
      title: '通知设置',
      subtitle: '通知状态：- · 未开放',
      height: 286,
      child: Column(
        children: [
          _ToggleSetting(
            icon: Icons.new_releases_rounded,
            title: '游戏上新通知',
            subtitle: '关注的游戏有新资讯时通知',
            value: gameUpdate,
            onChanged: onGameUpdate,
          ),
          _ToggleSetting(
            icon: Icons.local_activity_rounded,
            title: '活动与优惠',
            subtitle: '限时活动、折扣信息等',
            value: activity,
            onChanged: onActivity,
          ),
          _ToggleSetting(
            icon: Icons.forum_rounded,
            title: '社区互动通知',
            subtitle: '回复、点赞、@我的消息',
            value: community,
            onChanged: onCommunity,
          ),
          _ToggleSetting(
            icon: Icons.tips_and_updates_rounded,
            title: '桌游资讯推送',
            subtitle: '精选文章、测评和桌游新闻',
            value: recommendation,
            onChanged: onRecommendation,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _ToggleSetting extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final bool last;

  const _ToggleSetting({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFA15D45)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: _SettingsColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          _TinySwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TinySwitch extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool>? onChanged;

  const _TinySwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: _ReferenceControl(
        onTap: null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 39,
          height: 23,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value == true
                ? _SettingsColors.orange
                : const Color(0xFFD9D4CE),
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            alignment: value == true
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              width: 19,
              height: 19,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: value == null
                  ? const Center(
                      child: Text('-', style: TextStyle(fontSize: 10)),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  final int selected;
  final int accent;
  final double zoom;
  final ValueChanged<int>? onSelected;
  final ValueChanged<int>? onAccent;
  final ValueChanged<double>? onZoom;

  const _AppearanceCard({
    required this.selected,
    required this.accent,
    required this.zoom,
    required this.onSelected,
    required this.onAccent,
    required this.onZoom,
  });

  @override
  Widget build(BuildContext context) {
    const themes = [
      ('assets/v4/theme_system.png', '跟随系统'),
      ('assets/v4/theme_light.png', '浅色模式'),
      ('assets/v4/theme_dark.png', '深色模式'),
    ];
    return _SettingsCard(
      icon: Icons.palette_rounded,
      title: '外观与主题',
      subtitle: 'V4 固定暖色；主题、色彩与缩放未开放',
      height: 286,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < themes.length; i++) ...[
                  Expanded(
                    child: _ThemeChoice(
                      image: themes[i].$1,
                      label: themes[i].$2,
                      selected: selected == i,
                      onTap: null,
                    ),
                  ),
                  if (i != themes.length - 1) const SizedBox(width: 9),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 74,
                child: Text(
                  '界面色彩',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              for (var i = 0; i < _accentColors.length; i++) ...[
                _AccentDot(
                  color: _accentColors[i],
                  selected: accent == i,
                  onTap: null,
                ),
                if (i != _accentColors.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 74,
                child: Text(
                  '界面缩放',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _SettingsColors.orange,
                    inactiveTrackColor: const Color(0xFFE7DFD8),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                      elevation: 1,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: zoom,
                    min: 0.8,
                    max: 1.2,
                    onChanged: onZoom,
                  ),
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '-',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: _SettingsColors.secondaryText,
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

class _ThemeChoice extends StatelessWidget {
  final String image;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ThemeChoice({
    required this.image,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: _ReferenceControl(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selected
                                ? _SettingsColors.orange
                                : const Color(0xFFE5DDD6),
                            width: selected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.asset(image, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    const Positioned(
                      right: 6,
                      top: 6,
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: _SettingsColors.orange,
                        child: Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const _AccentDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 2,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x33FF6846),
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final String language;
  final ValueChanged<String>? onLanguage;

  const _LanguageCard({required this.language, required this.onLanguage});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.language_rounded,
      title: '语言设置',
      subtitle: '仅影响旧版页面；V4 界面固定中文',
      height: 177,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5DDD6)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: language,
                isExpanded: true,
                style: const TextStyle(
                  fontSize: 12,
                  color: _SettingsColors.text,
                ),
                items: const ['简体中文', 'English']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: onLanguage == null
                    ? null
                    : (value) {
                        if (value != null) onLanguage!(value);
                      },
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '更改后自动保存，不改变 V4 界面语言',
            style: TextStyle(
              fontSize: 9.5,
              color: _SettingsColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  final ValueChanged<String>? onUnavailable;

  const _PrivacyCard({required this.onUnavailable});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.security_rounded,
      title: '隐私与安全',
      subtitle: '账号安全：- · 未开放',
      height: 177,
      child: Column(
        children: [
          _ArrowSetting(icon: Icons.shield_rounded, label: '修改密码', onTap: null),
          _ArrowSetting(
            icon: Icons.lock_rounded,
            label: '两步验证',
            trailing: '未开放',
            onTap: null,
          ),
          _ArrowSetting(
            icon: Icons.privacy_tip_rounded,
            label: '隐私设置',
            onTap: null,
          ),
          _ArrowSetting(
            icon: Icons.devices_rounded,
            label: '管理已授权的设备',
            onTap: null,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _ArrowSetting extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;
  final bool last;

  const _ArrowSetting({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Row(
          children: [
            Icon(icon, size: 15, color: const Color(0xFFA15D45)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: _SettingsColors.secondaryText,
                ),
              ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Color(0xFFB1AAA4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  final bool? autoSync;
  final ValueChanged<bool>? onAutoSync;
  final ValueChanged<String>? onUnavailable;

  const _SyncCard({
    required this.autoSync,
    required this.onAutoSync,
    required this.onUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.cloud_rounded,
      title: '数据同步与备份',
      subtitle: '云同步：- · 未开放',
      height: 177,
      child: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F5EF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFD9D4CE),
                    child: Text('-', style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '上次同步：-',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '未开放',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: _SettingsColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MiniPrimaryButton(label: '立即同步', onTap: null),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '自动同步',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Wi-Fi下自动同步数据',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: _SettingsColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              _TinySwitch(value: autoSync, onChanged: onAutoSync),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  final ValueChanged<String>? onUnavailable;

  const _StorageCard({required this.onUnavailable});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: Icons.storage_rounded,
      title: '存储与缓存',
      subtitle: '管理本地存储空间',
      height: 145,
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '缓存大小',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              const Text(
                '-',
                style: TextStyle(
                  fontSize: 10.5,
                  color: _SettingsColors.secondaryText,
                ),
              ),
              const SizedBox(width: 10),
              _MiniOutlineButton(label: '清理缓存', onTap: null),
            ],
          ),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '缓存统计与清理未开放；下载配置见完整设置',
              style: TextStyle(
                fontSize: 9.3,
                color: _SettingsColors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  final Set<String> preferences;
  final ValueChanged<String>? onPreference;

  const _PreferenceCard({
    required this.preferences,
    required this.onPreference,
  });

  @override
  Widget build(BuildContext context) {
    const tags = ['策略', '合作', '推理', '派对', '卡牌', '家庭', '抽象'];
    return _SettingsCard(
      icon: Icons.favorite_rounded,
      title: '推荐偏好',
      subtitle: '推荐偏好：- · 未开放',
      height: 145,
      child: Row(
        children: [
          const Text(
            '我感兴趣的游戏类型',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                for (final tag in tags)
                  _PreferenceChip(
                    label: tag,
                    selected: preferences.contains(tag),
                    onTap: null,
                  ),
                _PreferenceChip(label: '＋ 添加', selected: false, onTap: null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _PreferenceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: _ReferenceControl(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? _SettingsColors.orange : const Color(0xFFF7F3EE),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? _SettingsColors.orange
                  : const Color(0xFFE5DDD6),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: selected ? Colors.white : const Color(0xFF6A625D),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _MiniOutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: _ReferenceControl(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFFA182)),
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFFFFFBF7),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              color: Color(0xFFE95637),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _MiniPrimaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: _ReferenceControl(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5C45), Color(0xFFFF8A4F)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final double width;
  final VoidCallback? onTap;

  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ReferenceControl(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: width,
        height: 41,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF7),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFFFA182)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: const Color(0xFFB45A3A)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFB45A3A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final double width;
  final VoidCallback? onTap;

  const _PrimaryButton({
    required this.label,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ReferenceControl(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: width,
        height: 41,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF5C45), Color(0xFFFF9D58)],
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ReferenceControl extends StatelessWidget {
  const _ReferenceControl({
    required this.child,
    required this.onTap,
    this.borderRadius,
  });
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: onTap == null ? '- · 未开放' : '',
    child: Semantics(
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(8),
        mouseCursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        hoverColor: const Color(0x0DA76D48),
        focusColor: const Color(0x26FF6846),
        child: child,
      ),
    ),
  );
}
