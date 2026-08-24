import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/app_language.dart';
import '../../models/chat_message.dart';
import '../../models/color_scheme_option.dart';
import '../../models/connectivity_status.dart';
import '../../models/game_info.dart';
import '../../models/remote_library_update.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';
import '../widgets/language_sheet.dart';
import '../widgets/message_bubble.dart';
import 'game_detail_screen.dart';

enum _DesktopDestination { home, games, assistant, library, settings }

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
                        onNew: () =>
                            _selectDestination(_DesktopDestination.games),
                        onRefresh: _showStatus,
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
              _selectDestination(_DesktopDestination.assistant),
          onOpenLibrary: () => _selectDestination(_DesktopDestination.library),
          onOpenGame: _openGame,
        );
      case _DesktopDestination.games:
        return _DesktopGamesPane(controller: controller, onOpenGame: _openGame);
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
    setState(() => _destination = destination);
  }

  void _openGame(GameInfo game) {
    widget.controller.selectGame(game.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameDetailScreen(controller: widget.controller),
      ),
    );
  }

  void _showStatus() {
    final ConnectivityStatus status = widget.controller.aiConnectivityStatus;
    final String message = status.message.trim().isEmpty
        ? widget.controller.copy.statusReadyShort
        : status.message;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _destinationTitle(AppCopy copy) {
    switch (_destination) {
      case _DesktopDestination.home:
        return '首页';
      case _DesktopDestination.games:
        return '我的游戏';
      case _DesktopDestination.assistant:
        return copy.globalAiTitle;
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(copy.libraryUpdateMessage),
              if (update != null && update.changedGameTitles.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...update.changedGameTitles.map(
                  (String title) => Text('• $title'),
                ),
              ],
            ],
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
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onOpenAbout,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: <Widget>[
                    const _DesktopUserAvatar(),
                    const SizedBox(width: 9),
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
                            '2.0 预览',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
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

class _DesktopUserAvatar extends StatelessWidget {
  const _DesktopUserAvatar();

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 15,
      backgroundColor: AppPalette.of(context).secondary,
      foregroundColor: AppPalette.of(context).onSecondary,
      child: const Text('你'),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.title,
    required this.compact,
    required this.onNew,
    required this.onRefresh,
  });

  final String title;
  final bool compact;
  final VoidCallback onNew;
  final VoidCallback onRefresh;

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
          IconButton(
            tooltip: '状态',
            onPressed: onRefresh,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: '搜索',
            onPressed: () {},
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 6),
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
  });

  final AppController controller;
  final bool compact;
  final VoidCallback onOpenGames;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenLibrary;
  final ValueChanged<GameInfo> onOpenGame;

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
            final List<Widget> cards = <Widget>[
              Expanded(
                child: _DesktopRecentGamesCard(
                  controller: controller,
                  onOpenGame: onOpenGame,
                ),
              ),
              Expanded(child: _DesktopStatusCard(controller: controller)),
            ];
            return stack
                ? Column(
                    children: <Widget>[
                      cards[0],
                      const SizedBox(height: 12),
                      cards[1],
                    ],
                  )
                : Row(children: cards);
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
            padding: const EdgeInsets.only(bottom: 7),
            child: _DesktopGameRow(game: game, onTap: () => onOpenGame(game)),
          );
        }).toList(),
      ),
    );
  }
}

class _DesktopGameRow extends StatelessWidget {
  const _DesktopGameRow({required this.game, required this.onTap});

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
              _DesktopGameMark(game: game),
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

class _DesktopStatusCard extends StatelessWidget {
  const _DesktopStatusCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final ConnectivityStatus aiStatus = controller.aiConnectivityStatus;
    return _DesktopSurface(
      title: '状态',
      action: IconButton(
        tooltip: '刷新',
        onPressed: () {},
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: Column(
        children: <Widget>[
          _DesktopStatusRow(
            label: '规则资料',
            value: controller.homeAssetsLoading ? '加载中' : '已就绪',
            color: controller.homeAssetsLoading
                ? palette.warning
                : palette.success,
          ),
          _DesktopStatusRow(
            label: 'AI 服务',
            value: _connectivityLabel(aiStatus.state),
            color: _connectivityColor(palette, aiStatus.state),
          ),
          _DesktopStatusRow(
            label: '模型',
            value: controller.hasSelectedAiModel ? '已选择' : '未选择',
            color: controller.hasSelectedAiModel
                ? palette.success
                : palette.warning,
          ),
        ],
      ),
    );
  }

  Color _connectivityColor(AppPalette palette, ConnectivityState state) {
    return switch (state) {
      ConnectivityState.success => palette.success,
      ConnectivityState.warning => palette.warning,
      ConnectivityState.failure => palette.error,
      ConnectivityState.unknown => palette.disabledForeground,
    };
  }

  String _connectivityLabel(ConnectivityState state) {
    return switch (state) {
      ConnectivityState.success => '已连接',
      ConnectivityState.warning => '受限',
      ConnectivityState.failure => '失败',
      ConnectivityState.unknown => '未检测',
    };
  }
}

class _DesktopStatusRow extends StatelessWidget {
  const _DesktopStatusRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
          const SizedBox(width: 8),
          Icon(Icons.check_circle_outline_rounded, size: 17, color: color),
        ],
      ),
    );
  }
}

class _DesktopGameMark extends StatelessWidget {
  const _DesktopGameMark({required this.game});

  final GameInfo game;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      width: 36,
      height: 36,
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
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: <Color>[
                            Color(game.cardAccent),
                            palette.surfaceContainer,
                          ],
                        ),
                      ),
                      child: Text(
                        _shortGameMark(game.title),
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: palette.onPrimary,
                              fontWeight: FontWeight.w800,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.messagesForContext(useGlobalMode: false).isEmpty) {
        controller.resetConversation(useGlobalMode: false);
      }
    });
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
    final List<ChatMessage> messages = controller.messagesForContext(
      useGlobalMode: false,
    );
    final GameInfo game = controller.featuredGame;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.pageBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.outline),
        ),
        child: Row(
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
                                '${game.title}助手',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '官方资料已加载',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '清空对话',
                          onPressed: () =>
                              controller.clearConversationForContext(
                                useGlobalMode: false,
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
                                    useGlobalMode: false,
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
              child: _DesktopContextPanel(controller: controller),
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
    await controller.sendPrompt(text, useGlobalMode: false);
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

class _DesktopAssistantSessions extends StatelessWidget {
  const _DesktopAssistantSessions({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${controller.featuredGame.title}助手',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text('当前对局', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _DesktopSessionRow(
            icon: Icons.message_outlined,
            title: '规则问答',
            subtitle: '${controller.messages.length} 条消息',
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
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.labelMedium),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
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
  const _DesktopContextPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final bool smartSupplement = controller.allowSmartSupplement(
      useGlobalMode: false,
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
            label: controller.featuredGame.title,
          ),
          _DesktopContextLine(icon: Icons.menu_book_outlined, label: '规则书'),
          _DesktopContextLine(icon: Icons.fact_check_outlined, label: 'FAQ'),
          const SizedBox(height: 18),
          Text('回答模式', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _DesktopContextToggle(
            label: '官方资料优先',
            selected: !smartSupplement,
            onTap: () =>
                controller.setAllowSmartSupplement(false, useGlobalMode: false),
          ),
          _DesktopContextToggle(
            label: '允许智能补充',
            selected: smartSupplement,
            onTap: () =>
                controller.setAllowSmartSupplement(true, useGlobalMode: false),
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
              onPressed: () {},
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
