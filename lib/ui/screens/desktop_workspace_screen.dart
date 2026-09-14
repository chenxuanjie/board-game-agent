import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

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
import '../../models/remote_library_update.dart';
import '../../models/resolved_document.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';
import '../widgets/ai_run_activity.dart';
import '../widgets/assistant_feature_chip.dart';
import '../widgets/language_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/desktop_resolved_image.dart';
import 'desktop_game_detail_pane.dart';
import 'markdown_document_screen.dart';
import 'pdf_document_screen.dart';
import 'library_resource_document_screen.dart';

Color _v4Color(BuildContext context, Color original, Color replacement) =>
    AppPalette.of(context).scheme == ColorSchemeOption.warmwoodStudy
    ? replacement
    : original;

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
    this.embedded = false,
    this.activityLink,
    this.onDestinationChanged,
  });

  final AppController controller;
  final VoidCallback onOpenAbout;
  final bool embedded;
  final LayerLink? activityLink;
  final ValueChanged<String>? onDestinationChanged;

  @override
  State<DesktopWorkspaceScreen> createState() => DesktopWorkspaceScreenState();
}

class DesktopWorkspaceScreenState extends State<DesktopWorkspaceScreen> {
  _DesktopDestination _currentDestination = _DesktopDestination.home;
  _DesktopDestination get _destination => _currentDestination;
  set _destination(_DesktopDestination value) {
    _currentDestination = value;
    widget.onDestinationChanged?.call(value.name);
  }

  _DesktopDestination _detailReturnDestination = _DesktopDestination.games;

  /// Current business pane exposed to the V4 host and integration tests.
  String get destinationName => _destination.name;
  final GlobalKey<_DesktopAssistantPaneState> _assistantPaneKey =
      GlobalKey<_DesktopAssistantPaneState>();
  final GlobalKey _activityButtonKey = GlobalKey();
  final LayerLink _activityLayerLink = LayerLink();
  RemoteLibraryUpdate? _lastSeenUpdate;
  bool _showingUpdateDialog = false;
  bool _rulesDrawerOpen = false;
  GameInfo? _rulesDrawerGame;
  DesktopLibraryResource? _rulesDrawerResource;
  int _rulesDrawerTab = 0;
  bool _windowMaximized = false;

  // Sidebar filters are owned by the workspace so the sidebar, toolbar and
  // library view always reflect the same selection.
  String? _sidebarPlayerFilter;
  String? _sidebarWeightFilter;
  DesktopLibraryResourceType? _sidebarLibraryFilter;

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
    if (widget.embedded) {
      return LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: <Widget>[
            Positioned.fill(child: _buildPage(constraints.maxWidth < 960)),
            _RulesDrawerOverlay(
              open: _rulesDrawerOpen,
              tabIndex: _rulesDrawerTab,
              game: _rulesDrawerGame,
              resource: _rulesDrawerResource,
              controller: widget.controller,
              onClose: _closeRulesDrawer,
              onTabChanged: (value) => setState(() => _rulesDrawerTab = value),
              onOpenAssistant: _openDrawerAssistant,
              onOpenResource: _openDrawerResource,
            ),
          ],
        ),
      );
    }
    final AppCopy copy = widget.controller.copy;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = constraints.maxWidth < 680;
          final bool compact = constraints.maxWidth < 960;
          final EdgeInsets pagePadding = narrow
              ? EdgeInsets.zero
              : const EdgeInsets.all(20);
          return Padding(
            padding: pagePadding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1380),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(narrow ? 0 : 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: narrow
                          ? null
                          : Border.all(color: const Color(0x2E66C0F4)),
                      gradient: const RadialGradient(
                        center: Alignment(-0.8, -1),
                        radius: 1.4,
                        colors: <Color>[
                          Color(0xFF171F2C),
                          Color(0xFF121721),
                          Color(0xFF0D1117),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: <Widget>[
                        Column(
                          children: <Widget>[
                            _DesktopTopBar(
                              title: _destinationTitle(copy),
                              compact: compact,
                              narrow: narrow,
                              destination: _destination,
                              copy: copy,
                              activityButtonKey: _activityButtonKey,
                              activityLayerLink: _activityLayerLink,
                              onNew: () =>
                                  _selectDestination(_DesktopDestination.games),
                              onSearch: _openSearch,
                              onOpenActivities: _openActivityCenter,
                              unreadActivityCount:
                                  widget.controller.unreadActivityCount,
                              onNavigateBack: _navigateBack,
                              onNavigateForward: () =>
                                  _selectDestination(_DesktopDestination.games),
                              onSelectDestination: _selectDestination,
                              onMinimizeWindow: _minimizeWindow,
                              onToggleMaximizeWindow: _toggleMaximizeWindow,
                              onCloseWindow: _closeWindow,
                              windowMaximized: _windowMaximized,
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
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  if (!narrow)
                                    _DesktopSidebar(
                                      destination: _destination,
                                      compact: compact,
                                      onSelected: _selectDestination,
                                      onOpenAbout: widget.onOpenAbout,
                                      controller: widget.controller,
                                      playerFilter: _sidebarPlayerFilter,
                                      onPlayerFilterChanged:
                                          _handlePlayerFilter,
                                      weightFilter: _sidebarWeightFilter,
                                      onWeightFilterChanged:
                                          _handleWeightFilter,
                                      libraryFilter: _sidebarLibraryFilter,
                                      onLibraryFilterChanged:
                                          _handleLibraryFilter,
                                    ),
                                  Expanded(child: _buildPage(compact)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        _RulesDrawerOverlay(
                          open: _rulesDrawerOpen,
                          tabIndex: _rulesDrawerTab,
                          game: _rulesDrawerGame,
                          resource: _rulesDrawerResource,
                          controller: widget.controller,
                          onClose: _closeRulesDrawer,
                          onTabChanged: (int value) =>
                              setState(() => _rulesDrawerTab = value),
                          onOpenAssistant: _openDrawerAssistant,
                          onOpenResource: _openDrawerResource,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Host access for the V4 shell; uses the same business panes and run state.
  void navigateTo(String destination) {
    final target = _DesktopDestination.values
        .where((value) => value.name == destination)
        .firstOrNull;
    if (target != null) _selectDestination(target);
  }

  void showGame(GameInfo game) => _openGame(game);
  void openSearch() => _openSearch();
  void openActivities() => _openActivityCenter();
  void openRulesForGame(GameInfo game) => _openRulesDrawerForGame(game);
  void openAssistantForGame(GameInfo game) => _openAssistantForGame(game.id);
  void _navigateBack() {
    if (_destination == _DesktopDestination.gameDetail) {
      setState(() => _destination = _detailReturnDestination);
      return;
    }
    if (_destination != _DesktopDestination.home) {
      setState(() => _destination = _DesktopDestination.home);
    }
  }

  Future<void> _minimizeWindow() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    await windowManager.minimize();
  }

  Future<void> _toggleMaximizeWindow() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    final bool maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    if (mounted) setState(() => _windowMaximized = !maximized);
  }

  Future<void> _closeWindow() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    await windowManager.close();
  }

  void _openRulesDrawerForGame(GameInfo game) {
    widget.controller.selectGame(game.id);
    setState(() {
      _rulesDrawerGame = game;
      _rulesDrawerResource = null;
      _rulesDrawerTab = 0;
      _rulesDrawerOpen = true;
    });
  }

  void _openRulesDrawerForResource(DesktopLibraryResource resource) {
    final GameInfo? game = widget.controller.games
        .where((GameInfo item) => item.slug == resource.gameSlug)
        .firstOrNull;
    if (game != null) widget.controller.selectGame(game.id);
    setState(() {
      _rulesDrawerGame = game;
      _rulesDrawerResource = resource;
      _rulesDrawerTab = 0;
      _rulesDrawerOpen = true;
    });
  }

  void _closeRulesDrawer() {
    setState(() => _rulesDrawerOpen = false);
  }

  void _openDrawerAssistant() {
    final GameInfo? game = _rulesDrawerGame;
    _closeRulesDrawer();
    if (game != null) {
      _openAssistantForGame(game.id);
    } else {
      _openAssistant();
    }
  }

  Future<void> _openDrawerResource() async {
    final DesktopLibraryResource? resource = _rulesDrawerResource;
    if (resource == null || !resource.canOpen) return;
    _closeRulesDrawer();
    final ResolvedDocument? document = await widget.controller
        .resolveLibraryResource(resource);
    if (!mounted || document == null) return;
    final String title = '${resource.gameTitle} · ${resource.title}';
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
    } else if (document.renderType == DocumentRenderType.pdf) {
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
  }

  Widget _buildPage(bool compact) {
    final AppController controller = widget.controller;
    switch (_destination) {
      case _DesktopDestination.home:
        return _DesktopHomePane(
          controller: controller,
          compact: compact,
          onOpenGames: () => _selectDestination(_DesktopDestination.games),
          onContinueGame: _openAssistantForGame,
          onOpenAssistant: _openAssistant,
          onOpenLibrary: () => _selectDestination(_DesktopDestination.library),
          onOpenGame: _openGame,
          onOpenActivities: _openActivityCenter,
          onActivityTap: _handleActivityTap,
        );
      case _DesktopDestination.games:
        return _DesktopGamesPane(
          controller: controller,
          onOpenGame: _openGame,
          onOpenRules: _openRulesDrawerForGame,
          onOpenAssistant: (GameInfo game) => _openAssistantForGame(game.id),
          playerFilter: _sidebarPlayerFilter,
          weightFilter: _sidebarWeightFilter,
          onClearFilters: () => setState(() {
            _sidebarPlayerFilter = null;
            _sidebarWeightFilter = null;
          }),
        );
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
        return _DesktopLibraryPane(
          controller: controller,
          onOpenRules: _openRulesDrawerForResource,
          filter: _sidebarLibraryFilter,
          onFilterChanged: _handleLibraryFilter,
        );
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
    setState(() {
      _destination = destination;
      if (destination != _DesktopDestination.games) {
        _sidebarPlayerFilter = null;
        _sidebarWeightFilter = null;
      }
      if (destination != _DesktopDestination.library) {
        _sidebarLibraryFilter = null;
      }
    });
  }

  void _handlePlayerFilter(String? filter) {
    setState(() {
      _sidebarPlayerFilter = filter;
      _sidebarWeightFilter = null;
      _destination = _DesktopDestination.games;
    });
  }

  void _handleWeightFilter(String? filter) {
    setState(() {
      _sidebarWeightFilter = filter;
      _sidebarPlayerFilter = null;
      _destination = _DesktopDestination.games;
    });
  }

  void _handleLibraryFilter(DesktopLibraryResourceType? filter) {
    setState(() {
      _sidebarLibraryFilter = filter;
      _destination = _DesktopDestination.library;
    });
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
                  link: widget.activityLink ?? _activityLayerLink,
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

    if (activity.kind == AppActivityKind.libraryLoadFailed) {
      _selectDestination(_DesktopDestination.library);
      return;
    }

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

class _DesktopSidebar extends StatefulWidget {
  const _DesktopSidebar({
    required this.destination,
    required this.compact,
    required this.onSelected,
    required this.onOpenAbout,
    required this.controller,
    required this.playerFilter,
    required this.onPlayerFilterChanged,
    required this.weightFilter,
    required this.onWeightFilterChanged,
    required this.libraryFilter,
    required this.onLibraryFilterChanged,
  });

  final _DesktopDestination destination;
  final bool compact;
  final ValueChanged<_DesktopDestination> onSelected;
  final VoidCallback onOpenAbout;
  final AppController controller;
  final String? playerFilter;
  final ValueChanged<String?> onPlayerFilterChanged;
  final String? weightFilter;
  final ValueChanged<String?> onWeightFilterChanged;
  final DesktopLibraryResourceType? libraryFilter;
  final ValueChanged<DesktopLibraryResourceType?> onLibraryFilterChanged;

  @override
  State<_DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<_DesktopSidebar> {
  bool _isDocsCatExpanded = true;
  bool _isPlayersExpanded = true;
  bool _isWeightExpanded = true;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = widget.controller.copy;
    final Color line = const Color(0x12FFFFFF);
    final double width = widget.compact ? 200 : 240;
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141D),
        border: Border(right: BorderSide(color: line)),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                _DesktopNavLabel(label: '主要视图'),
                const SizedBox(height: 6),
                _HtmlSidebarItem(
                  icon: Icons.dashboard_outlined,
                  label: '工作台首页',
                  selected: widget.destination == _DesktopDestination.home,
                  onTap: () => widget.onSelected(_DesktopDestination.home),
                ),
                _HtmlSidebarItem(
                  icon: Icons.local_library_outlined,
                  label: '所有桌游',
                  count: '${widget.controller.games.length}',
                  selected:
                      (widget.destination == _DesktopDestination.games ||
                          widget.destination ==
                              _DesktopDestination.gameDetail) &&
                      widget.playerFilter == null &&
                      widget.weightFilter == null,
                  onTap: _openAllGames,
                ),
                _HtmlSidebarItem(
                  icon: Icons.menu_book_outlined,
                  label: '规则知识库',
                  count: '${widget.controller.libraryResources.length}',
                  selected:
                      widget.destination == _DesktopDestination.library &&
                      widget.libraryFilter == null,
                  onTap: _openAllLibrary,
                ),
                _HtmlSidebarItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: copy.globalAiTitle,
                  selected: widget.destination == _DesktopDestination.assistant,
                  onTap: () => widget.onSelected(_DesktopDestination.assistant),
                ),
                if (widget.destination ==
                    _DesktopDestination.games) ...<Widget>[
                  const SizedBox(height: 14),
                  _DesktopNavLabel(
                    label: '资料库分类',
                    collapsible: true,
                    isExpanded: _isDocsCatExpanded,
                    onToggle: () => setState(
                      () => _isDocsCatExpanded = !_isDocsCatExpanded,
                    ),
                  ),
                  if (_isDocsCatExpanded) ...<Widget>[
                    _HtmlSidebarSubItem(
                      icon: Icons.description_outlined,
                      label: '官方说明书',
                      selected:
                          widget.destination == _DesktopDestination.library &&
                          widget.libraryFilter ==
                              DesktopLibraryResourceType.rulebook,
                      onTap: () => _toggleLibraryFilter(
                        DesktopLibraryResourceType.rulebook,
                      ),
                    ),
                    _HtmlSidebarSubItem(
                      icon: Icons.bolt,
                      label: '玩家速查卡',
                      selected:
                          widget.destination == _DesktopDestination.library &&
                          widget.libraryFilter ==
                              DesktopLibraryResourceType.playerAid,
                      onTap: () => _toggleLibraryFilter(
                        DesktopLibraryResourceType.playerAid,
                      ),
                    ),
                    _HtmlSidebarSubItem(
                      icon: Icons.help_outline,
                      label: '勘误与 FAQ',
                      selected:
                          widget.destination == _DesktopDestination.library &&
                          widget.libraryFilter ==
                              DesktopLibraryResourceType.faq,
                      onTap: () =>
                          _toggleLibraryFilter(DesktopLibraryResourceType.faq),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _DesktopNavLabel(
                    label: '桌游库人数筛选',
                    collapsible: true,
                    isExpanded: _isPlayersExpanded,
                    onToggle: () => setState(
                      () => _isPlayersExpanded = !_isPlayersExpanded,
                    ),
                  ),
                  if (_isPlayersExpanded) ...<Widget>[
                    _HtmlSidebarSubItem(
                      icon: Icons.person_outline,
                      label: '2 人对决专席',
                      selected: widget.playerFilter == '2',
                      onTap: () => _togglePlayerFilter('2'),
                    ),
                    _HtmlSidebarSubItem(
                      icon: Icons.people_outline,
                      label: '3–4 人标准局',
                      selected: widget.playerFilter == '3-4',
                      onTap: () => _togglePlayerFilter('3-4'),
                    ),
                    _HtmlSidebarSubItem(
                      icon: Icons.auto_awesome_outlined,
                      label: '5 人以上聚会',
                      selected: widget.playerFilter == '5+',
                      onTap: () => _togglePlayerFilter('5+'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _DesktopNavLabel(
                    label: '策略重度',
                    collapsible: true,
                    isExpanded: _isWeightExpanded,
                    onToggle: () =>
                        setState(() => _isWeightExpanded = !_isWeightExpanded),
                  ),
                  if (_isWeightExpanded) ...<Widget>[
                    _HtmlSidebarSubItem(
                      icon: Icons.filter_vintage_outlined,
                      label: '轻度欢乐',
                      selected: widget.weightFilter == '轻度',
                      onTap: () => _toggleWeightFilter('轻度'),
                    ),
                    _HtmlSidebarSubItem(
                      icon: Icons.balance_outlined,
                      label: '中度策略',
                      selected: widget.weightFilter == '中度',
                      onTap: () => _toggleWeightFilter('中度'),
                    ),
                    _HtmlSidebarSubItem(
                      icon: Icons.landscape_outlined,
                      label: '德式重策',
                      selected: widget.weightFilter == '重度',
                      onTap: () => _toggleWeightFilter('重度'),
                    ),
                  ],
                ],
                if (!widget.compact) ...<Widget>[
                  const SizedBox(height: 14),
                  _DesktopNavLabel(label: copy.desktopSystem),
                  const SizedBox(height: 6),
                  _HtmlSidebarItem(
                    icon: Icons.tune_rounded,
                    label: copy.desktopSettings,
                    selected:
                        widget.destination == _DesktopDestination.settings,
                    onTap: () =>
                        widget.onSelected(_DesktopDestination.settings),
                  ),
                ],
              ],
            ),
          ),
          _HtmlWorkspaceIdentity(onTap: widget.onOpenAbout),
        ],
      ),
    );
  }

  void _openAllGames() {
    widget.onPlayerFilterChanged(null);
    widget.onWeightFilterChanged(null);
    widget.onSelected(_DesktopDestination.games);
  }

  void _openAllLibrary() {
    widget.onLibraryFilterChanged(null);
    widget.onSelected(_DesktopDestination.library);
  }

  void _togglePlayerFilter(String value) {
    widget.onPlayerFilterChanged(widget.playerFilter == value ? null : value);
  }

  void _toggleWeightFilter(String value) {
    widget.onWeightFilterChanged(widget.weightFilter == value ? null : value);
  }

  void _toggleLibraryFilter(DesktopLibraryResourceType value) {
    widget.onLibraryFilterChanged(widget.libraryFilter == value ? null : value);
  }
}

class _HtmlSidebarItem extends StatelessWidget {
  const _HtmlSidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF161E2A) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border(
              left: BorderSide(
                color: selected ? const Color(0xFF66C0F4) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 15,
                color: selected
                    ? const Color(0xFF66C0F4)
                    : const Color(0xFF8A96A3),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF8A96A3),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  count!,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF66C0F4)
                        : const Color(0xFF8A96A3),
                    fontSize: 10.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HtmlSidebarSubItem extends StatelessWidget {
  const _HtmlSidebarSubItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 31,
          padding: const EdgeInsets.only(left: 28, right: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF161E2A) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: selected
                ? const Border(
                    left: BorderSide(color: Color(0xFF66C0F4), width: 2),
                  )
                : null,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 14,
                color: selected
                    ? const Color(0xFF66C0F4)
                    : const Color(0xFF8A96A3),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF8A96A3),
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HtmlWorkspaceIdentity extends StatelessWidget {
  const _HtmlWorkspaceIdentity({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0x33000000),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: const Row(
            children: <Widget>[
              SizedBox(
                width: 32,
                height: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[Color(0xFF24354A), Color(0xFF151E2A)],
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0x4766C0F4)),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF66C0F4),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '本地工作区',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '已就绪 · 本地资料',
                      style: TextStyle(
                        color: Color(0xFF8A96A3),
                        fontSize: 10.5,
                      ),
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

class _DesktopNavLabel extends StatelessWidget {
  const _DesktopNavLabel({
    required this.label,
    this.collapsible = false,
    this.isExpanded = true,
    this.onToggle,
  });

  final String label;
  final bool collapsible;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final Widget labelText = Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: const Color(0xFF8A96A3),
        letterSpacing: 0.8,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
    if (!collapsible) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: labelText,
      );
    }
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(child: labelText),
            Icon(
              isExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 14,
              color: const Color(0xFF8A96A3),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _desktopOptionDecoration(
  AppPalette palette, {
  required bool selected,
  double radius = 8,
}) {
  return BoxDecoration(
    color: selected ? palette.surfaceContainer : Colors.transparent,
    borderRadius: BorderRadius.circular(radius),
    border: Border(
      left: BorderSide(
        color: selected ? palette.primary : Colors.transparent,
        width: 3,
      ),
    ),
  );
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.title,
    required this.compact,
    required this.narrow,
    required this.destination,
    required this.copy,
    required this.activityButtonKey,
    required this.activityLayerLink,
    required this.onNew,
    required this.onSearch,
    required this.onOpenActivities,
    required this.unreadActivityCount,
    required this.onNavigateBack,
    required this.onNavigateForward,
    required this.onSelectDestination,
    required this.onMinimizeWindow,
    required this.onToggleMaximizeWindow,
    required this.onCloseWindow,
    required this.windowMaximized,
    this.primaryAction,
    this.primaryLabel,
  });

  final String title;
  final bool compact;
  final bool narrow;
  final _DesktopDestination destination;
  final AppCopy copy;
  final GlobalKey activityButtonKey;
  final LayerLink activityLayerLink;
  final VoidCallback onNew;
  final VoidCallback onSearch;
  final VoidCallback onOpenActivities;
  final int unreadActivityCount;
  final VoidCallback onNavigateBack;
  final VoidCallback onNavigateForward;
  final ValueChanged<_DesktopDestination> onSelectDestination;
  final Future<void> Function() onMinimizeWindow;
  final Future<void> Function() onToggleMaximizeWindow;
  final Future<void> Function() onCloseWindow;
  final bool windowMaximized;
  final VoidCallback? primaryAction;
  final String? primaryLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Widget header = Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xE012171F),
        border: Border(bottom: BorderSide(color: palette.outline)),
      ),
      child: Row(
        children: <Widget>[
          _DesktopHeaderIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: '后退',
            onPressed: onNavigateBack,
          ),
          const SizedBox(width: 4),
          _DesktopHeaderIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: '前进',
            onPressed: onNavigateForward,
          ),
          const SizedBox(width: 16),
          _DesktopHeaderBrand(compact: narrow),
          if (!narrow) ...[
            const SizedBox(width: 16),
            Container(width: 1, height: 20, color: palette.outline),
            const SizedBox(width: 18),
            _DesktopHeaderTab(
              label: '首页',
              selected: destination == _DesktopDestination.home,
              onPressed: () => onSelectDestination(_DesktopDestination.home),
            ),
            const SizedBox(width: 18),
            _DesktopHeaderTab(
              label: '桌游库',
              selected:
                  destination == _DesktopDestination.games ||
                  destination == _DesktopDestination.gameDetail,
              onPressed: () => onSelectDestination(_DesktopDestination.games),
            ),
            const SizedBox(width: 18),
            _DesktopHeaderTab(
              label: '规则资料库',
              selected: destination == _DesktopDestination.library,
              onPressed: () => onSelectDestination(_DesktopDestination.library),
            ),
            if (destination == _DesktopDestination.gameDetail) ...<Widget>[
              const SizedBox(width: 18),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8A96A3),
                  fontSize: 11.5,
                ),
              ),
            ],
          ],
          const Spacer(),
          if (!narrow)
            Tooltip(
              message: '搜索',
              child: SizedBox(
                width: compact ? 150 : 200,
                height: 28,
                child: TextField(
                  onTap: onSearch,
                  onSubmitted: (_) => onSearch(),
                  style: const TextStyle(
                    color: Color(0xFFC7D5E0),
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    hintText: '搜索战局、桌游或规则...',
                    hintStyle: TextStyle(
                      color: Color(0xFF8A96A3),
                      fontSize: 11.5,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 14,
                      color: Color(0xFF8A96A3),
                    ),
                    filled: true,
                    fillColor: Color(0x4D000000),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0x12FFFFFF)),
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0x12FFFFFF)),
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0x4766C0F4)),
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            )
          else
            _DesktopHeaderIconButton(
              icon: Icons.search_rounded,
              tooltip: copy.desktopSearchAction,
              onPressed: onSearch,
            ),
          const SizedBox(width: 10),
          if (!compact && primaryAction != null)
            _DesktopHeaderActionButton(
              icon: Icons.chat_bubble_outline_rounded,
              label: primaryLabel ?? copy.askAiAssistant,
              onPressed: primaryAction!,
            )
          else if (!compact)
            _DesktopHeaderActionButton(
              icon: Icons.add_rounded,
              label: copy.desktopCreate,
              onPressed: onNew,
            )
          else
            _DesktopHeaderIconButton(
              icon: primaryAction != null
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.add_rounded,
              tooltip: primaryLabel ?? copy.desktopCreate,
              onPressed: primaryAction ?? onNew,
            ),
          const SizedBox(width: 4),
          CompositedTransformTarget(
            link: activityLayerLink,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                IconButton(
                  key: activityButtonKey,
                  tooltip: copy.activityTitle,
                  onPressed: onOpenActivities,
                  style: _desktopIconButtonStyle(palette),
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
          if (!narrow &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.windows)
            _DesktopWindowControls(
              maximized: windowMaximized,
              onMinimize: onMinimizeWindow,
              onToggleMaximize: onToggleMaximizeWindow,
              onClose: onCloseWindow,
            ),
        ],
      ),
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return DragToMoveArea(child: header);
    }
    return header;
  }
}

class _DesktopWindowControls extends StatelessWidget {
  const _DesktopWindowControls({
    required this.maximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final bool maximized;
  final Future<void> Function() onMinimize;
  final Future<void> Function() onToggleMaximize;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _DesktopWindowControl(
          icon: Icons.remove_rounded,
          tooltip: '最小化',
          onPressed: onMinimize,
        ),
        _DesktopWindowControl(
          icon: maximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          tooltip: maximized ? '还原' : '最大化',
          onPressed: onToggleMaximize,
        ),
        _DesktopWindowControl(
          icon: Icons.close_rounded,
          tooltip: '关闭',
          close: true,
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _DesktopWindowControl extends StatelessWidget {
  const _DesktopWindowControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.close = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => unawaited(onPressed()),
        child: SizedBox(
          width: 36,
          height: 52,
          child: Icon(
            icon,
            size: 14,
            color: close ? const Color(0xFF8A96A3) : const Color(0xFF8A96A3),
          ),
        ),
      ),
    );
  }
}

class _DesktopHeaderBrand extends StatelessWidget {
  const _DesktopHeaderBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF1F3045), Color(0xFF121D2A)],
            ),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0x4766C0F4)),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x3366C0F4), blurRadius: 8),
            ],
          ),
          child: const Text(
            '♟',
            style: TextStyle(color: Color(0xFF66C0F4), fontSize: 13),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 9),
          const Text(
            '桌游导师',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _DesktopHeaderTab extends StatelessWidget {
  const _DesktopHeaderTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF8A96A3),
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (selected)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFF66C0F4),
                      boxShadow: <BoxShadow>[
                        BoxShadow(color: Color(0x6666C0F4), blurRadius: 8),
                      ],
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

class _DesktopHeaderIconButton extends StatelessWidget {
  const _DesktopHeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        color: const Color(0xFF8A96A3),
        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0x40000000),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

class _DesktopHeaderActionButton extends StatelessWidget {
  const _DesktopHeaderActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 13),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFC7D5E0),
        backgroundColor: const Color(0xFF283E54),
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

class _RulesDrawerOverlay extends StatelessWidget {
  const _RulesDrawerOverlay({
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
        color: _v4Color(
          context,
          Color(0xFF111722),
          AppPalette.of(context).surface,
        ),
        border: Border(
          left: BorderSide(
            color: _v4Color(
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
              color: _v4Color(
                context,
                Color(0xB3121924),
                AppPalette.of(context).surfaceContainer,
              ),
              border: Border(
                bottom: BorderSide(
                  color: _v4Color(
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
                          color: _v4Color(
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
                          color: _v4Color(
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
                  color: _v4Color(
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
              color: _v4Color(
                context,
                Color(0xFF0E131D),
                AppPalette.of(context).surfaceContainer,
              ),
              border: Border(
                bottom: BorderSide(
                  color: _v4Color(
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
                    ? _v4Color(
                        context,
                        Colors.white,
                        AppPalette.of(context).textPrimary,
                      )
                    : _v4Color(
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
                    color: _v4Color(
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
            color: _v4Color(
              context,
              Color(0x40000000),
              AppPalette.of(context).surfaceVariant,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _v4Color(
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
                    color: _v4Color(
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
                          color: _v4Color(
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
                            color: _v4Color(
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
                            color: _v4Color(
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
                                color: _v4Color(
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
                            color: _v4Color(
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
                                color: _v4Color(
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
                          foregroundColor: _v4Color(
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
                  color: _v4Color(
                    context,
                    Color(0xB3161F2C),
                    AppPalette.of(context).surfaceVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _v4Color(
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
                    color: _v4Color(
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
                  color: _v4Color(
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
                  foregroundColor: _v4Color(
                    context,
                    Color(0xFF66C0F4),
                    AppPalette.of(context).primary,
                  ),
                  backgroundColor: _v4Color(
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

ButtonStyle _desktopIconButtonStyle(AppPalette palette) {
  return IconButton.styleFrom(
    foregroundColor: palette.textSecondary,
    backgroundColor: Colors.transparent,
    minimumSize: const Size.square(34),
    maximumSize: const Size.square(34),
    fixedSize: const Size.square(34),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.standard,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
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
    required this.onContinueGame,
    required this.onOpenLibrary,
    required this.onOpenGame,
    required this.onOpenActivities,
    required this.onActivityTap,
  });

  final AppController controller;
  final bool compact;
  final VoidCallback onOpenGames;
  final VoidCallback onOpenAssistant;
  final ValueChanged<String> onContinueGame;
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
          onContinue: () => onContinueGame(game.id),
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
    required this.onContinue,
  });

  final AppCopy copy;
  final GameInfo game;
  final VoidCallback onTap;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    const Color backdrop = Color(0xFF071D2C);
    const Color secondary = Color(0xFFBED1DF);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 760;
        final String artwork = game.id == 'puerto-rico'
            ? 'assets/games/puerto_rico/images/last_game.png'
            : game.bannerAssetPath;
        return Container(
          key: const ValueKey<String>('desktop-last-game-card'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: backdrop,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.primary.withValues(alpha: 0.8)),
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Image.asset(
                  artwork,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0.65, 0.35),
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const ColoredBox(color: backdrop),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        backdrop,
                        backdrop.withValues(alpha: wide ? 0.94 : 0.9),
                        backdrop.withValues(alpha: wide ? 0.22 : 0.72),
                        backdrop.withValues(alpha: 0.12),
                      ],
                      stops: const <double>[0, 0.30, 0.68, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(wide ? 30 : 22),
                child: SizedBox(
                  width: wide ? constraints.maxWidth * 0.57 : double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 4,
                            height: 18,
                            decoration: BoxDecoration(
                              color: palette.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            copy.desktopLastGame,
                            style: textTheme.labelLarge?.copyWith(
                              color: palette.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        game.title,
                        style: textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontSize: wide ? 40 : 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        game.heroTagline.isNotEmpty
                            ? game.heroTagline
                            : game.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(
                          color: secondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 24,
                        runSpacing: 10,
                        children: <Widget>[
                          _metadata(
                            context,
                            Icons.people_outline_rounded,
                            game.playerCount,
                          ),
                          _metadata(
                            context,
                            Icons.schedule_rounded,
                            game.playTime,
                          ),
                          if (game.categoryLine.isNotEmpty)
                            _metadata(
                              context,
                              Icons.bar_chart_rounded,
                              game.categoryLine,
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: onContinue,
                            style: FilledButton.styleFrom(
                              backgroundColor: palette.primary,
                              foregroundColor: backdrop,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 19,
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(copy.desktopContinue),
                          ),
                          OutlinedButton.icon(
                            onPressed: onTap,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: secondary,
                              backgroundColor: const Color(0x55334F69),
                              side: const BorderSide(color: Color(0xFF57788F)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 19,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: Text(
                              copy.isChinese ? '查看详情' : 'View details',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metadata(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20, color: const Color(0xFF9FC5DC)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFBED1DF)),
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(12),
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
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

enum _DesktopGamesFilter { all, recent }

enum _DesktopGamesSort { recent, name, weight }

/// Steam-style game library surface used by the desktop "我的游戏" entry.
///
/// The HTML reference intentionally keeps the grid visually quiet: a strong
/// poster, a restrained toolbar, and hover feedback instead of a card full of
/// metadata. The actual [GameInfo] remains the source of truth, so opening a
/// poster still enters the existing detail flow and uses the real cover.
class _DesktopGamesPane extends StatefulWidget {
  const _DesktopGamesPane({
    required this.controller,
    required this.onOpenGame,
    this.onOpenRules,
    this.onOpenAssistant,
    this.playerFilter,
    this.weightFilter,
    this.onClearFilters,
  });

  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;
  final ValueChanged<GameInfo>? onOpenRules;
  final ValueChanged<GameInfo>? onOpenAssistant;
  final String? playerFilter;
  final String? weightFilter;
  final VoidCallback? onClearFilters;

  @override
  State<_DesktopGamesPane> createState() => _DesktopGamesPaneState();
}

class _DesktopGamesPaneState extends State<_DesktopGamesPane> {
  _DesktopGamesFilter _filter = _DesktopGamesFilter.all;
  _DesktopGamesSort _sort = _DesktopGamesSort.recent;
  final List<String> _recentIds = <String>[];

  @override
  void initState() {
    super.initState();
    _syncRecentGames(widget.controller.games);
  }

  @override
  void didUpdateWidget(covariant _DesktopGamesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _syncRecentGames(widget.controller.games);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = widget.controller;
    if (!controller.hasGames) {
      return _DesktopNoGamesPane(controller: controller);
    }
    _syncRecentGames(controller.games);
    final List<GameInfo> games = _visibleGames(controller.games);
    return SingleChildScrollView(
      key: const ValueKey<String>('desktop-games-library'),
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DesktopGamesHeader(
            count: games.length,
            total: controller.games.length,
          ),
          const SizedBox(height: 20),
          _DesktopGamesToolbar(
            filter: _filter,
            sort: _sort,
            activePlayerFilter: widget.playerFilter,
            activeWeightFilter: widget.weightFilter,
            onClearExtraFilters: widget.onClearFilters,
            onFilterChanged: (value) => setState(() => _filter = value),
            onSortChanged: (value) => setState(() => _sort = value),
          ),
          const SizedBox(height: 24),
          if (games.isEmpty)
            SizedBox(
              height: 240,
              child: _DesktopGamesEmptyState(filter: _filter),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.none,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: math.max(
                    1,
                    ((constraints.maxWidth + 18) / 198).floor(),
                  ),
                  childAspectRatio: 2 / 3,
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 24,
                ),
                itemCount: games.length,
                itemBuilder: (BuildContext context, int index) {
                  final GameInfo game = games[index];
                  return _DesktopPosterCard(
                    key: ValueKey<String>('desktop-game-card-${game.id}'),
                    controller: controller,
                    game: game,
                    onOpenAssistant: widget.onOpenAssistant == null
                        ? null
                        : () => widget.onOpenAssistant!(game),
                    onTap: () {
                      _markRecent(game.id);
                      (widget.onOpenRules ?? widget.onOpenGame)(game);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<GameInfo> _visibleGames(List<GameInfo> source) {
    final List<GameInfo> result = source.where((game) {
      switch (_filter) {
        case _DesktopGamesFilter.all:
          break;
        case _DesktopGamesFilter.recent:
          if (!_recentIds.contains(game.id)) return false;
      }
      if (!_matchesPlayerCount(game, widget.playerFilter)) return false;
      if (!_matchesWeight(game, widget.weightFilter)) return false;
      return true;
    }).toList();
    result.sort((a, b) {
      switch (_sort) {
        case _DesktopGamesSort.recent:
          final int aIndex = _recentIds.indexOf(a.id);
          final int bIndex = _recentIds.indexOf(b.id);
          final int aRank = aIndex < 0 ? 1 << 20 : aIndex;
          final int bRank = bIndex < 0 ? 1 << 20 : bIndex;
          return aRank != bRank
              ? aRank.compareTo(bRank)
              : source.indexOf(a).compareTo(source.indexOf(b));
        case _DesktopGamesSort.name:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case _DesktopGamesSort.weight:
          return _weightRank(a).compareTo(_weightRank(b));
      }
    });
    return result;
  }

  int _weightRank(GameInfo game) {
    final String value = '${game.complexity} ${game.learningDifficulty}'
        .toLowerCase();
    if (value.contains('重') ||
        value.contains('hard') ||
        value.contains('heavy')) {
      return 2;
    }
    if (value.contains('中') || value.contains('medium')) return 1;
    return 0;
  }

  bool _matchesPlayerCount(GameInfo game, String? filter) {
    if (filter == null || filter.isEmpty) return true;
    final String text = game.playerCount;
    final RegExpMatch? match = RegExp(
      r'(\d+)\s*[-–~至到]\s*(\d+)',
    ).firstMatch(text);
    if (filter == '2') {
      if (match != null) {
        final int min = int.tryParse(match.group(1) ?? '') ?? 0;
        final int max = int.tryParse(match.group(2) ?? '') ?? 99;
        return min <= 2 && 2 <= max;
      }
      return text.contains('2');
    }
    if (filter == '3-4') {
      if (match != null) {
        final int min = int.tryParse(match.group(1) ?? '') ?? 0;
        final int max = int.tryParse(match.group(2) ?? '') ?? 99;
        return min <= 4 && max >= 3;
      }
      return text.contains('3') || text.contains('4');
    }
    if (filter == '5+') {
      if (match != null) {
        final int max = int.tryParse(match.group(2) ?? '') ?? 0;
        return max >= 5;
      }
      final Iterable<int> values = RegExp(r'\d+')
          .allMatches(text)
          .map((RegExpMatch item) => int.tryParse(item.group(0) ?? '') ?? 0);
      return values.any((int value) => value >= 5) || text.contains('5');
    }
    return true;
  }

  bool _matchesWeight(GameInfo game, String? filter) {
    if (filter == null || filter.isEmpty) return true;
    final int rank = _weightRank(game);
    if (filter == '轻度') return rank == 0;
    if (filter == '中度') return rank == 1;
    if (filter == '重度') return rank == 2;
    return true;
  }

  void _syncRecentGames(List<GameInfo> games) {
    final Set<String> available = games.map((game) => game.id).toSet();
    _recentIds.removeWhere((id) => !available.contains(id));
    if (_recentIds.isEmpty && games.isNotEmpty) {
      _recentIds.add(games.first.id);
    }
  }

  void _markRecent(String id) {
    setState(() {
      _recentIds
        ..remove(id)
        ..insert(0, id);
    });
  }
}

class _DesktopGamesHeader extends StatelessWidget {
  const _DesktopGamesHeader({required this.count, required this.total});

  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '我的游戏',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '选择桌游，直接查看规则档案与 AI 推演支持。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
        Text(
          '$count / $total 个项目',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: palette.textSecondary,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _DesktopGamesToolbar extends StatelessWidget {
  const _DesktopGamesToolbar({
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onSortChanged,
    this.activePlayerFilter,
    this.activeWeightFilter,
    this.onClearExtraFilters,
  });

  final _DesktopGamesFilter filter;
  final _DesktopGamesSort sort;
  final ValueChanged<_DesktopGamesFilter> onFilterChanged;
  final ValueChanged<_DesktopGamesSort> onSortChanged;
  final String? activePlayerFilter;
  final String? activeWeightFilter;
  final VoidCallback? onClearExtraFilters;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final bool hasExtraFilter =
        activePlayerFilter != null || activeWeightFilter != null;
    final String extraFilterLabel = <String?>[
      activePlayerFilter == null ? null : '${activePlayerFilter!}人',
      activeWeightFilter,
    ].whereType<String>().join(' · ');
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.outline)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _DesktopGamesFilterButton(
                  label: '全部',
                  selected: filter == _DesktopGamesFilter.all,
                  onTap: () => onFilterChanged(_DesktopGamesFilter.all),
                ),
                _DesktopGamesFilterButton(
                  label: '最近游玩',
                  selected: filter == _DesktopGamesFilter.recent,
                  onTap: () => onFilterChanged(_DesktopGamesFilter.recent),
                ),
                if (hasExtraFilter)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InputChip(
                      label: Text(
                        extraFilterLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF66C0F4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      deleteIcon: const Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: Color(0xFF66C0F4),
                      ),
                      onDeleted: onClearExtraFilters,
                      backgroundColor: const Color(0x2666C0F4),
                      side: const BorderSide(color: Color(0x5966C0F4)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '排序',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(width: 6),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF10161F),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0x12FFFFFF)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_DesktopGamesSort>(
                value: sort,
                isDense: true,
                dropdownColor: palette.surfaceVariant,
                iconEnabledColor: palette.textSecondary,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: palette.textPrimary),
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
                items: const <DropdownMenuItem<_DesktopGamesSort>>[
                  DropdownMenuItem(
                    value: _DesktopGamesSort.recent,
                    child: Text('最近打开'),
                  ),
                  DropdownMenuItem(
                    value: _DesktopGamesSort.name,
                    child: Text('名称拼音'),
                  ),
                  DropdownMenuItem(
                    value: _DesktopGamesSort.weight,
                    child: Text('重度等级'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopGamesFilterButton extends StatefulWidget {
  const _DesktopGamesFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DesktopGamesFilterButton> createState() =>
      _DesktopGamesFilterButtonState();
}

class _DesktopGamesFilterButtonState extends State<_DesktopGamesFilterButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    final bool active = selected || _hovered || _focused;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.ease,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF161E2A) : const Color(0x33000000),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? const Color(0x6666C0F4)
                  : active
                  ? const Color(0xFF2A475E)
                  : Colors.transparent,
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? const Color(0xFF66C0F4)
                    : active
                    ? Colors.white
                    : const Color(0xFF8A96A3),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopGamesEmptyState extends StatelessWidget {
  const _DesktopGamesEmptyState({required this.filter});

  final _DesktopGamesFilter filter;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final String message = switch (filter) {
      _DesktopGamesFilter.recent => '还没有最近打开的桌游。',
      _DesktopGamesFilter.all => '暂无可显示的桌游。',
    };
    return Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
      ),
    );
  }
}

class _DesktopPosterCard extends StatefulWidget {
  const _DesktopPosterCard({
    super.key,
    required this.controller,
    required this.game,
    required this.onTap,
    this.onOpenAssistant,
  });

  final AppController controller;
  final GameInfo game;
  final VoidCallback onTap;
  final VoidCallback? onOpenAssistant;

  @override
  State<_DesktopPosterCard> createState() => _DesktopPosterCardState();
}

class _DesktopPosterCardState extends State<_DesktopPosterCard> {
  static const double _previewWidth = 290;
  static const double _previewGap = 14;
  static const double _previewEstimatedHeight = 318;

  final LayerLink _previewLink = LayerLink();
  OverlayEntry? _previewEntry;
  Timer? _previewHideTimer;
  bool _hovered = false;
  bool _focused = false;
  bool _previewOnLeft = false;
  bool _previewAlignBottom = false;

  bool get _highlighted => _hovered || _focused;

  @override
  void dispose() {
    _previewHideTimer?.cancel();
    _removePreview();
    super.dispose();
  }

  void _handlePointerEnter() {
    _previewHideTimer?.cancel();
    if (!_hovered) setState(() => _hovered = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hovered) _showPreview();
    });
  }

  void _handlePointerExit() {
    if (_hovered) setState(() => _hovered = false);
    _schedulePreviewHide();
  }

  void _schedulePreviewHide() {
    _previewHideTimer?.cancel();
    _previewHideTimer = Timer(const Duration(milliseconds: 110), () {
      if (mounted) _removePreview();
    });
  }

  void _showPreview() {
    _previewHideTimer?.cancel();
    if (_previewEntry != null) {
      _previewEntry!.markNeedsBuild();
      return;
    }

    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final Offset globalOrigin = renderObject.localToGlobal(Offset.zero);
    final Rect cardRect = globalOrigin & renderObject.size;
    final Size viewport = MediaQuery.sizeOf(context);

    _previewOnLeft =
        cardRect.right + _previewGap + _previewWidth > viewport.width - 16;
    _previewAlignBottom =
        cardRect.top + _previewEstimatedHeight > viewport.height - 20 &&
        cardRect.bottom - _previewEstimatedHeight > 20;

    final OverlayState overlay = Overlay.of(context);
    _previewEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        final Alignment targetAnchor = _previewAlignBottom
            ? (_previewOnLeft ? Alignment.bottomLeft : Alignment.bottomRight)
            : (_previewOnLeft ? Alignment.topLeft : Alignment.topRight);
        final Alignment followerAnchor = _previewAlignBottom
            ? (_previewOnLeft ? Alignment.bottomRight : Alignment.bottomLeft)
            : (_previewOnLeft ? Alignment.topRight : Alignment.topLeft);
        final Offset offset = Offset(
          _previewOnLeft ? -_previewGap : _previewGap,
          0,
        );

        // Overlay entries are laid out by a full-screen Stack. Keep the
        // follower in the original finite preview box so its child cannot
        // expand to the viewport and override _previewWidth.
        return Positioned(
          left: 0,
          top: 0,
          width: _previewWidth,
          child: CompositedTransformFollower(
            link: _previewLink,
            showWhenUnlinked: false,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: offset,
            child: Material(
              type: MaterialType.transparency,
              child: MouseRegion(
                onEnter: (_) => _previewHideTimer?.cancel(),
                onExit: (_) => _schedulePreviewHide(),
                child: _DesktopGameHoverPreview(
                  controller: widget.controller,
                  game: widget.game,
                  onOpenAssistant: widget.onOpenAssistant == null
                      ? null
                      : () {
                          _removePreview();
                          widget.onOpenAssistant!.call();
                        },
                  enterFromRight: _previewOnLeft,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_previewEntry!);
  }

  void _removePreview() {
    _previewHideTimer?.cancel();
    _previewHideTimer = null;
    _previewEntry?.remove();
    _previewEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final GameInfo game = widget.game;
    final Color accent = Color(game.cardAccent);
    return Semantics(
      button: true,
      label: '${game.title}，${game.playerCount}，${game.complexity}',
      child: CompositedTransformTarget(
        link: _previewLink,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _handlePointerEnter(),
          onExit: (_) => _handlePointerExit(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: () {
                    _removePreview();
                    widget.onTap();
                  },
                  onFocusChange: (value) => setState(() => _focused = value),
                  child: AnimatedContainer(
                    key: ValueKey<String>('desktop-poster-${game.id}'),
                    duration: const Duration(milliseconds: 380),
                    curve: const Cubic(0.25, 1, 0.5, 1),
                    transformAlignment: Alignment.topCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, -1 / 1200)
                      // Keep the hover effect inside the grid cell. Scaling a
                      // GridView child makes it overlap neighbouring children,
                      // whose later paint order can visually cover the hovered
                      // poster and create a one-frame "jump". The 3D tilt,
                      // shadow, border and sheen still provide the lift effect
                      // without changing the card's 2D footprint.
                      ..rotateX(_hovered ? math.pi / 50 : 0.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          accent.withValues(alpha: 0.9),
                          Color.lerp(accent, palette.pageBackground, 0.72) ??
                              palette.pageBackground,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: _highlighted
                            ? const Color(0x94FFFFFF)
                            : const Color(0x14FFFFFF),
                        width: 1,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: _hovered
                              ? const Color(0xE6000000)
                              : const Color(0xA6000000),
                          blurRadius: _hovered ? 42 : 14,
                          offset: Offset(0, _hovered ? 22 : 4),
                        ),
                        BoxShadow(
                          color: _hovered
                              ? const Color(0x8C000000)
                              : Colors.transparent,
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: _hovered
                              ? const Color(0x4066C0F4)
                              : Colors.transparent,
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: _DesktopPosterTone(
                      active: _hovered,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            DesktopResolvedImage(
                              controller: widget.controller,
                              assetPath: game.coverAssetPath,
                              palette: palette,
                              fit: BoxFit.cover,
                              placeholderBuilder: (BuildContext context) =>
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: <Color>[
                                          accent.withValues(alpha: 0.9),
                                          Color.lerp(
                                                accent,
                                                palette.pageBackground,
                                                0.72,
                                              ) ??
                                              palette.pageBackground,
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _posterIcon(game),
                                        size: 78,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                            ),
                            Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.ease,
                                opacity: _hovered ? 0.45 : 0.28,
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.ease,
                                  scale: _hovered ? 1.05 : 1,
                                  child: Icon(
                                    _posterIcon(game),
                                    size: 78,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ),
                            const IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: <Color>[
                                      Color(0x14FFFFFF),
                                      Colors.transparent,
                                      Color(0x26000000),
                                      Color(0x99000000),
                                    ],
                                    stops: <double>[0, 0.4, 0.75, 1.0],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: _DesktopPosterSheen(active: _hovered),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _posterIcon(GameInfo game) {
    final String value = '${game.categoryLine} ${game.title}'.toLowerCase();
    if (value.contains('城市') || value.contains('建筑')) {
      return Icons.location_city_rounded;
    }
    if (value.contains('卡') || value.contains('牌')) {
      return Icons.style_rounded;
    }
    if (value.contains('骰')) return Icons.casino_rounded;
    return Icons.extension_rounded;
  }
}

class _DesktopGameHoverPreview extends StatelessWidget {
  const _DesktopGameHoverPreview({
    required this.controller,
    required this.game,
    required this.enterFromRight,
    this.onOpenAssistant,
  });

  final AppController controller;
  final GameInfo game;
  final VoidCallback? onOpenAssistant;
  final bool enterFromRight;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color accent = Color(game.cardAccent);
    final String bannerPath = game.bannerAssetPath.trim().isNotEmpty
        ? game.bannerAssetPath
        : game.coverAssetPath;
    final String title = _previewTitle(game);
    final String status = _rulebookStatus(controller, game);
    final String playTime = game.playTime.trim().isEmpty ? '—' : game.playTime;
    final String perPlayer = game.perPlayerTime.trim().isEmpty
        ? '—'
        : game.perPlayerTime;
    final String complexity = game.complexity.trim().isNotEmpty
        ? game.complexity
        : (game.learningDifficulty.trim().isNotEmpty
              ? game.learningDifficulty
              : '—');

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (BuildContext context, double value, Widget? child) {
        final double dx = (enterFromRight ? 6 : -6) * (1 - value);
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
      child: SizedBox(
        key: ValueKey<String>('desktop-game-hover-preview-${game.id}'),
        width: _DesktopPosterCardState._previewWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF517212E),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x5966C0F4)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0xD9000000),
                blurRadius: 50,
                offset: Offset(0, 20),
              ),
              BoxShadow(color: Color(0x2E66C0F4), blurRadius: 22),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 96,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              accent.withValues(alpha: 0.82),
                              const Color(0xFF132235),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      DesktopResolvedImage(
                        controller: controller,
                        assetPath: bannerPath,
                        palette: palette,
                        fit: BoxFit.cover,
                        placeholderBuilder: (_) => const SizedBox.shrink(),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Colors.transparent,
                              Color(0xF517212E),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF66C0F4),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0x14FFFFFF)),
                      const SizedBox(height: 10),
                      const Text(
                        '游戏时间',
                        style: TextStyle(
                          color: Color(0xFF8F98A0),
                          fontSize: 10.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '单局：$playTime',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFC7D5E0),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '人均：$perPlayer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Color(0xFFC7D5E0),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _DesktopGameHoverStat(
                              label: '适合人数',
                              value: game.playerCount.trim().isEmpty
                                  ? '—'
                                  : game.playerCount,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DesktopGameHoverStat(
                              label: '策略重度',
                              value: complexity,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 36,
                        child: FilledButton(
                          onPressed: onOpenAssistant,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: const Color(0xFF75B022),
                            foregroundColor: const Color(0xFFD8F5A2),
                            disabledBackgroundColor: const Color(0xFF3A4A2A),
                            disabledForegroundColor: const Color(0xFF8F98A0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          child: const Text(
                            '启动 AI 规则问答',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
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

  static String _previewTitle(GameInfo game) {
    final String title = game.title.trim();
    final String edition = game.editionLabel?.trim() ?? '';
    if (edition.isEmpty || title.contains(edition)) return '《$title》';
    return '《$title：$edition》';
  }

  static String _rulebookStatus(AppController controller, GameInfo game) {
    final List<DesktopLibraryResource> rulebooks = controller.libraryResources
        .where(
          (DesktopLibraryResource resource) =>
              resource.gameSlug == game.slug &&
              resource.type == DesktopLibraryResourceType.rulebook,
        )
        .toList(growable: false);
    if (rulebooks.any(
      (DesktopLibraryResource resource) =>
          resource.canOpen && !resource.isRemote,
    )) {
      return '规则手册已缓存 · 离线可用';
    }
    if (rulebooks.any((DesktopLibraryResource resource) => resource.canOpen)) {
      return '规则手册已同步 · 可直接打开';
    }
    if (rulebooks.isNotEmpty) return '规则手册已登记 · 待同步';
    return '规则资料待补充';
  }
}

class _DesktopGameHoverStat extends StatelessWidget {
  const _DesktopGameHoverStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xB30E1621),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: const Color(0x0DFFFFFF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8F98A0), fontSize: 9.5),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _DesktopPosterTone extends StatelessWidget {
  const _DesktopPosterTone({required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: active ? 1 : 0),
    duration: const Duration(milliseconds: 280),
    curve: Curves.ease,
    child: child,
    builder: (context, value, child) {
      // CSS brightness(1.05) followed by contrast(1.02).
      final double scale = 1 + 0.071 * value;
      final double bias = -2.55 * value;
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          scale,
          0,
          0,
          0,
          bias,
          0,
          scale,
          0,
          0,
          bias,
          0,
          0,
          scale,
          0,
          bias,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: child,
      );
    },
  );
}

// Matches test-all.html: steamSheenSweep, 800ms, with an oversized screen-blended band.
class _DesktopPosterSheen extends StatefulWidget {
  const _DesktopPosterSheen({required this.active});
  final bool active;
  @override
  State<_DesktopPosterSheen> createState() => _DesktopPosterSheenState();
}

class _DesktopPosterSheenState extends State<_DesktopPosterSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didUpdateWidget(covariant _DesktopPosterSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
        _sweep.forward(from: 0);
      } else {
        _sweep.reset();
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _DesktopPosterSheenPainter(_sweep)),
  );
}

class _DesktopPosterSheenPainter extends CustomPainter {
  _DesktopPosterSheenPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final double time = animation.value;
    if (time == 0) return;
    const Curve easing = Cubic(0.2, 0.8, 0.25, 1);
    final double progress = easing.transform(time);
    final double opacity = time < 0.3
        ? 0.65 * easing.transform(time / 0.3)
        : 0.65 - 0.23 * easing.transform((time - 0.3) / 0.7);
    final double translation = -0.35 + 0.51 * progress;
    final Rect band = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 2,
      height: size.height * 2,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      size.width * (0.5 + translation * 2),
      size.height * (0.5 + translation * 2),
    );
    canvas.rotate(math.pi / 12);
    final Paint paint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: const Alignment(-0.9063, -0.4226),
        end: const Alignment(0.9063, 0.4226),
        stops: const <double>[0.38, 0.46, 0.50, 0.54, 0.62],
        colors: <Color>[
          Colors.transparent,
          Colors.white.withValues(alpha: 0.05 * opacity),
          Colors.white.withValues(alpha: 0.22 * opacity),
          const Color(0xFF66C0F4).withValues(alpha: 0.12 * opacity),
          Colors.transparent,
        ],
      ).createShader(band);
    canvas.drawRect(band, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DesktopPosterSheenPainter oldDelegate) =>
      oldDelegate.animation != animation;
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

class _DesktopLibraryPane extends StatefulWidget {
  const _DesktopLibraryPane({
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
  State<_DesktopLibraryPane> createState() => _DesktopLibraryPaneState();
}

class _DesktopLibraryPaneState extends State<_DesktopLibraryPane> {
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
