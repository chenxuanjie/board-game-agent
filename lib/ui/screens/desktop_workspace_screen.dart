import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../models/app_activity.dart';
import '../../models/app_language.dart';
import '../../models/ai_conversation.dart';
import '../../models/ai_run.dart';
import '../../models/chat_message.dart';
import '../../models/color_scheme_option.dart';
import '../../models/desktop_library_resource.dart';
import '../../models/game_info.dart';
import '../../models/remote_library_update.dart';
import '../../models/resolved_document.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';
import '../widgets/ai_run_activity.dart';
import '../widgets/language_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/desktop_resolved_image.dart';
import 'desktop_game_detail_pane.dart';
import 'markdown_document_screen.dart';
import 'pdf_document_screen.dart';
import 'library_resource_document_screen.dart';

enum _DesktopDestination {
  home,
  games,
  gameDetail,
  assistant,
  library,
  settings,
}

double _desktopActivityPanelWidth(double overlayWidth) {
  final double availableWidth = math.max(0, overlayWidth - 24);
  if (availableWidth == 0) return 0;

  // Keep the panel compact on narrow windows while capping it on large
  // monitors. The available-width clamp prevents overflow in very small
  // windows where even the preferred minimum cannot fit.
  final double preferredWidth = overlayWidth * 0.36;
  // Leave a small allowance for SafeArea/overlay padding so the rendered
  // panel remains within the viewport on very small desktop windows.
  final double clampedPreferred = math.max(
    240,
    math.min(332, preferredWidth - 8),
  );
  return math.min(availableWidth, clampedPreferred);
}

double _desktopActivityPanelMaxHeight(double overlayHeight) {
  // The follower is anchored below the top bar, so leave enough room for the
  // header and safe-area insets instead of allowing the popup to run offscreen.
  final double availableHeight = math.max(0, overlayHeight - 100);
  if (availableHeight == 0) return 0;
  return math.min(520, availableHeight);
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
  final GlobalKey<_DesktopAssistantPaneState> _assistantPaneKey =
      GlobalKey<_DesktopAssistantPaneState>();
  final GlobalKey _activityButtonKey = GlobalKey();
  final LayerLink _activityLayerLink = LayerLink();
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
                        copy: copy,
                        activityButtonKey: _activityButtonKey,
                        activityLayerLink: _activityLayerLink,
                        onNew: () =>
                            _selectDestination(_DesktopDestination.games),
                        onSearch: _openSearch,
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
          onOpenAssistant: _openAssistant,
          onOpenLibrary: () => _selectDestination(_DesktopDestination.library),
          onOpenGame: _openGame,
          onOpenActivities: _openActivityCenter,
          onActivityTap: _handleActivityTap,
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
        return _DesktopAssistantPane(
          key: _assistantPaneKey,
          controller: controller,
        );
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

  Future<void> _openSearch() async {
    final GameInfo? result = await showDialog<GameInfo>(
      context: context,
      builder: (BuildContext dialogContext) => _DesktopSearchDialog(
        games: widget.controller.games,
        copy: widget.controller.copy,
      ),
    );
    if (!mounted || result == null) return;
    _openGame(result);
  }

  Future<void> _openActivityCenter() async {
    final AppController controller = widget.controller;
    if (!mounted) return;
    final AppCopy copy = controller.copy;
    final Size overlaySize = MediaQuery.sizeOf(context);
    final double panelWidth = _desktopActivityPanelWidth(overlaySize.width);
    final double panelMaxHeight = _desktopActivityPanelMaxHeight(
      overlaySize.height,
    );
    if (panelWidth <= 0 || panelMaxHeight <= 0) return;
    bool markedRead = false;

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
            if (!markedRead) {
              markedRead = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  unawaited(controller.markActivitiesRead());
                }
              });
            }
            return Stack(
              children: <Widget>[
                CompositedTransformFollower(
                  link: _activityLayerLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomRight,
                  followerAnchor: Alignment.topRight,
                  offset: const Offset(0, 8),
                  child: SizedBox(
                    width: panelWidth,
                    child: _DesktopActivityPopup(
                      controller: controller,
                      maxHeight: panelMaxHeight,
                      onClose: () => Navigator.of(dialogContext).pop(),
                      onActivityTap: (AppActivity activity) {
                        _handleActivityTap(
                          activity,
                          closePanel: () => Navigator.of(dialogContext).pop(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
    );
  }

  void _handleActivityTap(AppActivity activity, {VoidCallback? closePanel}) {
    closePanel?.call();
    unawaited(widget.controller.markActivityRead(activity.id));

    activity = widget.controller.resolveActivityTarget(activity);

    final String? conversationId = activity.conversationId;
    if (conversationId == null || conversationId.isEmpty) {
      if (activity.kind == AppActivityKind.aiCompleted ||
          activity.kind == AppActivityKind.aiFailed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.controller.copy.activityConversationUnavailable,
              ),
            ),
          );
        }
      }
      return;
    }
    final bool exists = widget.controller.conversations.any(
      (AiConversation conversation) => conversation.id == conversationId,
    );
    if (!exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.controller.copy.activityConversationUnavailable,
            ),
          ),
        );
      }
      return;
    }
    widget.controller.selectConversation(conversationId);
    if (!mounted) return;
    setState(() => _destination = _DesktopDestination.assistant);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _assistantPaneKey.currentState?.revealMessage(activity.messageId);
    });
  }

  String _destinationTitle(AppCopy copy) {
    switch (_destination) {
      case _DesktopDestination.home:
        return copy.desktopHome;
      case _DesktopDestination.games:
        return copy.desktopGames;
      case _DesktopDestination.gameDetail:
        return copy.desktopGameDetail;
      case _DesktopDestination.assistant:
        return widget.controller.selectedConversation?.title ??
            copy.globalAiTitle;
      case _DesktopDestination.library:
        return copy.desktopLibrary;
      case _DesktopDestination.settings:
        return copy.desktopSettings;
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
    final AppCopy copy = controller.copy;
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
            _DesktopNavLabel(label: copy.desktopWorkspace),
            const SizedBox(height: 8),
          ],
          ...<Widget>[
            _DesktopNavItem(
              compact: compact,
              icon: Icons.home_outlined,
              label: copy.desktopHome,
              selected: destination == _DesktopDestination.home,
              onTap: () => onSelected(_DesktopDestination.home),
            ),
            _DesktopNavItem(
              compact: compact,
              icon: Icons.layers_outlined,
              label: copy.desktopGames,
              selected: destination == _DesktopDestination.games,
              onTap: () => onSelected(_DesktopDestination.games),
            ),
            _DesktopNavItem(
              compact: compact,
              icon: Icons.chat_bubble_outline_rounded,
              label: copy.globalAiTitle,
              selected: destination == _DesktopDestination.assistant,
              onTap: () => onSelected(_DesktopDestination.assistant),
            ),
            _DesktopNavItem(
              compact: compact,
              icon: Icons.menu_book_outlined,
              label: copy.desktopLibrary,
              selected: destination == _DesktopDestination.library,
              onTap: () => onSelected(_DesktopDestination.library),
            ),
          ],
          const SizedBox(height: 18),
          if (!compact) _DesktopNavLabel(label: copy.desktopSystem),
          if (!compact) const SizedBox(height: 8),
          _DesktopNavItem(
            compact: compact,
            icon: Icons.tune_rounded,
            label: copy.desktopSettings,
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
    required this.copy,
    required this.activityButtonKey,
    required this.activityLayerLink,
    required this.onNew,
    required this.onSearch,
    required this.onOpenActivities,
    required this.unreadActivityCount,
    this.primaryAction,
    this.primaryLabel,
  });

  final String title;
  final bool compact;
  final AppCopy copy;
  final GlobalKey activityButtonKey;
  final LayerLink activityLayerLink;
  final VoidCallback onNew;
  final VoidCallback onSearch;
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
          CompositedTransformTarget(
            link: activityLayerLink,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                IconButton(
                  key: activityButtonKey,
                  tooltip: copy.activityTitle,
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
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
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
          ),
          if (compact)
            IconButton(
              tooltip: copy.desktopSearchAction,
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
            )
          else
            Tooltip(
              message: copy.desktopSearchAction,
              excludeFromSemantics: true,
              child: OutlinedButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search_rounded),
                label: Text(copy.desktopSearchAction),
              ),
            ),
          const SizedBox(width: 6),
          if (primaryAction != null)
            compact
                ? IconButton.filled(
                    tooltip: primaryLabel ?? copy.askAiAssistant,
                    onPressed: primaryAction,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                  )
                : FilledButton.icon(
                    onPressed: primaryAction,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: Text(primaryLabel ?? copy.askAiAssistant),
                  )
          else
            compact
                ? IconButton.filled(
                    tooltip: copy.desktopCreate,
                    onPressed: onNew,
                    icon: const Icon(Icons.add_rounded),
                  )
                : FilledButton.icon(
                    onPressed: onNew,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(copy.desktopCreate),
                  ),
        ],
      ),
    );
  }
}

class _DesktopSearchDialog extends StatefulWidget {
  const _DesktopSearchDialog({required this.games, required this.copy});

  final List<GameInfo> games;
  final AppCopy copy;

  @override
  State<_DesktopSearchDialog> createState() => _DesktopSearchDialogState();
}

class _DesktopSearchDialogState extends State<_DesktopSearchDialog> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController()
      ..addListener(_handleQueryChanged);
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final List<String> queryTokens = _searchTokens(_queryController.text);
    final List<GameInfo> results = widget.games
        .where((GameInfo game) {
          if (queryTokens.isEmpty) return true;
          final String searchable = <String?>[
            game.title,
            game.subtitle,
            game.slug,
            game.editionLabel,
            ...game.aliases,
            ...game.designers,
            ...game.publishers,
            ...game.keywords,
            game.categoryLine,
            game.learningDifficulty,
            game.perPlayerTime,
            game.setupTime,
            game.languageRequirement,
            ...game.rankBadges,
            game.heroTagline,
            game.assistantIntro,
            game.summary,
            game.mentorPitch,
            game.playTime,
            game.playerCount,
            game.complexity,
            ...game.roundFlow,
            ...game.assistantSkills,
            ...game.quickPrompts,
          ].whereType<String>().join(' ').toLowerCase();
          return queryTokens.every(searchable.contains);
        })
        .toList(growable: false);
    final double maxHeight = math.min(
      680,
      math.max(180, MediaQuery.sizeOf(context).height - 48),
    );

    return Dialog(
      key: const ValueKey<String>('desktop-search-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.copy.desktopSearchTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.copy.dialogClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey<String>('desktop-search-field'),
                controller: _queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.copy.desktopSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _queryController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除',
                          onPressed: _queryController.clear,
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          widget.games.isEmpty
                              ? widget.copy.desktopNoGames
                              : widget.copy.desktopNoSearchResults,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: results.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: 4),
                        itemBuilder: (BuildContext context, int index) {
                          final GameInfo game = results[index];
                          return ListTile(
                            key: ValueKey<String>(
                              'desktop-search-result-${game.id}',
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: Color(game.cardAccent),
                              child: Text(
                                game.title.isEmpty
                                    ? '?'
                                    : game.title.characters.first,
                                style: TextStyle(color: palette.onPrimary),
                              ),
                            ),
                            title: Text(game.title),
                            subtitle: Text(
                              game.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).pop(game),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _searchTokens(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .map((String token) => token.trim())
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
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
    required this.onActivityTap,
  });

  final AppController controller;
  final bool compact;
  final VoidCallback onOpenGames;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenLibrary;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onOpenActivities;
  final ValueChanged<AppActivity> onActivityTap;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasGames) {
      return _DesktopNoGamesPane(controller: controller);
    }
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
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
                copy.desktopContinuePlaying,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: onOpenGames,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(copy.desktopStart),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _DesktopFeaturedGameCard(
          copy: copy,
          game: game,
          onTap: () => onOpenGame(game),
        ),
        const SizedBox(height: 16),
        _DesktopSurface(
          title: copy.desktopQuickActions,
          action: IconButton(
            tooltip: copy.desktopOpenGlobalAssistant,
            onPressed: onOpenAssistant,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _DesktopQuickAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: copy.desktopAskAi,
                onTap: onOpenAssistant,
              ),
              _DesktopQuickAction(
                icon: Icons.layers_outlined,
                label: copy.desktopGames,
                onTap: onOpenGames,
              ),
              _DesktopQuickAction(
                icon: Icons.menu_book_outlined,
                label: copy.desktopLibrary,
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
                    copy: copy,
                    onOpenGame: onOpenGame,
                    onOpenAll: onOpenGames,
                  ),
                  const SizedBox(height: 16),
                  _DesktopActivityCard(
                    controller: controller,
                    onOpenActivities: onOpenActivities,
                    onActivityTap: onActivityTap,
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
                      copy: copy,
                      onOpenGame: onOpenGame,
                      onOpenAll: onOpenGames,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 9,
                    child: _DesktopActivityCard(
                      controller: controller,
                      onOpenActivities: onOpenActivities,
                      onActivityTap: onActivityTap,
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
  const _DesktopFeaturedGameCard({
    required this.copy,
    required this.game,
    required this.onTap,
  });

  final AppCopy copy;
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
                    copy.desktopLastGame,
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
                    label: Text(copy.desktopContinue),
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
    required this.copy,
    required this.onOpenGame,
    required this.onOpenAll,
  });

  final AppController controller;
  final AppCopy copy;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return _DesktopSurface(
      title: copy.desktopRecentGames,
      action: IconButton(
        tooltip: copy.activityViewAll,
        onPressed: onOpenAll,
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
    required this.onActivityTap,
  });

  final AppController controller;
  final VoidCallback onOpenActivities;
  final ValueChanged<AppActivity> onActivityTap;

  @override
  Widget build(BuildContext context) {
    final List<AppActivity> activities = controller.activities
        .take(3)
        .map(controller.resolveActivityTarget)
        .toList(growable: false);
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
                      onTap: () => onActivityTap(activities[index]),
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
    required this.onActivityTap,
  });

  final AppController controller;
  final double maxHeight;
  final VoidCallback onClose;
  final ValueChanged<AppActivity> onActivityTap;

  @override
  State<_DesktopActivityPopup> createState() => _DesktopActivityPopupState();
}

class _DesktopActivityPopupState extends State<_DesktopActivityPopup> {
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
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                key: const ValueKey<String>('desktop-activity-popup'),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
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
  const _DesktopAssistantPane({super.key, required this.controller});

  final AppController controller;

  @override
  State<_DesktopAssistantPane> createState() => _DesktopAssistantPaneState();
}

class _DesktopAssistantPaneState extends State<_DesktopAssistantPane> {
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
    final String assistantSubtitle = useGlobalMode
        ? controller.copy.desktopCrossGameQuestions
        : controller.copy.desktopOfficialLoaded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.pageBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.outline),
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool narrow = constraints.maxWidth < 900;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!narrow)
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    assistantSubtitle,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (narrow)
                              IconButton(
                                tooltip: controller.copy.desktopSessionTitle,
                                onPressed: () => _showAssistantSheet(
                                  title: controller.copy.desktopSessionTitle,
                                  child: _DesktopAssistantSessions(
                                    controller: controller,
                                  ),
                                ),
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
                                icon: const Icon(Icons.tune_rounded),
                              ),
                            IconButton(
                              tooltip: controller.copy.desktopClearConversation,
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
                        child: Stack(
                          children: <Widget>[
                            ListView(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                14,
                                18,
                                14,
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
                                    ),
                                  if (!(messages[index].role ==
                                          ChatRole.assistant &&
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
                                      onSpeak:
                                          messages[index].role ==
                                              ChatRole.assistant
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
                                    icon: const Icon(
                                      Icons.south_rounded,
                                      size: 17,
                                    ),
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
                if (!narrow)
                  SizedBox(
                    width: 220,
                    child: _DesktopContextPanel(
                      controller: controller,
                      useGlobalMode: useGlobalMode,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
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
        _scrollToBottom();
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
    final AppCopy copy = controller.copy;
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
                Text(
                  copy.desktopNoSession,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  copy.desktopNoSessionHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
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
          Text(
            controller.copy.desktopSessionTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
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
                      subtitle: controller.copy.desktopConversationSummary(
                        conversation.isGlobal,
                        conversation.messageCount,
                      ),
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
          _DesktopContextLine(
            icon: Icons.casino_outlined,
            label: useGlobalMode
                ? controller.copy.desktopAllResources
                : selectedGame.title,
          ),
          _DesktopContextLine(
            icon: Icons.menu_book_outlined,
            label: controller.copy.desktopRulebook,
          ),
          _DesktopContextLine(
            icon: Icons.fact_check_outlined,
            label: controller.copy.desktopFaq,
          ),
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
    final AppCopy copy = controller.copy;
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
                  tooltip: copy.desktopVoiceInput,
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
                    decoration: InputDecoration(
                      hintText: copy.desktopInputHint,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: controller.isSending
                      ? copy.desktopStopGenerating
                      : copy.desktopSend,
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
  DesktopLibraryResourceType? _filter;
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
    final List<DesktopLibraryResource> visible = _filter == null
        ? items
        : items
              .where((DesktopLibraryResource item) => item.type == _filter)
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
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.outline),
              ),
              child: Wrap(
                spacing: 4,
                children: <Widget>[
                  _LibraryFilterChip(
                    label: copy.desktopAll,
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopRulebook,
                    selected: _filter == DesktopLibraryResourceType.rulebook,
                    onTap: () => setState(
                      () => _filter = DesktopLibraryResourceType.rulebook,
                    ),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopFaq,
                    selected: _filter == DesktopLibraryResourceType.faq,
                    onTap: () => setState(
                      () => _filter = DesktopLibraryResourceType.faq,
                    ),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopLibraryOther,
                    selected: _filter == DesktopLibraryResourceType.other,
                    onTap: () => setState(
                      () => _filter = DesktopLibraryResourceType.other,
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
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.playerAid:
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
    required this.onDownload,
    required this.onDelete,
  });

  final DesktopLibraryResource resource;
  final AppCopy copy;
  final bool isLoading;
  final bool isDownloading;
  final VoidCallback onOpen;
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
              else
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
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.playerAid:
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
