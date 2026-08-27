import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/app_activity.dart';
import '../../models/app_language.dart';
import '../../models/ai_conversation.dart';
import '../../models/chat_message.dart';
import '../../models/color_scheme_option.dart';
import '../../models/game_info.dart';
import '../../models/remote_library_update.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';
import '../widgets/language_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/desktop_resolved_image.dart';
import 'desktop_game_detail_pane.dart';

enum _DesktopDestination {
  home,
  games,
  gameDetail,
  assistant,
  library,
  settings,
}

class DesktopWorkspaceScreen extends StatefulWidget {
  const DesktopWorkspaceScreen({
    super.key,
    required this.controller,
    required this.onOpenAbout,
  });

  final AppController controller;
  final VoidCallback onOpenAbout;

  @override
  State<DesktopWorkspaceScreen> createState() => _DesktopWorkspaceScreenState();
}

class _DesktopWorkspaceScreenState extends State<DesktopWorkspaceScreen> {
  _DesktopDestination _destination = _DesktopDestination.home;
  _DesktopDestination _detailReturnDestination = _DesktopDestination.games;
  final GlobalKey _activityButtonKey = GlobalKey();
  RemoteLibraryUpdate? _lastSeenUpdate;
  bool _showingUpdateDialog = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowLibraryUpdateDialog();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    return Scaffold(
      backgroundColor: palette.pageBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxWidth < 980;
            return Row(
              children: <Widget>[
                _DesktopSidebar(
                  destination: _destination,
                  compact: compact,
                  onSelected: _selectDestination,
                  onOpenAbout: widget.onOpenAbout,
                  controller: widget.controller,
                ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      _DesktopTopBar(
                        title: _destinationTitle(copy),
                        compact: compact,
                        activityButtonKey: _activityButtonKey,
                        onNew: () =>
                            _selectDestination(_DesktopDestination.games),
                        onOpenActivities: _openActivityCenter,
                        unreadActivityCount:
                            widget.controller.unreadActivityCount,
                        primaryAction:
                            _destination == _DesktopDestination.gameDetail
                            ? () => _openAssistantForGame(
                                widget.controller.selectedGame.id,
                              )
                            : null,
                        primaryLabel:
                            _destination == _DesktopDestination.gameDetail
                            ? copy.askAiAssistant
                            : null,
                      ),
                      Expanded(child: _buildPage(compact)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPage(bool compact) {
    final AppController controller = widget.controller;
    switch (_destination) {
      case _DesktopDestination.home:
        return _DesktopHomePane(
          controller: controller,
          compact: compact,
          onOpenGames: () => _selectDestination(_DesktopDestination.games),
          onOpenAssistant: () =>
              _openAssistantForGame(controller.featuredGame.id),
          onOpenLibrary: () => _selectDestination(_DesktopDestination.library),
          onOpenGame: _openGame,
          onOpenActivities: _openActivityCenter,
        );
      case _DesktopDestination.games:
        return _DesktopGamesPane(controller: controller, onOpenGame: _openGame);
      case _DesktopDestination.gameDetail:
        return DesktopGameDetailPane(
          controller: controller,
          game: controller.selectedGame,
          onBack: () => _selectDestination(_detailReturnDestination),
          onAskAi: () => _openAssistantForGame(controller.selectedGame.id),
        );
      case _DesktopDestination.assistant:
        return _DesktopAssistantPane(controller: controller);
      case _DesktopDestination.library:
        return _DesktopLibraryPane(controller: controller);
      case _DesktopDestination.settings:
        return _DesktopSettingsPane(
          controller: controller,
          onOpenAbout: widget.onOpenAbout,
        );
    }
  }

  void _selectDestination(_DesktopDestination destination) {
    if (!mounted) return;
    if (destination == _DesktopDestination.assistant) {
      _openAssistant();
      return;
    }
    setState(() => _destination = destination);
  }

  /// Opens the generic desktop assistant entry point. It reuses the current
  /// session when one is selected; otherwise it creates the global session.
  /// No game-scoped session is created merely by navigating to the assistant
  /// section.
  void _openAssistant() {
    if (widget.controller.selectedConversation == null) {
      widget.controller.openGlobalAssistant();
    }
    if (!mounted) return;
    setState(() => _destination = _DesktopDestination.assistant);
  }

  /// Enters the assistant in the context of exactly one game. This is used by
  /// the game detail and featured-game actions, so the session is created only
  /// after the user explicitly chooses that game.
  void _openAssistantForGame(String gameId) {
    if (!widget.controller.openGameAssistant(gameId)) {
      return;
    }
    if (!mounted) return;
    setState(() => _destination = _DesktopDestination.assistant);
  }

  void _openGame(GameInfo game) {
    widget.controller.selectGame(game.id);
    setState(() {
      _detailReturnDestination = _destination == _DesktopDestination.gameDetail
          ? _DesktopDestination.games
          : _destination;
      _destination = _DesktopDestination.gameDetail;
    });
  }

  Future<void> _openActivityCenter() async {
    final AppController controller = widget.controller;
    await controller.markActivitiesRead();
    if (!mounted) return;
    final AppCopy copy = controller.copy;
    final RenderBox? button =
        _activityButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null || !button.hasSize) return;

    final Offset anchor = button.localToGlobal(Offset.zero, ancestor: overlay);
    final Size overlaySize = overlay.size;
    final double panelWidth = math.min(390, overlaySize.width - 24);
    final double panelMaxHeight = math.min(580, overlaySize.height - 24);
    final double left = (anchor.dx + button.size.width - panelWidth)
        .clamp(12.0, math.max(12.0, overlaySize.width - panelWidth - 12.0))
        .toDouble();
    final double top = (anchor.dy + button.size.height + 8)
        .clamp(12.0, math.max(12.0, overlaySize.height - panelMaxHeight - 12.0))
        .toDouble();

    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      barrierLabel: copy.activityTitle,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final CurvedAnimation curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.025),
                  end: Offset.zero,
                ).animate(curve),
                child: child,
              ),
            );
          },
      pageBuilder:
          (
            BuildContext dialogContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            return Stack(
              children: <Widget>[
                Positioned(
                  left: left,
                  top: top,
                  width: panelWidth,
                  child: SafeArea(
                    child: _DesktopActivityPopup(
                      controller: controller,
                      maxHeight: panelMaxHeight,
                      onClose: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ),
              ],
            );
          },
    );
  }

  String _destinationTitle(AppCopy copy) {
    switch (_destination) {
      case _DesktopDestination.home:
        return '首页';
      case _DesktopDestination.games:
        return '我的游戏';
      case _DesktopDestination.gameDetail:
        return '桌游详情';
      case _DesktopDestination.assistant:
        return widget.controller.selectedConversation?.title ??
            copy.globalAiTitle;
      case _DesktopDestination.library:
        return '资料库';
      case _DesktopDestination.settings:
        return '设置';
    }
  }

  void _handleControllerChange() {
    if (!mounted) return;
    setState(() {});
    final RemoteLibraryUpdate? next = widget.controller.pendingLibraryUpdate;
    if (next == null || identical(next, _lastSeenUpdate)) return;
    _lastSeenUpdate = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowLibraryUpdateDialog();
    });
  }

  Future<void> _maybeShowLibraryUpdateDialog() async {
    if (!mounted || _showingUpdateDialog) return;
    if (!widget.controller.shouldShowLibraryUpdatePrompt()) return;
    _showingUpdateDialog = true;
    final AppCopy copy = widget.controller.copy;
    final RemoteLibraryUpdate? update = widget.controller.pendingLibraryUpdate;
    final bool? shouldUpdate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(copy.libraryUpdateTitle),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.55,
              maxWidth: 520,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(copy.libraryUpdateMessage),
                  if (update != null && update.changedCount > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      copy.libraryUpdateChangeSummary(update.changedCount),
                      style: Theme.of(dialogContext).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: update.changedResourceCounts.entries
                          .map(
                            (entry) => Chip(
                              label: Text(
                                '${copy.libraryUpdateResourceLabel(entry.key)} ${entry.value}',
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  if (update != null &&
                      update.changedGameTitles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      copy.libraryUpdateGameListLabel(
                        update.changedGameTitles.length,
                      ),
                      style: Theme.of(dialogContext).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    ...update.changedGameTitles.map(
                      (String title) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $title'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(copy.updateLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(copy.updateNow),
            ),
          ],
        );
      },
    );
    _showingUpdateDialog = false;
    if (!mounted) return;
    if (shouldUpdate == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(copy.updatingNow)));
      await widget.controller.applyPendingLibraryUpdate();
    } else if (shouldUpdate == false) {
      widget.controller.dismissPendingLibraryUpdatePrompt();
    }
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.destination,
    required this.compact,
    required this.onSelected,
    required this.onOpenAbout,
    required this.controller,
  });

  final _DesktopDestination destination;
  final bool compact;
  final ValueChanged<_DesktopDestination> onSelected;
  final VoidCallback onOpenAbout;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final double width = compact ? 76 : 214;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        20,
        compact ? 10 : 14,
        14,
      ),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.72),
        border: Border(right: BorderSide(color: palette.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DesktopBrand(compact: compact),
          const SizedBox(height: 30),
          if (!compact) ...[
            _DesktopNavLabel(label: '工作区'),
            const SizedBox(height: 8),
          ],
          ...<Widget>[
            _DesktopNavItem(
              compact: compact,
              icon: Icons.home_outlined,
              label: '首页',
              selected: destination == _DesktopDestination.home,
              onTap: () => onSelected(_DesktopDestination.home),
            ),
            _DesktopNavItem(
              compact: compact,
              icon: Icons.layers_outlined,
              label: '我的游戏',
              selected: destination == _DesktopDestination.games,
              onTap: () => onSelected(_DesktopDestination.games),
            ),
            _DesktopNavItem(
              compact: compact,
              icon: Icons.chat_bubble_outline_rounded,
              label: 'AI 助手',
              selected: destination == _DesktopDestination.assistant,
              onTap: () => onSelected(_DesktopDestination.assistant),
            ),
            _DesktopNavItem(
              compact: compact,
              icon: Icons.menu_book_outlined,
              label: '资料库',
              selected: destination == _DesktopDestination.library,
              onTap: () => onSelected(_DesktopDestination.library),
            ),
          ],
          const SizedBox(height: 18),
          if (!compact) _DesktopNavLabel(label: '系统'),
          if (!compact) const SizedBox(height: 8),
          _DesktopNavItem(
            compact: compact,
            icon: Icons.tune_rounded,
            label: '设置',
            selected: destination == _DesktopDestination.settings,
            onTap: () => onSelected(_DesktopDestination.settings),
          ),
          const Spacer(),
          if (compact)
            IconButton(
              tooltip: '关于',
              onPressed: onOpenAbout,
              icon: const Icon(Icons.info_outline_rounded),
            )
          else
            _DesktopWorkspaceIdentity(onTap: onOpenAbout),
        ],
      ),
    );
  }
}

class _DesktopBrand extends StatelessWidget {
  const _DesktopBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Row(
      mainAxisAlignment: compact
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.asset(
            'branding/app_icon.png',
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) =>
                    Container(
                      width: 36,
                      height: 36,
                      color: palette.primary,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.casino_rounded,
                        color: palette.onPrimary,
                      ),
                    ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '桌游导师',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ],
    );
  }
}

class _DesktopNavLabel extends StatelessWidget {
  const _DesktopNavLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppPalette.of(context).textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.compact,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color foreground = selected ? palette.primary : palette.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Tooltip(
        message: compact ? label : '',
        child: Material(
          color: selected
              ? palette.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 0 : 11,
                vertical: 11,
              ),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, color: foreground, size: 21),
                  if (!compact) ...[
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? palette.textPrimary
                              : palette.textSecondary,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
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
}

class _DesktopWorkspaceIdentity extends StatelessWidget {
  const _DesktopWorkspaceIdentity({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Semantics(
      button: true,
      label: '本地工作区，桌面端 2.0 预览',
      child: Material(
        color: palette.surfaceContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.28),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.desktop_windows_rounded,
                    size: 19,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '本地工作区',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        '桌面端 · 2.0',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.title,
    required this.compact,
    required this.activityButtonKey,
    required this.onNew,
    required this.onOpenActivities,
    required this.unreadActivityCount,
    this.primaryAction,
    this.primaryLabel,
  });

  final String title;
  final bool compact;
  final GlobalKey activityButtonKey;
  final VoidCallback onNew;
  final VoidCallback onOpenActivities;
  final int unreadActivityCount;
  final VoidCallback? primaryAction;
  final String? primaryLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      height: 68,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 26),
      decoration: BoxDecoration(
        color: palette.pageBackground.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: palette.outline)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              IconButton(
                key: activityButtonKey,
                tooltip: '消息',
                onPressed: onOpenActivities,
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              if (unreadActivityCount > 0)
                Positioned(
                  top: 7,
                  right: 7,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: palette.error,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: palette.pageBackground,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadActivityCount > 99
                            ? '99+'
                            : '$unreadActivityCount',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: palette.onPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: '搜索',
            onPressed: () {},
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 6),
          if (primaryAction != null)
            FilledButton.icon(
              onPressed: primaryAction,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(primaryLabel ?? '询问 AI'),
            )
          else
            FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add_rounded),
              label: Text(compact ? '新建' : '新建'),
            ),
        ],
      ),
    );
  }
}

class _DesktopHomePane extends StatelessWidget {
  const _DesktopHomePane({
    required this.controller,
    required this.compact,
    required this.onOpenGames,
    required this.onOpenAssistant,
    required this.onOpenLibrary,
    required this.onOpenGame,
    required this.onOpenActivities,
  });

  final AppController controller;
  final bool compact;
  final VoidCallback onOpenGames;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenLibrary;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onOpenActivities;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasGames) {
      return _DesktopNoGamesPane(controller: controller);
    }
    final AppPalette palette = AppPalette.of(context);
    final GameInfo game = controller.featuredGame;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 28,
        26,
        compact ? 16 : 28,
        28,
      ),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Text(
                '继续游玩',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: onOpenGames,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('开始'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _DesktopFeaturedGameCard(game: game, onTap: () => onOpenGame(game)),
        const SizedBox(height: 16),
        _DesktopSurface(
          title: '快捷操作',
          action: IconButton(
            tooltip: '打开 AI 助手',
            onPressed: onOpenAssistant,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _DesktopQuickAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: '询问 AI',
                onTap: onOpenAssistant,
              ),
              _DesktopQuickAction(
                icon: Icons.layers_outlined,
                label: '我的游戏',
                onTap: onOpenGames,
              ),
              _DesktopQuickAction(
                icon: Icons.menu_book_outlined,
                label: '资料库',
                onTap: onOpenLibrary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool stack = constraints.maxWidth < 700;
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DesktopRecentGamesCard(
                    controller: controller,
                    onOpenGame: onOpenGame,
                  ),
                  const SizedBox(height: 16),
                  _DesktopActivityCard(
                    controller: controller,
                    onOpenActivities: onOpenActivities,
                  ),
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    flex: 11,
                    child: _DesktopRecentGamesCard(
                      controller: controller,
                      onOpenGame: onOpenGame,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 9,
                    child: _DesktopActivityCard(
                      controller: controller,
                      onOpenActivities: onOpenActivities,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DesktopFeaturedGameCard extends StatelessWidget {
  const _DesktopFeaturedGameCard({required this.game, required this.onTap});

  final GameInfo game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          height: 250,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.primary.withValues(alpha: 0.45)),
            gradient: LinearGradient(
              colors: <Color>[palette.surfaceContainer, palette.surface],
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -25,
                bottom: -80,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.12),
                      width: 24,
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '上次对局',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: palette.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    game.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: palette.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${game.playerCount} · ${game.playTime}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  FilledButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('继续'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSurface extends StatelessWidget {
  const _DesktopSurface({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DesktopQuickAction extends StatelessWidget {
  const _DesktopQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return SizedBox(
      width: 180,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.outline),
          backgroundColor: palette.surfaceContainer.withValues(alpha: 0.56),
        ),
      ),
    );
  }
}

class _DesktopRecentGamesCard extends StatelessWidget {
  const _DesktopRecentGamesCard({
    required this.controller,
    required this.onOpenGame,
  });

  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;

  @override
  Widget build(BuildContext context) {
    return _DesktopSurface(
      title: '最近游戏',
      action: IconButton(
        tooltip: '查看全部',
        onPressed: () {},
        icon: const Icon(Icons.arrow_outward_rounded),
      ),
      child: Column(
        children: controller.games.take(3).map((GameInfo game) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _DesktopGameRow(
              controller: controller,
              game: game,
              onTap: () => onOpenGame(game),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DesktopGameRow extends StatelessWidget {
  const _DesktopGameRow({
    required this.controller,
    required this.game,
    required this.onTap,
  });

  final AppController controller;
  final GameInfo game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Material(
      color: palette.surfaceContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              _DesktopGameMark(controller: controller, game: game),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      game.title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      game.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopActivityCard extends StatelessWidget {
  const _DesktopActivityCard({
    required this.controller,
    required this.onOpenActivities,
  });

  final AppController controller;
  final VoidCallback onOpenActivities;

  @override
  Widget build(BuildContext context) {
    final List<AppActivity> activities = controller.activities.take(3).toList();
    final AppCopy copy = controller.copy;
    return _DesktopSurface(
      title: copy.activityTitle,
      action: TextButton.icon(
        onPressed: onOpenActivities,
        icon: const Icon(Icons.arrow_outward_rounded, size: 17),
        label: Text(copy.activityViewAll),
      ),
      child: activities.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.notifications_none_rounded,
                    color: AppPalette.of(context).textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(copy.activityEmpty)),
                ],
              ),
            )
          : Column(
              children: <Widget>[
                for (int index = 0; index < activities.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == activities.length - 1 ? 0 : 8,
                    ),
                    child: _DesktopActivityTile(
                      controller: controller,
                      activity: activities[index],
                      compact: true,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DesktopActivityPopup extends StatefulWidget {
  const _DesktopActivityPopup({
    required this.controller,
    required this.maxHeight,
    required this.onClose,
  });

  final AppController controller;
  final double maxHeight;
  final VoidCallback onClose;

  @override
  State<_DesktopActivityPopup> createState() => _DesktopActivityPopupState();
}

class _DesktopActivityPopupState extends State<_DesktopActivityPopup> {
  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    final double listMaxHeight = math.max(96, widget.maxHeight - 82);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final List<AppActivity> activities = widget.controller.activities;
        return Material(
          color: Colors.transparent,
          elevation: 18,
          shadowColor: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.outline),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.notifications_none_rounded,
                          color: palette.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          copy.activityTitle,
                          style: Theme.of(context).textTheme.titleLarge
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
                              color: palette.primary.withValues(alpha: 0.14),
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
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Divider(height: 16, color: palette.outline),
                    if (activities.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: listMaxHeight),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: activities.length,
                          separatorBuilder: (BuildContext context, int index) =>
                              Divider(height: 1, color: palette.outline),
                          itemBuilder: (BuildContext context, int index) =>
                              _DesktopActivityTile(
                                activity: activities[index],
                                compact: false,
                                controller: widget.controller,
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
  }
}

class _DesktopActivityTile extends StatelessWidget {
  const _DesktopActivityTile({
    required this.controller,
    required this.activity,
    required this.compact,
  });

  final AppController controller;
  final AppActivity activity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    final Color accent = _activityColor(palette, activity.kind);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 4,
        vertical: compact ? 10 : 8,
      ),
      decoration: compact
          ? BoxDecoration(
              color: palette.surfaceContainer.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(11),
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
  }
}

IconData _activityIcon(AppActivityKind kind) {
  return switch (kind) {
    AppActivityKind.serviceRefresh => Icons.sync_rounded,
    AppActivityKind.aiCompleted => Icons.check_circle_outline_rounded,
    AppActivityKind.aiFailed => Icons.error_outline_rounded,
    AppActivityKind.libraryUpdate => Icons.system_update_alt_rounded,
    AppActivityKind.info => Icons.info_outline_rounded,
  };
}

Color _activityColor(AppPalette palette, AppActivityKind kind) {
  return switch (kind) {
    AppActivityKind.serviceRefresh => palette.primary,
    AppActivityKind.aiCompleted => palette.success,
    AppActivityKind.aiFailed => palette.error,
    AppActivityKind.libraryUpdate => palette.warning,
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

class _DesktopGameMark extends StatelessWidget {
  const _DesktopGameMark({required this.controller, required this.game});

  final AppController controller;
  final GameInfo game;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 36,
        height: 36,
        child: DesktopResolvedImage(
          controller: controller,
          assetPath: game.coverAssetPath,
          palette: palette,
          placeholderBuilder: (BuildContext context) => Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(game.cardAccent).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _shortGameMark(game.title),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: palette.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNoGamesPane extends StatefulWidget {
  const _DesktopNoGamesPane({
    required this.controller,
    this.title = '还没有可用的游戏',
    this.message = '游戏资料还没有加载完成。你可以重试加载，或先到设置检查资料来源。',
  });

  final AppController controller;
  final String title;
  final String message;

  @override
  State<_DesktopNoGamesPane> createState() => _DesktopNoGamesPaneState();
}

class _DesktopNoGamesPaneState extends State<_DesktopNoGamesPane> {
  bool _loading = false;
  String? _error;

  Future<void> _reload() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.controller.reloadGames();
      if (mounted && !widget.controller.hasGames) {
        setState(() => _error = '没有找到可用的游戏资料，请检查本地资源或资料来源配置。');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '加载失败：$error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
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
                  widget.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  widget.message,
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
                      label: Text(_loading ? '加载中…' : '重新加载'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('请打开左侧“设置”，检查资料来源配置。')),
                        ),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('检查设置'),
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

class _DesktopGamesPane extends StatelessWidget {
  const _DesktopGamesPane({required this.controller, required this.onOpenGame});

  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasGames) {
      return _DesktopNoGamesPane(controller: controller);
    }
    final AppPalette palette = AppPalette.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 310,
        mainAxisExtent: 235,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: controller.games.length,
      itemBuilder: (BuildContext context, int index) {
        final GameInfo game = controller.games[index];
        return Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onOpenGame(game),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: DesktopResolvedImage(
                        controller: controller,
                        assetPath: game.coverAssetPath,
                        palette: palette,
                        placeholderBuilder: (BuildContext context) =>
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    Color(game.cardAccent),
                                    palette.surfaceContainer,
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _shortGameMark(game.title),
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        color: palette.onPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    game.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${game.playerCount} · ${game.complexity}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopAssistantPane extends StatefulWidget {
  const _DesktopAssistantPane({required this.controller});

  final AppController controller;

  @override
  State<_DesktopAssistantPane> createState() => _DesktopAssistantPaneState();
}

class _DesktopAssistantPaneState extends State<_DesktopAssistantPane> {
  late final TextEditingController _draftController;
  late final ScrollController _scrollController;
  bool _showMessageTimes = false;
  Timer? _messageTimesTimer;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController();
    _scrollController = ScrollController();
    controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
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
        title: 'AI 助手暂不可用',
        message: '请先加载至少一个游戏资料，AI 助手才能建立对应的规则上下文。',
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
    final GameInfo game = controller.featuredGame;
    final String assistantTitle = useGlobalMode
        ? controller.copy.globalAiTitle
        : '${game.title}助手';
    final String assistantSubtitle = useGlobalMode ? '跨桌游知识问答' : '官方资料已加载';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.pageBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.outline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 205,
              child: _DesktopAssistantSessions(controller: controller),
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                    child: Row(
                      children: <Widget>[
                        const _AssistantAppMark(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                assistantTitle,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                assistantSubtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '清空对话',
                          onPressed: () =>
                              controller.clearConversationForContext(
                                useGlobalMode: useGlobalMode,
                              ),
                          icon: const Icon(Icons.delete_sweep_outlined),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: palette.outline),
                  Expanded(
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      children: <Widget>[
                        for (final ChatMessage message in messages)
                          MessageBubble(
                            message: message,
                            palette: palette,
                            copy: controller.copy,
                            onSpeak: message.role == ChatRole.assistant
                                ? () => controller.speakMessage(message.text)
                                : () {},
                            speakTooltip: controller.copy.speakAgain,
                            onRetry: message.canRetry
                                ? () => controller.retryMessage(
                                    message,
                                    useGlobalMode: useGlobalMode,
                                  )
                                : null,
                            retryTooltip: controller.copy.retry,
                            showTimestamp: _showMessageTimes,
                            onTap: _toggleMessageTimes,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: _DesktopComposer(
                      controller: controller,
                      draftController: _draftController,
                      onSend: _send,
                      onMic: _toggleListening,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 220,
              child: _DesktopContextPanel(
                controller: controller,
                useGlobalMode: useGlobalMode,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
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
    if (text.isEmpty || controller.isSending) return;
    if (!controller.hasSelectedAiModel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.copy.aiApiModelRequired)),
      );
      return;
    }
    _draftController.clear();
    await controller.sendPrompt(
      text,
      useGlobalMode: controller.selectedConversationIsGlobal,
    );
  }

  Future<void> _toggleListening() async {
    if (!controller.speechAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.copy.micUnavailable)));
      return;
    }
    if (controller.isListening) {
      await controller.stopListening();
      return;
    }
    await controller.startListening(
      onRecognizedText: (String value) {
        _draftController.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      },
    );
  }
}

class _DesktopAssistantEmptyPane extends StatelessWidget {
  const _DesktopAssistantEmptyPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.pageBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.outline),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.forum_outlined, size: 42, color: palette.primary),
                const SizedBox(height: 14),
                Text('还没有会话', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '进入某款桌游的详情页并点击“询问 AI”，或打开通用助手开始聊天。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => controller.openGlobalAssistant(),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('打开通用助手'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopAssistantSessions extends StatelessWidget {
  const _DesktopAssistantSessions({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final List<AiConversation> conversations = controller.conversations;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.6),
        border: Border(right: BorderSide(color: palette.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('会话', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (final AiConversation conversation in conversations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _DesktopSessionRow(
                      icon: conversation.id == controller.selectedConversationId
                          ? Icons.chat_rounded
                          : Icons.chat_bubble_outline_rounded,
                      title: conversation.title,
                      subtitle: conversation.isGlobal
                          ? '跨桌游问答 · ${conversation.messageCount} 条消息'
                          : '规则问答 · ${conversation.messageCount} 条消息',
                      selected:
                          conversation.id == controller.selectedConversationId,
                      onTap: () =>
                          controller.selectConversation(conversation.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
      color: selected
          ? palette.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
          Text('上下文', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 13),
          _DesktopContextLine(
            icon: Icons.casino_outlined,
            label: useGlobalMode ? '全部资料' : controller.featuredGame.title,
          ),
          _DesktopContextLine(icon: Icons.menu_book_outlined, label: '规则书'),
          _DesktopContextLine(icon: Icons.fact_check_outlined, label: 'FAQ'),
          const SizedBox(height: 18),
          Text('回答模式', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _DesktopContextToggle(
            label: '官方资料优先',
            selected: !smartSupplement,
            onTap: () => controller.setAllowSmartSupplement(
              false,
              useGlobalMode: useGlobalMode,
            ),
          ),
          _DesktopContextToggle(
            label: '允许智能补充',
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
        color: selected
            ? palette.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
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
    );
  }
}

class _DesktopComposer extends StatelessWidget {
  const _DesktopComposer({
    required this.controller,
    required this.draftController,
    required this.onSend,
    required this.onMic,
  });

  final AppController controller;
  final TextEditingController draftController;
  final Future<void> Function() onSend;
  final Future<void> Function() onMic;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return AnimatedBuilder(
      animation: draftController,
      builder: (BuildContext context, Widget? child) {
        final bool canSend =
            draftController.text.trim().isNotEmpty && !controller.isSending;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.inputSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 4, 7, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                IconButton(
                  tooltip: '语音输入',
                  onPressed: controller.isSending ? null : onMic,
                  icon: Icon(
                    controller.isListening
                        ? Icons.stop_rounded
                        : Icons.mic_none_rounded,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: draftController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: canSend ? (_) => onSend() : null,
                    decoration: const InputDecoration(
                      hintText: '输入问题…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: controller.isSending ? '停止生成' : '发送',
                  onPressed: controller.isSending
                      ? controller.stopGenerating
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
                  ),
                  icon: Icon(
                    controller.isSending
                        ? Icons.stop_rounded
                        : Icons.arrow_upward_rounded,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DesktopLibraryPane extends StatefulWidget {
  const _DesktopLibraryPane({required this.controller});

  final AppController controller;

  @override
  State<_DesktopLibraryPane> createState() => _DesktopLibraryPaneState();
}

class _DesktopLibraryPaneState extends State<_DesktopLibraryPane> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.hasGames) {
      return _DesktopNoGamesPane(
        controller: widget.controller,
        title: '资料库暂为空',
        message: '游戏资料加载完成后，规则书、FAQ 和笔记会显示在这里。',
      );
    }
    final AppPalette palette = AppPalette.of(context);
    final GameInfo game = widget.controller.featuredGame;
    final List<_LibraryItem> items = <_LibraryItem>[
      _LibraryItem(
        icon: Icons.menu_book_outlined,
        title: '${game.title} · 官方规则书',
        meta: '${game.rulebookAssetPath} · 已索引',
        type: 0,
      ),
      _LibraryItem(
        icon: Icons.fact_check_outlined,
        title: '${game.title} · 官方 FAQ',
        meta: '${game.faqAssetPath} · 已索引',
        type: 1,
      ),
      const _LibraryItem(
        icon: Icons.sticky_note_2_outlined,
        title: '我的笔记',
        meta: '当前工作区 · 个人',
        type: 2,
      ),
    ];
    final List<_LibraryItem> visible = _filter == 0
        ? items
        : items.where((_LibraryItem item) => item.type == _filter - 1).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '规则资料',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _showImportComingSoon,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导入'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.outline),
          ),
          child: Wrap(
            spacing: 4,
            children: <Widget>[
              _LibraryFilterChip(
                label: '全部',
                selected: _filter == 0,
                onTap: () => setState(() => _filter = 0),
              ),
              _LibraryFilterChip(
                label: '规则书',
                selected: _filter == 1,
                onTap: () => setState(() => _filter = 1),
              ),
              _LibraryFilterChip(
                label: 'FAQ',
                selected: _filter == 2,
                onTap: () => setState(() => _filter = 2),
              ),
              _LibraryFilterChip(
                label: '笔记',
                selected: _filter == 3,
                onTap: () => setState(() => _filter = 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...visible.map(
          (_LibraryItem item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LibraryItemTile(item: item),
          ),
        ),
      ],
    );
  }

  void _showImportComingSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('该功能正在开发中')));
  }
}

class _LibraryItem {
  const _LibraryItem({
    required this.icon,
    required this.title,
    required this.meta,
    required this.type,
  });

  final IconData icon;
  final String title;
  final String meta;
  final int type;
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
      ),
      child: Text(label),
    );
  }
}

class _LibraryItemTile extends StatelessWidget {
  const _LibraryItemTile({required this.item});

  final _LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
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
            child: Icon(item.icon, color: palette.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(item.meta, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: '更多',
            onPressed: () {},
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
    );
  }
}

class _DesktopSettingsPane extends StatelessWidget {
  const _DesktopSettingsPane({
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
        borderRadius: BorderRadius.circular(17),
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

String _shortGameMark(String title) {
  if (title.length <= 2) return title;
  return title.substring(0, 2);
}

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
