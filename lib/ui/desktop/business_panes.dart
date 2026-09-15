import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../models/app_activity.dart';
import '../../models/app_language.dart';
import '../../models/ai_api_config.dart';
import '../../models/ai_conversation.dart';
import '../../models/ai_run.dart';
import '../../models/answer_source.dart';
import '../../models/chat_message.dart';
import '../../models/color_scheme_option.dart';
import '../../models/desktop_library_resource.dart';
import '../../models/game_info.dart';
import '../../models/game_resource.dart';
import '../../models/resolved_document.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';
import '../widgets/ai_run_activity.dart';
import '../widgets/assistant_feature_chip.dart';
import '../widgets/language_sheet.dart';
import '../widgets/message_bubble.dart';
import '../screens/markdown_document_screen.dart';
import '../screens/pdf_document_screen.dart';
import '../screens/library_resource_document_screen.dart';

Color _desktopFeatureColor(
  BuildContext context,
  Color original,
  Color replacement,
) => AppPalette.of(context).scheme == ColorSchemeOption.warmwoodStudy
    ? replacement
    : original;

ButtonStyle _desktopIconButtonStyle(AppPalette palette) => IconButton.styleFrom(
  foregroundColor: palette.textSecondary,
  backgroundColor: Colors.transparent,
  minimumSize: const Size.square(34),
  maximumSize: const Size.square(34),
  fixedSize: const Size.square(34),
  padding: EdgeInsets.zero,
  visualDensity: VisualDensity.standard,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
);

BoxDecoration _desktopOptionDecoration(
  AppPalette palette, {
  required bool selected,
  double radius = 8,
}) => BoxDecoration(
  color: selected ? palette.surfaceContainer : Colors.transparent,
  borderRadius: BorderRadius.circular(radius),
  border: Border(
    left: BorderSide(
      color: selected ? palette.primary : Colors.transparent,
      width: 3,
    ),
  ),
);

class _DesktopNoGamesPane extends StatefulWidget {
  const _DesktopNoGamesPane({
    required this.controller,
    this.title,
    this.message,
  });

  final AppController controller;
  final String? title;
  final String? message;

  @override
  State<_DesktopNoGamesPane> createState() => _DesktopNoGamesPaneState();
}

class _DesktopNoGamesPaneState extends State<_DesktopNoGamesPane> {
  bool _loading = false;
  String? _error;

  Future<void> _reload() async {
    if (_loading) return;
    final AppCopy copy = widget.controller.copy;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.controller.reloadGames();
      if (mounted && !widget.controller.hasGames) {
        setState(() => _error = copy.desktopNoGamesMissing);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = copy.desktopNoGamesLoadFailed(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    final String title = widget.title ?? copy.desktopNoGamesTitle;
    final String message = widget.message ?? copy.desktopNoGamesMessage;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: palette.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.inventory_2_outlined,
                  size: 48,
                  color: palette.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.error,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _loading ? null : _reload,
                      icon: _loading
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        _loading
                            ? copy.desktopNoGamesLoading
                            : copy.desktopNoGamesRetry,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(copy.desktopCheckSettingsHint),
                          ),
                        ),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(copy.desktopCheckSettings),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopRulesDrawer extends StatelessWidget {
  const DesktopRulesDrawer({
    super.key,
    required this.open,
    required this.tabIndex,
    required this.game,
    required this.resource,
    required this.controller,
    required this.onClose,
    required this.onTabChanged,
    required this.onOpenAssistant,
    required this.onOpenResource,
  });

  final bool open;
  final int tabIndex;
  final GameInfo? game;
  final DesktopLibraryResource? resource;
  final AppController controller;
  final VoidCallback onClose;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenResource;

  @override
  Widget build(BuildContext context) {
    if (!open) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          opacity: open ? 1 : 0,
          child: Stack(
            children: <Widget>[
              GestureDetector(
                onTap: onClose,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: const Color(0xB8000000)),
                ),
              ),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = math.min(
                    720,
                    constraints.maxWidth * 0.92,
                  );
                  return Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      offset: open ? Offset.zero : const Offset(1, 0),
                      child: SizedBox(
                        width: width,
                        height: constraints.maxHeight,
                        child: _RulesDrawerPanel(
                          game: game,
                          resource: resource,
                          controller: controller,
                          tabIndex: tabIndex,
                          onClose: onClose,
                          onTabChanged: onTabChanged,
                          onOpenAssistant: onOpenAssistant,
                          onOpenResource: onOpenResource,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulesDrawerPanel extends StatelessWidget {
  const _RulesDrawerPanel({
    required this.game,
    required this.resource,
    required this.controller,
    required this.tabIndex,
    required this.onClose,
    required this.onTabChanged,
    required this.onOpenAssistant,
    required this.onOpenResource,
  });

  final GameInfo? game;
  final DesktopLibraryResource? resource;
  final AppController controller;
  final int tabIndex;
  final VoidCallback onClose;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenResource;

  String get _title {
    if (resource != null) return resource!.title;
    if (game != null) return '《${game!.title}》· 游戏档案';
    return '文档速览';
  }

  String get _subtitle {
    if (resource != null) {
      return '${resource!.gameTitle} · ${resource!.typeLabel} · ${resource!.formatLabel}';
    }
    if (game != null) return '已挂载当前桌游的本地资料';
    return '未选择桌游资料';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _desktopFeatureColor(
          context,
          Color(0xFF111722),
          AppPalette.of(context).surface,
        ),
        border: Border(
          left: BorderSide(
            color: _desktopFeatureColor(
              context,
              Color(0x12FFFFFF),
              AppPalette.of(context).outline,
            ),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0xE6000000),
            blurRadius: 60,
            offset: Offset(-20, 0),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Container(
            height: 56,
            padding: EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: _desktopFeatureColor(
                context,
                Color(0xB3121924),
                AppPalette.of(context).surfaceContainer,
              ),
              border: Border(
                bottom: BorderSide(
                  color: _desktopFeatureColor(
                    context,
                    Color(0x12FFFFFF),
                    AppPalette.of(context).outline,
                  ),
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _desktopFeatureColor(
                            context,
                            Colors.white,
                            AppPalette.of(context).textPrimary,
                          ),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        _subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _desktopFeatureColor(
                            context,
                            Color(0xFF8A96A3),
                            AppPalette.of(context).textSecondary,
                          ),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: '关闭',
                  icon: Icon(Icons.close_rounded, size: 17),
                  color: _desktopFeatureColor(
                    context,
                    Color(0xFF8A96A3),
                    AppPalette.of(context).textSecondary,
                  ),
                  style: IconButton.styleFrom(
                    fixedSize: Size.square(28),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: _desktopFeatureColor(
                context,
                Color(0xFF0E131D),
                AppPalette.of(context).surfaceContainer,
              ),
              border: Border(
                bottom: BorderSide(
                  color: _desktopFeatureColor(
                    context,
                    Color(0x12FFFFFF),
                    AppPalette.of(context).outline,
                  ),
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                _RulesDrawerTab(
                  label: '规则速览',
                  selected: tabIndex == 0,
                  onTap: () => onTabChanged(0),
                ),
                SizedBox(width: 20),
                _RulesDrawerTab(
                  label: '规则裁决问答',
                  selected: tabIndex == 1,
                  onTap: () => onTabChanged(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: tabIndex == 0
                ? _RulesReaderContent(
                    game: game,
                    resource: resource,
                    onOpenResource: onOpenResource,
                  )
                : _RulesAssistantContent(
                    game: game,
                    onOpenAssistant: onOpenAssistant,
                  ),
          ),
        ],
      ),
    );
  }
}

class _RulesDrawerTab extends StatelessWidget {
  const _RulesDrawerTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? _desktopFeatureColor(
                        context,
                        Colors.white,
                        AppPalette.of(context).textPrimary,
                      )
                    : _desktopFeatureColor(
                        context,
                        Color(0xFF8A96A3),
                        AppPalette.of(context).textSecondary,
                      ),
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (selected)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 2,
                  child: ColoredBox(
                    color: _desktopFeatureColor(
                      context,
                      Color(0xFF66C0F4),
                      AppPalette.of(context).primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RulesReaderContent extends StatelessWidget {
  const _RulesReaderContent({
    required this.game,
    required this.resource,
    required this.onOpenResource,
  });

  final GameInfo? game;
  final DesktopLibraryResource? resource;
  final VoidCallback onOpenResource;

  @override
  Widget build(BuildContext context) {
    final List<String> roundFlow = game?.roundFlow ?? <String>[];
    final List<GameResource> resources =
        game?.resources
            .where(
              (GameResource item) =>
                  item.enabled && item.isAvailable && !item.isInOthersDirectory,
            )
            .toList(growable: false) ??
        <GameResource>[];
    final bool hasContent =
        game != null &&
        ((game!.summary.trim().isNotEmpty) ||
            roundFlow.isNotEmpty ||
            resources.isNotEmpty);
    return ListView(
      padding: EdgeInsets.all(28),
      children: <Widget>[
        Container(
          padding: EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: _desktopFeatureColor(
              context,
              Color(0x40000000),
              AppPalette.of(context).surfaceVariant,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _desktopFeatureColor(
                context,
                Color(0x12FFFFFF),
                AppPalette.of(context).outline,
              ),
            ),
          ),
          child: !hasContent
              ? Text(
                  '暂无可用规则摘要。请先挂载规则书或 FAQ 资料。',
                  style: TextStyle(
                    color: _desktopFeatureColor(
                      context,
                      Color(0xFF8A96A3),
                      AppPalette.of(context).textSecondary,
                    ),
                    fontSize: 13,
                    height: 1.8,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (game != null) ...<Widget>[
                      Text(
                        '《${game!.title}》· 规则资料速览',
                        style: TextStyle(
                          color: _desktopFeatureColor(
                            context,
                            Colors.white,
                            AppPalette.of(context).textPrimary,
                          ),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 14),
                      if (game!.summary.trim().isNotEmpty)
                        Text(
                          game!.summary,
                          style: TextStyle(
                            color: _desktopFeatureColor(
                              context,
                              Color(0xFFC9D2DB),
                              AppPalette.of(context).textSecondary,
                            ),
                            fontSize: 13,
                            height: 1.8,
                          ),
                        ),
                      if (roundFlow.isNotEmpty) ...<Widget>[
                        SizedBox(height: 18),
                        Text(
                          '回合流程',
                          style: TextStyle(
                            color: _desktopFeatureColor(
                              context,
                              Color(0xFF66C0F4),
                              AppPalette.of(context).primary,
                            ),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        ...roundFlow.asMap().entries.map(
                          (MapEntry<int, String> entry) => Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${entry.key + 1}. ${entry.value}',
                              style: TextStyle(
                                color: _desktopFeatureColor(
                                  context,
                                  Color(0xFFC9D2DB),
                                  AppPalette.of(context).textSecondary,
                                ),
                                fontSize: 13,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (resources.isNotEmpty) ...<Widget>[
                        SizedBox(height: 18),
                        Text(
                          '已挂载资料',
                          style: TextStyle(
                            color: _desktopFeatureColor(
                              context,
                              Color(0xFF66C0F4),
                              AppPalette.of(context).primary,
                            ),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        ...resources.map(
                          (GameResource item) => Padding(
                            padding: EdgeInsets.only(bottom: 5),
                            child: Text(
                              '• ${item.fileName} · ${item.format.toUpperCase()}',
                              style: TextStyle(
                                color: _desktopFeatureColor(
                                  context,
                                  Color(0xFFC9D2DB),
                                  AppPalette.of(context).textSecondary,
                                ),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (resource != null && resource!.canOpen) ...<Widget>[
                      SizedBox(height: 20),
                      TextButton.icon(
                        onPressed: onOpenResource,
                        icon: Icon(Icons.open_in_new_rounded, size: 15),
                        label: Text('打开原始资料'),
                        style: TextButton.styleFrom(
                          foregroundColor: _desktopFeatureColor(
                            context,
                            Color(0xFF66C0F4),
                            AppPalette.of(context).primary,
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _RulesAssistantContent extends StatelessWidget {
  const _RulesAssistantContent({
    required this.game,
    required this.onOpenAssistant,
  });

  final GameInfo? game;
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                constraints: BoxConstraints(maxWidth: 560),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _desktopFeatureColor(
                    context,
                    Color(0xB3161F2C),
                    AppPalette.of(context).surfaceVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _desktopFeatureColor(
                      context,
                      Color(0x12FFFFFF),
                      AppPalette.of(context).outline,
                    ),
                  ),
                ),
                child: Text(
                  game == null
                      ? '请选择一款桌游后再进入规则裁决问答。'
                      : '这里会继续使用《${game!.title}》的真实 AI 会话。打开助手后，回答、引用和运行过程会保留在同一会话中。',
                  style: TextStyle(
                    color: _desktopFeatureColor(
                      context,
                      Color(0xFFF0F3F7),
                      AppPalette.of(context).textPrimary,
                    ),
                    fontSize: 12.5,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: _desktopFeatureColor(
                    context,
                    Color(0x12FFFFFF),
                    AppPalette.of(context).outline,
                  ),
                ),
              ),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenAssistant,
                icon: Icon(Icons.chat_bubble_outline_rounded, size: 15),
                label: Text('打开桌游助手'),
                style: TextButton.styleFrom(
                  foregroundColor: _desktopFeatureColor(
                    context,
                    Color(0xFF66C0F4),
                    AppPalette.of(context).primary,
                  ),
                  backgroundColor: _desktopFeatureColor(
                    context,
                    Color(0x1A66C0F4),
                    AppPalette.of(context).primaryContainer,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopActivityPopup extends StatefulWidget {
  const DesktopActivityPopup({
    super.key,
    required this.controller,
    required this.maxHeight,
    required this.onClose,
    required this.onActivityTap,
  });

  final AppController controller;
  final double maxHeight;
  final VoidCallback onClose;
  final ValueChanged<AppActivity> onActivityTap;

  @override
  State<DesktopActivityPopup> createState() => DesktopActivityPopupState();
}

class DesktopActivityPopupState extends State<DesktopActivityPopup> {
  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final List<AppActivity> activities = widget.controller.activities
            .map(widget.controller.resolveActivityTarget)
            .toList(growable: false);
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxWidth < 320;
            final EdgeInsets panelPadding = EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 10 : 14,
              compact ? 12 : 16,
              compact ? 10 : 12,
            );
            final double listMaxHeight = math.max(
              0,
              widget.maxHeight - (compact ? 74 : 82),
            );
            return Material(
              color: Colors.transparent,
              elevation: 18,
              shadowColor: Colors.black.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                key: const ValueKey<String>('desktop-activity-popup'),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.outline),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  child: Padding(
                    padding: panelPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.notifications_none_rounded,
                              size: compact ? 21 : 24,
                              color: palette.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              copy.activityTitle,
                              style:
                                  (compact
                                          ? Theme.of(
                                              context,
                                            ).textTheme.titleMedium
                                          : Theme.of(
                                              context,
                                            ).textTheme.titleLarge)
                                      ?.copyWith(
                                        color: palette.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                            ),
                            if (activities.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.primary.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${activities.length}',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: palette.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            IconButton(
                              tooltip: copy.dialogClose,
                              visualDensity: compact
                                  ? VisualDensity.compact
                                  : VisualDensity.standard,
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        Divider(height: 16, color: palette.outline),
                        if (activities.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              copy.activityEmpty,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: listMaxHeight,
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: activities.length,
                              separatorBuilder:
                                  (BuildContext context, int index) => Divider(
                                    height: 1,
                                    color: palette.outline,
                                  ),
                              itemBuilder: (BuildContext context, int index) =>
                                  _DesktopActivityTile(
                                    activity: activities[index],
                                    compact: false,
                                    controller: widget.controller,
                                    onTap: () =>
                                        widget.onActivityTap(activities[index]),
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DesktopActivityTile extends StatelessWidget {
  const _DesktopActivityTile({
    required this.controller,
    required this.activity,
    required this.compact,
    this.onTap,
  });

  final AppController controller;
  final AppActivity activity;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    final Color accent = _activityColor(palette, activity.kind);
    final Widget content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 4,
        vertical: compact ? 10 : 8,
      ),
      decoration: compact
          ? BoxDecoration(
              color: palette.surfaceContainer.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(_activityIcon(activity.kind), size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  activity.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  activity.message,
                  maxLines: compact ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: _activityAbsoluteTime(activity.createdAt),
            child: Text(
              _activityTime(copy, activity.createdAt),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(compact ? 11 : 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 11 : 4),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

IconData _activityIcon(AppActivityKind kind) {
  return switch (kind) {
    AppActivityKind.serviceRefresh => Icons.sync_rounded,
    AppActivityKind.aiCompleted => Icons.check_circle_outline_rounded,
    AppActivityKind.aiFailed => Icons.error_outline_rounded,
    AppActivityKind.libraryUpdate => Icons.system_update_alt_rounded,
    AppActivityKind.libraryLoadFailed => Icons.error_outline_rounded,
    AppActivityKind.info => Icons.info_outline_rounded,
  };
}

Color _activityColor(AppPalette palette, AppActivityKind kind) {
  return switch (kind) {
    AppActivityKind.serviceRefresh => palette.primary,
    AppActivityKind.aiCompleted => palette.success,
    AppActivityKind.aiFailed => palette.error,
    AppActivityKind.libraryUpdate => palette.warning,
    AppActivityKind.libraryLoadFailed => palette.error,
    AppActivityKind.info => palette.textSecondary,
  };
}

String _activityTime(AppCopy copy, DateTime createdAt) {
  final Duration age = DateTime.now().difference(createdAt);
  if (age.isNegative || age.inSeconds < 60) {
    return copy.activityJustNow;
  }
  if (age.inMinutes < 60) {
    return copy.activityMinutesAgo(age.inMinutes);
  }
  if (age.inHours < 24) {
    return copy.activityHoursAgo(age.inHours);
  }
  if (age.inDays < 7) {
    return copy.activityDaysAgo(age.inDays);
  }
  final DateTime local = createdAt.toLocal();
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}

String _activityAbsoluteTime(DateTime createdAt) {
  final DateTime local = createdAt.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

class DesktopAssistantPane extends StatefulWidget {
  const DesktopAssistantPane({super.key, required this.controller});

  final AppController controller;

  @override
  State<DesktopAssistantPane> createState() => DesktopAssistantPaneState();
}

class DesktopAssistantPaneState extends State<DesktopAssistantPane> {
  late final TextEditingController _draftController;
  late final ScrollController _scrollController;
  bool _showMessageTimes = false;
  bool _showJumpToBottom = false;
  bool _hasNewContent = false;
  String? _lastConversationId;
  bool _followNewMessages = true;
  final Map<String, double> _scrollOffsets = <String, double>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  Timer? _messageTimesTimer;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController();
    _scrollController = ScrollController()..addListener(_handleScrollChanged);
    _lastConversationId = controller.selectedConversationId;
    controller.addListener(_handleControllerChanged);
    _scheduleInitialScrollToBottom();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _scrollController.removeListener(_handleScrollChanged);
    _draftController.dispose();
    _scrollController.dispose();
    _messageTimesTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.hasGames) {
      return _DesktopNoGamesPane(
        controller: controller,
        title: controller.copy.desktopAssistantUnavailable,
        message: controller.copy.desktopAssistantUnavailableMessage,
      );
    }
    final AppPalette palette = AppPalette.of(context);
    final AiConversation? selectedConversation =
        controller.selectedConversation;
    if (selectedConversation == null) {
      return _DesktopAssistantEmptyPane(controller: controller);
    }
    final bool useGlobalMode = selectedConversation.isGlobal;
    final List<ChatMessage> messages = controller.messagesForContext(
      useGlobalMode: useGlobalMode,
    );
    final List<AiRunEvent> runEvents = controller.aiRunEventsForContext(
      useGlobalMode: useGlobalMode,
    );
    final bool showRun =
        runEvents.isNotEmpty ||
        controller.isSendingForContext(useGlobalMode: useGlobalMode);
    final int lastAssistantIndex = messages.lastIndexWhere(
      (ChatMessage message) => message.role == ChatRole.assistant,
    );
    final GameInfo game = selectedConversation.gameId == null
        ? controller.featuredGame
        : controller.games.firstWhere(
            (GameInfo item) => item.id == selectedConversation.gameId,
            orElse: () => controller.featuredGame,
          );
    final String assistantTitle = useGlobalMode
        ? controller.copy.globalAiTitle
        : '${game.title}助手';
    final String messageSummary = controller.copy.desktopAssistantMessages(
      messages.length,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 760;
        final double contentInset = math.max(
          17,
          (constraints.maxWidth - 780) / 2,
        );
        // The message column stays readable at 780px, while the composer
        // follows the wider desktop reference layout. Keeping its inset
        // independent prevents a wide window from squeezing the input row
        // into the message column.
        final double composerInset = math.max(
          17,
          (constraints.maxWidth - 1360) / 2,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              constraints: const BoxConstraints(minHeight: 79),
              padding: EdgeInsets.fromLTRB(
                narrow ? 17 : 28,
                16,
                narrow ? 17 : 28,
                16,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.outline)),
              ),
              child: Row(
                children: <Widget>[
                  const _AssistantAppMark(),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          assistantTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            _AssistantStatusDot(color: palette.success),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                messageSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!narrow &&
                      (!useGlobalMode ||
                          controller.globalUseCurrentGameKnowledge)) ...[
                    _AssistantStatusLabel(label: game.title, palette: palette),
                    const SizedBox(width: 14),
                    _AssistantStatusLabel(
                      label: controller.copy.desktopRulebookCached,
                      palette: palette,
                    ),
                    const SizedBox(width: 7),
                  ],
                  if (narrow)
                    IconButton(
                      tooltip: controller.copy.desktopSessionTitle,
                      onPressed: () => _showAssistantSheet(
                        title: controller.copy.desktopSessionTitle,
                        child: _DesktopAssistantSessions(
                          controller: controller,
                          embedded: false,
                        ),
                      ),
                      style: _desktopIconButtonStyle(palette),
                      icon: const Icon(Icons.forum_outlined),
                    ),
                  if (narrow)
                    IconButton(
                      tooltip: controller.copy.desktopContextTitle,
                      onPressed: () => _showAssistantSheet(
                        title: controller.copy.desktopContextTitle,
                        child: _DesktopContextPanel(
                          controller: controller,
                          useGlobalMode: useGlobalMode,
                        ),
                      ),
                      style: _desktopIconButtonStyle(palette),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  IconButton(
                    tooltip: controller.copy.desktopClearConversation,
                    onPressed: () => controller.clearConversationForContext(
                      useGlobalMode: useGlobalMode,
                    ),
                    style: _desktopIconButtonStyle(palette),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: controller.copy.desktopMore,
                    onSelected: (String value) {
                      if (value == 'context') {
                        _showAssistantSheet(
                          title: controller.copy.desktopContextTitle,
                          child: _DesktopContextPanel(
                            controller: controller,
                            useGlobalMode: useGlobalMode,
                          ),
                        );
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'context',
                            child: Text(controller.copy.desktopContextTitle),
                          ),
                        ],
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    iconSize: 18,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      contentInset,
                      30,
                      contentInset,
                      16,
                    ),
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < messages.length;
                        index++
                      ) ...<Widget>[
                        if (showRun && index == lastAssistantIndex)
                          AiRunActivity(
                            events: runEvents,
                            isRunning: controller.isSendingForContext(
                              useGlobalMode: useGlobalMode,
                            ),
                            palette: palette,
                            copy: controller.copy,
                            contextKey: selectedConversation.id,
                            initialExpanded: controller.aiRunExpandedForContext(
                              useGlobalMode: useGlobalMode,
                            ),
                            onExpandedChanged: (bool expanded) =>
                                controller.setAiRunExpandedForContext(
                                  useGlobalMode: useGlobalMode,
                                  expanded: expanded,
                                ),
                          ),
                        if (!(messages[index].role == ChatRole.assistant &&
                            messages[index].isStreaming &&
                            messages[index].text.trim().isEmpty &&
                            showRun))
                          MessageBubble(
                            key: _messageKeys.putIfAbsent(
                              messages[index].id,
                              GlobalKey.new,
                            ),
                            message: messages[index],
                            palette: palette,
                            copy: controller.copy,
                            showAssistantAvatar: false,
                            showAssistantActionLabels: true,
                            maxWidth: 780,
                            desktopLayout: true,
                            desktopMeta: _desktopMessageMeta(
                              messages[index],
                              controller.copy,
                            ),
                            onSpeak: messages[index].role == ChatRole.assistant
                                ? () => controller.speakMessage(
                                    messages[index].text,
                                  )
                                : () {},
                            speakTooltip: controller.copy.speakAgain,
                            onRetry: messages[index].canRetry
                                ? () => controller.retryMessage(
                                    messages[index],
                                    useGlobalMode: useGlobalMode,
                                  )
                                : null,
                            retryTooltip: controller.copy.retry,
                            showTimestamp: _showMessageTimes,
                            onTap: _toggleMessageTimes,
                          ),
                      ],
                      if (showRun && lastAssistantIndex < 0)
                        AiRunActivity(
                          events: runEvents,
                          isRunning: controller.isSendingForContext(
                            useGlobalMode: useGlobalMode,
                          ),
                          palette: palette,
                          copy: controller.copy,
                          contextKey: selectedConversation.id,
                          initialExpanded: controller.aiRunExpandedForContext(
                            useGlobalMode: useGlobalMode,
                          ),
                          onExpandedChanged: (bool expanded) =>
                              controller.setAiRunExpandedForContext(
                                useGlobalMode: useGlobalMode,
                                expanded: expanded,
                              ),
                        ),
                    ],
                  ),
                  if (_showJumpToBottom)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 14,
                      child: Center(
                        child: FilledButton.tonalIcon(
                          onPressed: _jumpToBottom,
                          icon: const Icon(Icons.south_rounded, size: 17),
                          label: Text(
                            _hasNewContent
                                ? controller.copy.aiNewMessages
                                : controller.copy.desktopJumpToBottom,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.surfaceContainer,
                            foregroundColor: palette.textPrimary,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(composerInset, 9, composerInset, 18),
              child: _DesktopComposer(
                controller: controller,
                draftController: _draftController,
                useGlobalMode: useGlobalMode,
                onSend: _send,
                onOpenContext: () => _showAssistantSheet(
                  title: controller.copy.desktopContextTitle,
                  child: _DesktopContextPanel(
                    controller: controller,
                    useGlobalMode: useGlobalMode,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Reveals a specific answer after navigation from the notification center.
  /// Missing or expired message IDs are intentionally ignored because the
  /// conversation itself is still a valid destination.
  void revealMessage(String? messageId) {
    final String? normalized = messageId?.trim();
    if (normalized == null || normalized.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = _messageKeys[normalized]?.currentContext;
      if (target == null || !mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.2,
      );
    });
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final String? conversationId = controller.selectedConversationId;
    final bool contextChanged = conversationId != _lastConversationId;
    if (contextChanged) {
      _saveScrollPosition();
      _lastConversationId = conversationId;
      _showJumpToBottom = false;
      _hasNewContent = false;
      _followNewMessages = true;
      _forceScrollToBottom = false;
    } else if (!_followNewMessages) {
      _showJumpToBottom = true;
      _hasNewContent = true;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (contextChanged) {
        final double? saved = conversationId == null
            ? null
            : _scrollOffsets[conversationId];
        if (saved == null) {
          _scrollToBottom(animated: false);
        } else {
          _scrollController.jumpTo(
            saved.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      } else if (_forceScrollToBottom || _followNewMessages) {
        _scrollToBottom(
          animated: !controller.isSendingForContext(
            useGlobalMode: controller.selectedConversation?.isGlobal ?? false,
          ),
        );
      }
      _forceScrollToBottom = false;
    });
  }

  bool _forceScrollToBottom = true;

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final ScrollPosition position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 96;
  }

  void _handleScrollChanged() {
    if (!mounted) return;
    final bool nearBottom = _isNearBottom();
    if (nearBottom) {
      if (_followNewMessages || !_showJumpToBottom) return;
      setState(() {
        _followNewMessages = true;
        _showJumpToBottom = false;
        _hasNewContent = false;
      });
      return;
    }
    _saveScrollPosition();
    if (_followNewMessages || !_showJumpToBottom) {
      setState(() {
        _followNewMessages = false;
        _showJumpToBottom = true;
      });
    }
  }

  void _saveScrollPosition() {
    final String? conversationId = _lastConversationId;
    if (conversationId == null || !_scrollController.hasClients) return;
    _scrollOffsets[conversationId] = _scrollController.position.pixels;
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final double target = _scrollController.position.maxScrollExtent;
    if (!animated) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _jumpToBottom() {
    _followNewMessages = true;
    _showJumpToBottom = false;
    _hasNewContent = false;
    _scrollToBottom();
    if (mounted) setState(() {});
  }

  void _scheduleInitialScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollToBottom(animated: false);
      _followNewMessages = true;
      _showJumpToBottom = false;
      _hasNewContent = false;
    });
  }

  Future<void> _showAssistantSheet({
    required String title,
    required Widget child,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: SizedBox(
          height: math.min(MediaQuery.sizeOf(context).height * 0.72, 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleMessageTimes() {
    _messageTimesTimer?.cancel();
    if (_showMessageTimes) {
      setState(() => _showMessageTimes = false);
      return;
    }
    setState(() => _showMessageTimes = true);
    _messageTimesTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showMessageTimes = false);
    });
  }

  Future<void> _send() async {
    final String text = _draftController.text.trim();
    final bool useGlobalMode = controller.selectedConversationIsGlobal;
    if (text.isEmpty ||
        controller.isSendingForContext(useGlobalMode: useGlobalMode)) {
      return;
    }
    if (!controller.hasSelectedAiModel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.copy.aiApiModelRequired)),
      );
      return;
    }
    _draftController.clear();
    await controller.sendPrompt(text, useGlobalMode: useGlobalMode);
  }
}

String _desktopMessageMeta(ChatMessage message, AppCopy copy) {
  if (message.role == ChatRole.user) return copy.activityJustNow;
  final String source = switch (message.source) {
    AnswerSource.official ||
    AnswerSource.rulebook => copy.desktopAssistantRuleMeta,
    AnswerSource.community => copy.answerSourceCommunity,
    AnswerSource.web => copy.answerSourceWeb,
    AnswerSource.modelKnowledge => copy.answerSourceModelKnowledge,
    AnswerSource.generalAdvice => copy.answerSourceGeneral,
    AnswerSource.insufficient => copy.answerSourceInsufficient,
    null => copy.desktopAssistantRuleMeta,
  };
  return '$source · ${copy.activityJustNow}';
}

class _DesktopAssistantEmptyPane extends StatelessWidget {
  const _DesktopAssistantEmptyPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.forum_outlined, size: 42, color: palette.primary),
            const SizedBox(height: 14),
            Text(
              copy.desktopNoSession,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              copy.desktopNoSessionHint,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => controller.openGlobalAssistant(),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(copy.desktopOpenGlobalAssistant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopAssistantSessions extends StatelessWidget {
  const _DesktopAssistantSessions({
    required this.controller,
    this.embedded = false,
  });

  final AppController controller;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      margin: embedded ? const EdgeInsets.only(left: 28) : EdgeInsets.zero,
      padding: embedded
          ? const EdgeInsets.fromLTRB(15, 12, 4, 4)
          : const EdgeInsets.all(14),
      decoration: embedded
          ? BoxDecoration(
              border: Border(left: BorderSide(color: palette.outline)),
            )
          : BoxDecoration(
              color: palette.surface.withValues(alpha: 0.6),
              border: Border(right: BorderSide(color: palette.outline)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  controller.copy.desktopSessionTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: controller.copy.desktopOpenGlobalAssistant,
                visualDensity: VisualDensity.compact,
                onPressed: controller.openGlobalAssistant,
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (embedded)
            Flexible(
              fit: FlexFit.loose,
              child: ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: _sessionRows(),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _sessionRows(),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sessionRows() {
    return <Widget>[
      for (final AiConversation conversation in controller.conversations)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: _DesktopSessionRow(
            icon: conversation.id == controller.selectedConversationId
                ? Icons.chat_rounded
                : Icons.chat_bubble_outline_rounded,
            title: conversation.title,
            subtitle: controller.copy.desktopConversationSummary(
              conversation.isGlobal,
              conversation.messageCount,
            ),
            selected: conversation.id == controller.selectedConversationId,
            onTap: () => controller.selectConversation(conversation.id),
          ),
        ),
    ];
  }
}

class _DesktopSessionRow extends StatelessWidget {
  const _DesktopSessionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: _desktopOptionDecoration(
          palette,
          selected: selected,
          radius: 7,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? palette.primary : palette.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: selected
                                  ? palette.textPrimary
                                  : palette.textSecondary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantAppMark extends StatelessWidget {
  const _AssistantAppMark();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Image.asset(
        'branding/app_icon.png',
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(Icons.casino_rounded),
                ),
      ),
    );
  }
}

class _AssistantStatusDot extends StatelessWidget {
  const _AssistantStatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 8, height: 8),
    );
  }
}

class _AssistantStatusLabel extends StatelessWidget {
  const _AssistantStatusLabel({required this.label, required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _AssistantStatusDot(color: palette.success),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _DesktopContextPanel extends StatelessWidget {
  const _DesktopContextPanel({
    required this.controller,
    required this.useGlobalMode,
  });

  final AppController controller;
  final bool useGlobalMode;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AiConversation? selectedConversation =
        controller.selectedConversation;
    final GameInfo selectedGame = selectedConversation?.gameId == null
        ? controller.featuredGame
        : controller.games.firstWhere(
            (GameInfo item) => item.id == selectedConversation!.gameId,
            orElse: () => controller.featuredGame,
          );
    final bool smartSupplement = controller.allowSmartSupplement(
      useGlobalMode: useGlobalMode,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.6),
        border: Border(left: BorderSide(color: palette.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            controller.copy.desktopContextTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 13),
          if (!useGlobalMode || controller.globalUseCurrentGameKnowledge) ...[
            _DesktopContextLine(
              icon: Icons.casino_outlined,
              label: selectedGame.title,
            ),
            _DesktopContextLine(
              icon: Icons.menu_book_outlined,
              label: controller.copy.desktopRulebook,
            ),
            _DesktopContextLine(
              icon: Icons.fact_check_outlined,
              label: controller.copy.desktopFaq,
            ),
          ],
          const SizedBox(height: 18),
          Text(
            controller.copy.desktopAnswerModeTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _DesktopContextToggle(
            label: controller.copy.desktopOfficialFirst,
            selected: !smartSupplement,
            onTap: () => controller.setAllowSmartSupplement(
              false,
              useGlobalMode: useGlobalMode,
            ),
          ),
          _DesktopContextToggle(
            label: controller.copy.desktopSmartSupplement,
            selected: smartSupplement,
            onTap: () => controller.setAllowSmartSupplement(
              true,
              useGlobalMode: useGlobalMode,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopContextLine extends StatelessWidget {
  const _DesktopContextLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AppPalette.of(context).primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _DesktopContextToggle extends StatelessWidget {
  const _DesktopContextToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: _desktopOptionDecoration(
            palette,
            selected: selected,
            radius: 9,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
              child: Row(
                children: <Widget>[
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 17,
                    color: selected ? palette.primary : palette.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopComposer extends StatelessWidget {
  const _DesktopComposer({
    required this.controller,
    required this.draftController,
    required this.useGlobalMode,
    required this.onSend,
    required this.onOpenContext,
  });

  final AppController controller;
  final TextEditingController draftController;
  final bool useGlobalMode;
  final Future<void> Function() onSend;
  final VoidCallback onOpenContext;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    return AnimatedBuilder(
      animation: draftController,
      builder: (BuildContext context, Widget? child) {
        final bool isSending = controller.isSendingForContext(
          useGlobalMode: useGlobalMode,
        );
        final bool canSend =
            draftController.text.trim().isNotEmpty && !isSending;
        final bool smartSupplement = controller.allowSmartSupplement(
          useGlobalMode: useGlobalMode,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AssistantFeatureChip(
                  icon: smartSupplement
                      ? Icons.auto_awesome_rounded
                      : Icons.menu_book_rounded,
                  label: smartSupplement
                      ? copy.smartSupplementLabel
                      : copy.knowledgeOnlyLabel,
                  foregroundColor: smartSupplement
                      ? palette.secondary
                      : palette.primary,
                  backgroundColor:
                      (smartSupplement ? palette.secondary : palette.primary)
                          .withValues(alpha: 0.14),
                  onRemove: onOpenContext,
                ),
              ),
            ),
            Container(
              key: const ValueKey<String>('desktop-composer-box'),
              constraints: const BoxConstraints(minHeight: 52),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.outline),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 4, 7, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _DesktopAnswerModeSelector(
                      controller: controller,
                      useGlobalMode: useGlobalMode,
                      enabled: !isSending,
                    ),
                    Expanded(
                      child: TextField(
                        controller: draftController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: canSend ? (_) => onSend() : null,
                        decoration: InputDecoration(
                          hintText: copy.desktopInputHint,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 7,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _DesktopModelAndReasoningSelector(
                      controller: controller,
                      enabled: !isSending,
                    ),
                    IconButton(
                      key: const ValueKey<String>('desktop-composer-send'),
                      tooltip: isSending
                          ? copy.desktopStopGenerating
                          : copy.desktopSend,
                      onPressed: isSending
                          ? () => controller.stopGenerating(
                              useGlobalMode: useGlobalMode,
                            )
                          : canSend
                          ? onSend
                          : null,
                      style: IconButton.styleFrom(
                        backgroundColor: canSend || controller.isSending
                            ? palette.primary
                            : palette.disabledBackground,
                        foregroundColor: canSend || controller.isSending
                            ? palette.onPrimary
                            : palette.disabledForeground,
                        minimumSize: const Size.square(37),
                        maximumSize: const Size.square(37),
                        fixedSize: const Size.square(37),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      icon: Icon(
                        isSending
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopAnswerModeSelector extends StatelessWidget {
  const _DesktopAnswerModeSelector({
    required this.controller,
    required this.useGlobalMode,
    required this.enabled,
  });

  final AppController controller;
  final bool useGlobalMode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    final bool smartSupplement = controller.allowSmartSupplement(
      useGlobalMode: useGlobalMode,
    );
    return PopupMenuButton<bool>(
      key: const ValueKey<String>('desktop-answer-mode-selector'),
      enabled: enabled,
      tooltip: copy.desktopAnswerModeTitle,
      onSelected: (bool value) {
        if (value == smartSupplement) return;
        unawaited(
          controller.setAllowSmartSupplement(
            value,
            useGlobalMode: useGlobalMode,
          ),
        );
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
        PopupMenuItem<bool>(
          value: false,
          child: _AnswerModeMenuItem(
            icon: Icons.menu_book_outlined,
            label: copy.desktopOfficialFirst,
            selected: !smartSupplement,
          ),
        ),
        PopupMenuItem<bool>(
          value: true,
          child: _AnswerModeMenuItem(
            icon: Icons.auto_awesome_outlined,
            label: copy.desktopSmartSupplement,
            selected: smartSupplement,
          ),
        ),
      ],
      child: _DesktopComposerIcon(
        icon: Icons.add_rounded,
        palette: palette,
        tooltip: copy.desktopAnswerModeTitle,
      ),
    );
  }
}

class _AnswerModeMenuItem extends StatelessWidget {
  const _AnswerModeMenuItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: selected ? palette.primary : null),
        const SizedBox(width: 9),
        Expanded(child: Text(label)),
        if (selected)
          Icon(Icons.check_rounded, size: 17, color: palette.primary),
      ],
    );
  }
}

class _DesktopComposerIcon extends StatelessWidget {
  const _DesktopComposerIcon({
    required this.icon,
    required this.palette,
    required this.tooltip,
  });

  final IconData icon;
  final AppPalette palette;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 37,
        height: 37,
        child: Icon(icon, color: palette.textSecondary),
      ),
    );
  }
}

const String _desktopRefreshModelsAction = '__refresh_models__';

class _DesktopModelAndReasoningSelector extends StatelessWidget {
  const _DesktopModelAndReasoningSelector({
    required this.controller,
    required this.enabled,
  });

  final AppController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    final String selectedModel = controller.aiApiConfig.model.trim();
    final AiReasoningEffort selectedReasoning =
        controller.aiApiConfig.reasoningEffort;
    final List<String> modelIds = <String>[];
    if (selectedModel.isNotEmpty) modelIds.add(selectedModel);
    for (final model in controller.availableAiModels) {
      if (model.id.trim().isNotEmpty && !modelIds.contains(model.id)) {
        modelIds.add(model.id);
      }
    }
    return PopupMenuButton<String>(
      key: const ValueKey<String>('desktop-model-selector'),
      enabled: enabled,
      tooltip: copy.desktopModel,
      onSelected: (String value) {
        if (value == _desktopRefreshModelsAction) {
          unawaited(controller.refreshAiModels());
          return;
        }
        if (value.startsWith('model:')) {
          final String model = value.substring('model:'.length).trim();
          if (model.isNotEmpty && model != selectedModel) {
            unawaited(controller.setAiModel(model));
          }
          return;
        }
        if (value.startsWith('reasoning:')) {
          final AiReasoningEffort effort = AiReasoningEffortX.fromStored(
            value.substring('reasoning:'.length),
          );
          if (effort != selectedReasoning) {
            unawaited(controller.setAiReasoningEffort(effort));
          }
        }
      },
      itemBuilder: (BuildContext context) {
        final List<PopupMenuEntry<String>> items = <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            value: 'model-header',
            child: Text(copy.desktopModel),
          ),
          if (modelIds.isEmpty)
            PopupMenuItem<String>(
              enabled: false,
              value: 'model-empty',
              child: Text(_modelStatusLabel(controller, copy)),
            )
          else
            for (final modelId in modelIds)
              PopupMenuItem<String>(
                value: 'model:$modelId',
                child: _DesktopSelectorMenuItem(
                  label: _modelLabel(controller, modelId),
                  selected: modelId == selectedModel,
                ),
              ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            enabled: false,
            value: 'reasoning-header',
            child: Text(copy.aiApiReasoningEffortLabel),
          ),
          for (final AiReasoningEffort effort in AiReasoningEffort.values)
            PopupMenuItem<String>(
              value: 'reasoning:${effort.storageValue}',
              child: _DesktopSelectorMenuItem(
                label: copy.aiApiReasoningEffortName(effort),
                selected: effort == selectedReasoning,
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: _desktopRefreshModelsAction,
            child: Row(
              children: <Widget>[
                const Icon(Icons.refresh_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  controller.aiModelLoadState == AiModelLoadState.loading
                      ? copy.aiApiModelsLoading
                      : copy.desktopRefreshModels,
                ),
              ],
            ),
          ),
        ];
        return items;
      },
      child: _DesktopModelReasoningChoice(
        model: selectedModel.isEmpty
            ? copy.desktopModel
            : _modelLabel(controller, selectedModel),
        reasoning: copy.aiApiReasoningEffortName(selectedReasoning),
        palette: palette,
      ),
    );
  }

  String _modelLabel(AppController controller, String id) {
    for (final model in controller.availableAiModels) {
      if (model.id == id) return model.label;
    }
    return id;
  }

  String _modelStatusLabel(AppController controller, AppCopy copy) {
    return switch (controller.aiModelLoadState) {
      AiModelLoadState.loading => copy.aiApiModelsLoading,
      AiModelLoadState.failure => copy.aiApiModelsFailed,
      AiModelLoadState.empty => copy.aiApiModelsEmpty,
      _ => copy.aiApiModelsNotLoaded,
    };
  }
}

class _DesktopSelectorMenuItem extends StatelessWidget {
  const _DesktopSelectorMenuItem({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (selected)
          Icon(Icons.check_rounded, size: 17, color: palette.primary),
      ],
    );
  }
}

class _DesktopModelReasoningChoice extends StatelessWidget {
  const _DesktopModelReasoningChoice({
    required this.model,
    required this.reasoning,
    required this.palette,
  });

  final String model;
  final String reasoning;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 0, maxWidth: 165),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              reasoning,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopLibraryPane extends StatefulWidget {
  const DesktopLibraryPane({
    super.key,
    required this.controller,
    this.onOpenRules,
    this.filter,
    this.onFilterChanged,
  });

  final AppController controller;
  final ValueChanged<DesktopLibraryResource>? onOpenRules;
  final DesktopLibraryResourceType? filter;
  final ValueChanged<DesktopLibraryResourceType?>? onFilterChanged;

  @override
  State<DesktopLibraryPane> createState() => DesktopLibraryPaneState();
}

class DesktopLibraryPaneState extends State<DesktopLibraryPane> {
  String? _openingItemId;
  String? _downloadingItemId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.controller.refreshLibraryResources());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = widget.controller.copy;
    if (!widget.controller.hasGames) {
      return _DesktopNoGamesPane(
        controller: widget.controller,
        title: copy.desktopLibraryEmptyTitle,
        message: copy.desktopLibraryEmptyMessage,
      );
    }
    final AppPalette palette = AppPalette.of(context);
    final List<DesktopLibraryResource> items =
        widget.controller.libraryResources;
    final List<DesktopLibraryResource> visible = widget.filter == null
        ? items
        : items
              .where(
                (DesktopLibraryResource item) => item.type == widget.filter,
              )
              .toList(growable: false);
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    copy.desktopLibraryTitle,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showImportComingSoon,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(copy.desktopImport),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey<String>('desktop-library-refresh'),
                  tooltip: copy.desktopRefreshLibrary,
                  onPressed: widget.controller.isRefreshingLibrary
                      ? null
                      : () => unawaited(
                          widget.controller.refreshLibraryResources(
                            force: true,
                          ),
                        ),
                  icon: widget.controller.isRefreshingLibrary
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        ),
        if (widget.controller.libraryLoadState == LibraryLoadState.failure)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            sliver: SliverToBoxAdapter(
              child: _LibraryStatusBanner(
                icon: Icons.cloud_off_rounded,
                color: palette.warning,
                message: copy.desktopLibraryUnavailable,
                detail: widget.controller.libraryLoadError,
                actionLabel: copy.desktopRetry,
                onAction: () => unawaited(
                  widget.controller.refreshLibraryResources(force: true),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.outline),
              ),
              child: Wrap(
                spacing: 4,
                children: <Widget>[
                  _LibraryFilterChip(
                    label: copy.desktopAll,
                    selected: widget.filter == null,
                    onTap: () => widget.onFilterChanged?.call(null),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopRulebook,
                    selected:
                        widget.filter == DesktopLibraryResourceType.rulebook,
                    onTap: () => widget.onFilterChanged?.call(
                      DesktopLibraryResourceType.rulebook,
                    ),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopFaq,
                    selected: widget.filter == DesktopLibraryResourceType.faq,
                    onTap: () => widget.onFilterChanged?.call(
                      DesktopLibraryResourceType.faq,
                    ),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopLibraryPlayerAid,
                    selected:
                        widget.filter == DesktopLibraryResourceType.playerAid,
                    onTap: () => widget.onFilterChanged?.call(
                      DesktopLibraryResourceType.playerAid,
                    ),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopLibraryOther,
                    selected: widget.filter == DesktopLibraryResourceType.other,
                    onTap: () => widget.onFilterChanged?.call(
                      DesktopLibraryResourceType.other,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.controller.libraryLoadState == LibraryLoadState.loading &&
            items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (widget.controller.libraryLoadState == LibraryLoadState.empty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 56),
              child: Center(child: Text(copy.desktopLibraryNoResources)),
            ),
          )
        else if (visible.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 56),
              child: Center(child: Text(copy.desktopLibraryFilterNoResources)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (BuildContext context, int index) {
                final DesktopLibraryResource resource = visible[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LibraryItemTile(
                    key: ValueKey<String>('library-item-${resource.id}'),
                    resource: resource,
                    copy: copy,
                    isLoading:
                        _openingItemId == resource.id ||
                        _downloadingItemId == resource.id,
                    isDownloading: _downloadingItemId == resource.id,
                    onOpen: () => _openItem(resource),
                    onOpenRules: widget.onOpenRules == null
                        ? null
                        : () => widget.onOpenRules!(resource),
                    onDownload: () => _downloadItem(resource),
                    onDelete: () => _deleteItem(resource),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showImportComingSoon() {
    final AppCopy copy = widget.controller.copy;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copy.desktopImportComingSoon)));
  }

  Future<void> _openItem(DesktopLibraryResource resource) async {
    if (_openingItemId != null || _downloadingItemId != null) return;
    if (!resource.canOpen) {
      final AppCopy copy = widget.controller.copy;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(copy.desktopOpenUnavailableMessage)),
        );
      return;
    }

    setState(() => _openingItemId = resource.id);
    try {
      final ResolvedDocument? document = await widget.controller
          .resolveLibraryResource(resource);
      if (!mounted) return;
      if (document == null) {
        _showDocumentUnavailable(resource.title);
        return;
      }
      await _openResolvedDocument(
        document,
        '${resource.gameTitle} · ${_displayResourceTitle(resource)}',
      );
    } catch (error) {
      if (mounted) _showDocumentUnavailable(resource.title, error: error);
    } finally {
      if (mounted) setState(() => _openingItemId = null);
    }
  }

  Future<void> _downloadItem(DesktopLibraryResource resource) async {
    if (_openingItemId != null || _downloadingItemId != null) return;
    if (kIsWeb) {
      _showDownloadUnavailable('当前 Web 端不支持选择本地下载目录');
      return;
    }

    setState(() => _downloadingItemId = resource.id);
    try {
      final String? directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: widget.controller.copy.desktopDownloadDirectory,
      );
      if (!mounted || directory == null || directory.trim().isEmpty) {
        return;
      }
      final String? destination = await widget.controller
          .downloadLibraryResource(
            resource: resource,
            directoryPath: directory,
          );
      if (!mounted) return;
      if (destination == null) {
        _showDownloadUnavailable(widget.controller.copy.desktopDownloadFailed);
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              widget.controller.copy.desktopDownloadedTo(destination),
            ),
          ),
        );
    } catch (error) {
      if (mounted) {
        _showDownloadUnavailable(
          widget.controller.copy.desktopDownloadError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingItemId = null);
    }
  }

  void _deleteItem(DesktopLibraryResource resource) {
    final AppCopy copy = widget.controller.copy;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copy.desktopDeleteUnavailable)));
  }

  String _displayResourceTitle(DesktopLibraryResource resource) {
    final AppCopy copy = widget.controller.copy;
    switch (resource.type) {
      case DesktopLibraryResourceType.rulebook:
        return resource.isRemote
            ? copy.desktopRulebook
            : '官方${copy.desktopRulebook}';
      case DesktopLibraryResourceType.faq:
        return resource.isRemote ? copy.desktopFaq : '官方 ${copy.desktopFaq}';
      case DesktopLibraryResourceType.playerAid:
        return copy.desktopLibraryPlayerAid;
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        return resource.title.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    }
  }

  void _showDownloadUnavailable(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openResolvedDocument(
    ResolvedDocument document,
    String title,
  ) async {
    if (document.renderType == DocumentRenderType.markdown) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MarkdownDocumentScreen(
            controller: widget.controller,
            remotePath: document.remotePath,
            title: title,
          ),
        ),
      );
      return;
    }
    if (document.renderType != DocumentRenderType.pdf) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LibraryResourceDocumentScreen(
            controller: widget.controller,
            document: document,
            title: title,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PdfDocumentScreen(
          controller: widget.controller,
          title: title,
          remotePath: document.remotePath,
        ),
      ),
    );
  }

  void _showDocumentUnavailable(String title, {Object? error}) {
    final String suffix = error == null ? '' : '：$error';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$title暂不可用$suffix')));
  }
}

class _LibraryStatusBanner extends StatelessWidget {
  const _LibraryStatusBanner({
    required this.icon,
    required this.color,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null && detail!.trim().isNotEmpty)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _LibraryFilterChip extends StatelessWidget {
  const _LibraryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? palette.primary.withValues(alpha: 0.16)
            : null,
        foregroundColor: selected ? palette.textPrimary : palette.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(
          color: selected ? palette.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Text(label),
    );
  }
}

class _LibraryItemTile extends StatelessWidget {
  const _LibraryItemTile({
    super.key,
    required this.resource,
    required this.copy,
    required this.isLoading,
    required this.isDownloading,
    required this.onOpen,
    this.onOpenRules,
    required this.onDownload,
    required this.onDelete,
  });

  final DesktopLibraryResource resource;
  final AppCopy copy;
  final bool isLoading;
  final bool isDownloading;
  final VoidCallback onOpen;
  final VoidCallback? onOpenRules;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final IconData icon = switch (resource.type) {
      DesktopLibraryResourceType.rulebook => Icons.menu_book_outlined,
      DesktopLibraryResourceType.faq => Icons.fact_check_outlined,
      DesktopLibraryResourceType.assetIndex => Icons.description_outlined,
      DesktopLibraryResourceType.reference => Icons.description_outlined,
      DesktopLibraryResourceType.playerAid => Icons.description_outlined,
      DesktopLibraryResourceType.supplement => Icons.description_outlined,
      DesktopLibraryResourceType.other => Icons.description_outlined,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading || !resource.canOpen ? null : onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.outline),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: palette.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${resource.gameTitle} · ${_displayTitle()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_typeLabel()} · ${_languageLabel()} · ${_formatLabel()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...<Widget>[
                if (onOpenRules != null)
                  TextButton(
                    onPressed: onOpenRules,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF66C0F4),
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(3),
                        side: const BorderSide(color: Color(0x4066C0F4)),
                      ),
                    ),
                    child: const Text('条款问答'),
                  ),
                PopupMenuButton<_LibraryItemAction>(
                  key: ValueKey<String>('library-more-${resource.id}'),
                  tooltip: copy.desktopMore,
                  onSelected: (_LibraryItemAction action) {
                    switch (action) {
                      case _LibraryItemAction.open:
                        onOpen();
                      case _LibraryItemAction.download:
                        onDownload();
                      case _LibraryItemAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<_LibraryItemAction>>[
                        PopupMenuItem<_LibraryItemAction>(
                          value: _LibraryItemAction.open,
                          enabled: resource.canOpen,
                          child: Text(
                            resource.canOpen
                                ? copy.desktopOpen
                                : copy.desktopOpenUnavailable,
                          ),
                        ),
                        PopupMenuItem<_LibraryItemAction>(
                          value: _LibraryItemAction.download,
                          child: Text(copy.desktopDownload),
                        ),
                        PopupMenuItem<_LibraryItemAction>(
                          value: _LibraryItemAction.delete,
                          child: Text(copy.desktopDelete),
                        ),
                      ],
                  icon: isDownloading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _displayTitle() {
    switch (resource.type) {
      case DesktopLibraryResourceType.rulebook:
        return copy.desktopRulebook;
      case DesktopLibraryResourceType.faq:
        return copy.desktopFaq;
      case DesktopLibraryResourceType.playerAid:
        return copy.desktopLibraryPlayerAid;
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        final String title = resource.title.trim();
        return title
            .replaceAll(RegExp(r'[_-]+'), ' ')
            .replaceFirst(RegExp(r'\.[^.]+$'), '')
            .trim();
    }
  }

  String _typeLabel() {
    switch (resource.type) {
      case DesktopLibraryResourceType.rulebook:
        return copy.desktopRulebook;
      case DesktopLibraryResourceType.faq:
        return copy.desktopFaq;
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.playerAid:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        return copy.desktopLibraryOther;
    }
  }

  String _languageLabel() {
    final String language = resource.language.trim();
    if (language == '中文') return copy.isChinese ? '中文' : 'Chinese';
    if (language == '英文') return copy.isChinese ? '英文' : 'English';
    if (language == '多语言') return copy.isChinese ? '多语言' : 'Multilingual';
    return copy.isChinese ? language : 'Unspecified';
  }

  String _formatLabel() {
    switch (resource.format) {
      case DesktopLibraryResourceFormat.markdown:
        return 'Markdown';
      case DesktopLibraryResourceFormat.pdf:
        return 'PDF';
      case DesktopLibraryResourceFormat.html:
        return 'HTML';
      case DesktopLibraryResourceFormat.text:
        return copy.isChinese ? '文本' : 'Text';
      case DesktopLibraryResourceFormat.image:
        return copy.isChinese ? '图片' : 'Image';
      case DesktopLibraryResourceFormat.other:
        return copy.isChinese ? '文件' : 'File';
    }
  }
}

enum _LibraryItemAction { open, download, delete }

class DesktopAdvancedSettingsPane extends StatelessWidget {
  const DesktopAdvancedSettingsPane({
    super.key,
    required this.controller,
    required this.onOpenAbout,
  });

  final AppController controller;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      children: <Widget>[
        Text(
          '偏好',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: AppPalette.of(context).textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        _DesktopSettingsCard(
          title: '外观',
          icon: Icons.palette_outlined,
          children: <Widget>[
            _DesktopSettingDropdown<ColorSchemeOption>(
              label: '主题',
              value: controller.colorScheme,
              values: ColorSchemeOption.values,
              labelBuilder: controller.copy.colorSchemeName,
              onChanged: (ColorSchemeOption? value) {
                if (value != null) controller.setColorScheme(value);
              },
            ),
            _DesktopSettingDropdown<AppLanguageValue>(
              label: '语言',
              value: _appLanguageValueFrom(controller.language),
              values: AppLanguageValue.values,
              labelBuilder: (AppLanguageValue value) => value.label,
              onChanged: (AppLanguageValue? value) {
                if (value != null) controller.setLanguage(value.language);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DesktopSettingsCard(
          title: 'AI 服务',
          icon: Icons.smart_toy_outlined,
          children: <Widget>[
            _DesktopSettingInfo(
              label: '供应商',
              value: controller.aiApiConfig.name,
            ),
            _DesktopSettingInfo(
              label: '模型',
              value: controller.hasSelectedAiModel
                  ? controller.aiApiConfig.model
                  : '未选择',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => LanguageSheet(
                    controller: controller,
                    onOpenAbout: onOpenAbout,
                  ),
                ),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('详细设置'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DesktopSettingsCard(
          title: '行为',
          icon: Icons.tune_rounded,
          children: <Widget>[
            _DesktopSettingSwitch(
              label: '语音朗读',
              value: controller.voiceReplyEnabled,
              enabled: controller.voiceReplyAvailable,
              onChanged: controller.setVoiceReplyEnabled,
            ),
            _DesktopSettingSwitch(
              label: '启动时检查更新',
              value: controller.checkForUpdates,
              onChanged: controller.setCheckForUpdates,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onOpenAbout,
            icon: const Icon(Icons.info_outline_rounded),
            label: const Text('关于桌游导师'),
          ),
        ),
      ],
    );
  }
}

class _DesktopSettingsCard extends StatelessWidget {
  const _DesktopSettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: palette.primary, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _DesktopSettingInfo extends StatelessWidget {
  const _DesktopSettingInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
        ),
      ),
    );
  }
}

class _DesktopSettingDropdown<T> extends StatelessWidget {
  const _DesktopSettingDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: values
            .map(
              (T item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item)),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged,
      ),
    );
  }
}

class _DesktopSettingSwitch extends StatelessWidget {
  const _DesktopSettingSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

enum AppLanguageValue { chinese, english }

extension on AppLanguageValue {
  String get label => this == AppLanguageValue.chinese ? '简体中文' : 'English';

  AppLanguage get language =>
      this == AppLanguageValue.chinese ? AppLanguage.zhHans : AppLanguage.en;
}

AppLanguageValue _appLanguageValueFrom(AppLanguage language) {
  return language == AppLanguage.en
      ? AppLanguageValue.english
      : AppLanguageValue.chinese;
}
