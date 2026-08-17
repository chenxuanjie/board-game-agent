import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/connectivity_status.dart';
import '../../models/game_info.dart';
import '../../models/remote_library_update.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';
import '../widgets/language_sheet.dart';
import 'game_detail_screen.dart';
import 'universal_ai_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onOpenAbout,
  });

  final AppController controller;
  final VoidCallback onOpenAbout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _favouritesOnly = false;
  bool _showingLibraryUpdateDialog = false;
  RemoteLibraryUpdate? _lastSeenUpdate;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final copy = controller.copy;
    final palette = controller.palette;
    final bool showAssetsLoadingBanner = controller.homeAssetsLoading;
    final query = _searchController.text.trim().toLowerCase();
    final games = controller.games.where((game) {
      if (_favouritesOnly && game.id != 'puerto-rico') {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return game.title.toLowerCase().contains(query) ||
          game.subtitle.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: palette.scaffoldBackground,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: palette.primaryGradient,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              ListView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  showAssetsLoadingBanner ? 112 : 22,
                ),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _SearchBar(
                          controller: _searchController,
                          hintText: copy.homeSearchHint,
                          onChanged: (_) => setState(() {}),
                          palette: palette,
                        ),
                      ),
                      const SizedBox(width: 14),
                      _AiOrbButton(
                        palette: palette,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  UniversalAiScreen(controller: controller),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: palette.homeSurface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(30),
                              ),
                            ),
                            builder: (_) => LanguageSheet(
                              controller: controller,
                              onOpenAbout: widget.onOpenAbout,
                            ),
                          );
                        },
                        iconSize: 40,
                        color: Colors.white,
                        icon: const Icon(Icons.settings_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          copy.favouritesOnly,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.homeTextPrimary,
                                fontSize: 18,
                              ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _favouritesOnly,
                        onChanged: (value) =>
                            setState(() => _favouritesOnly = value),
                        activeThumbColor: palette.accentPrimary,
                        activeTrackColor: palette.accentPrimary.withValues(
                          alpha: 0.55,
                        ),
                        inactiveThumbColor: palette.homeTextPrimary.withValues(
                          alpha: 0.24,
                        ),
                        inactiveTrackColor: palette.homeTextPrimary.withValues(
                          alpha: 0.12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ConnectivityStrip(controller: controller),
                  const SizedBox(height: 10),
                  _GlobalAiCard(
                    palette: palette,
                    title: copy.globalAiTitle,
                    subtitle: copy.globalAiSubtitle,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              UniversalAiScreen(controller: controller),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  ...games.map(
                    (game) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _GameListCard(
                        controller: controller,
                        game: game,
                        palette: palette,
                        onTap: () {
                          controller.selectGame(game.id);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  GameDetailScreen(controller: controller),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (showAssetsLoadingBanner)
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: _HomeAssetsLoadingBanner(controller: controller),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _maybeShowLibraryUpdateDialog(AppController controller) async {
    if (!mounted || _showingLibraryUpdateDialog) {
      debugPrint(
        '[updates-ui] skip dialog mounted=$mounted showing=$_showingLibraryUpdateDialog',
      );
      return;
    }
    if (!controller.shouldShowLibraryUpdatePrompt()) {
      debugPrint('[updates-ui] shouldShowLibraryUpdatePrompt=false');
      return;
    }

    _showingLibraryUpdateDialog = true;
    final copy = controller.copy;
    final palette = controller.palette;
    final titles =
        controller.pendingLibraryUpdate?.changedGameTitles ?? const <String>[];
    debugPrint('show update dialog: [${titles.join(', ')}]');
    final bool? shouldUpdate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final update = controller.pendingLibraryUpdate;
        final textTheme = Theme.of(context).textTheme;
        return AlertDialog(
          title: Text(copy.libraryUpdateTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                copy.libraryUpdateMessage,
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.homeTextPrimary.withValues(alpha: 0.88),
                  height: 1.55,
                ),
              ),
              if (update != null &&
                  update.changedGameTitles.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  copy.libraryUpdateGameListLabel(
                    update.changedGameTitles.length,
                  ),
                  style: textTheme.titleSmall?.copyWith(
                    color: palette.homeTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ...update.changedGameTitles.map(
                  (title) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $title',
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.homeTextPrimary.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(copy.updateLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(copy.updateNow),
            ),
          ],
        );
      },
    );
    _showingLibraryUpdateDialog = false;
    if (!mounted) {
      debugPrint('[updates-ui] dialog completed but widget unmounted');
      return;
    }

    if (shouldUpdate == true) {
      debugPrint('[updates-ui] user confirmed update');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(copy.updatingNow)));
      await controller.applyPendingLibraryUpdate();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    debugPrint('[updates-ui] user cancelled update');
    controller.dismissPendingLibraryUpdatePrompt();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final RemoteLibraryUpdate? next = widget.controller.pendingLibraryUpdate;
    if (next != null && !identical(next, _lastSeenUpdate)) {
      _lastSeenUpdate = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeShowLibraryUpdateDialog(widget.controller);
      });
    }
  }
}

class _ConnectivityStrip extends StatelessWidget {
  const _ConnectivityStrip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = controller.palette;
    final copy = controller.copy;
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatusLamp(
            copy: copy,
            dialogTitle: copy.aiStatusDialogTitle,
            label: copy.aiStatusTitle,
            status: controller.aiConnectivityStatus,
            details: <String>[controller.aiConnectivityStatus.message],
            palette: palette,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusLamp(
            copy: copy,
            dialogTitle: copy.assetStatusDialogTitle,
            label: copy.assetStatusTitle,
            status: controller.assetConnectivityStatus,
            details: controller.assetSourceConfigs.map((source) {
              final status = controller.assetSourceStatuses[source.id];
              final stateLabel = _statusSummary(copy, status?.state);
              return '${source.name}: $stateLabel${status == null ? '' : ' · ${status.message}'}';
            }).toList(),
            palette: palette,
          ),
        ),
      ],
    );
  }
}

class _StatusLamp extends StatelessWidget {
  const _StatusLamp({
    required this.copy,
    required this.dialogTitle,
    required this.label,
    required this.status,
    required this.details,
    required this.palette,
  });

  final AppCopy copy;
  final String dialogTitle;
  final String label;
  final ConnectivityStatus status;
  final List<String> details;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final Color lampColor = switch (status.state) {
      ConnectivityState.success => const Color(0xFF26D07C),
      ConnectivityState.warning => const Color(0xFFFFA940),
      ConnectivityState.failure => const Color(0xFFFF5E5E),
      ConnectivityState.unknown => const Color(0xFF8B97A9),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(dialogTitle),
              content: Text(
                details.join('\n'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.homeTextPrimary.withValues(alpha: 0.88),
                  height: 1.5,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(copy.dialogClose),
                ),
              ],
            );
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.cardSurface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: lampColor,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: lampColor.withValues(alpha: 0.45),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.homeTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusSummary(copy, status.state),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.homeTextPrimary.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
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
}

String _statusSummary(AppCopy copy, ConnectivityState? state) {
  return switch (state) {
    ConnectivityState.success => copy.statusReadyShort,
    ConnectivityState.warning => copy.statusLimitedShort,
    ConnectivityState.failure => copy.statusFailedShort,
    ConnectivityState.unknown || null => copy.statusPendingShort,
  };
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.palette,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: palette.homeSearchBackground,
        borderRadius: BorderRadius.circular(30),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: palette.homeTextPrimary),
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: palette.homeTextSecondary,
            size: 32,
          ),
          hintText: hintText,
          hintStyle: TextStyle(color: palette.homeSearchHint, fontSize: 20),
          contentPadding: const EdgeInsets.symmetric(vertical: 22),
        ),
      ),
    );
  }
}

class _AiOrbButton extends StatelessWidget {
  const _AiOrbButton({required this.onTap, required this.palette});

  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[palette.accentPrimary, palette.aiSecondary],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: palette.accentPrimary.withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            const Icon(Icons.forum_rounded, color: Colors.white, size: 34),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: palette.homeSearchBackground,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 12,
                  color: palette.aiSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalAiCard extends StatelessWidget {
  const _GlobalAiCard({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppPalette palette;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        height: 158,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              palette.aiPrimary,
              palette.aiSecondary,
              palette.accentPrimary,
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: <Widget>[
              Positioned(
                top: -20,
                right: -10,
                child: _GlowCircle(
                  size: 112,
                  color: palette.accentSecondary.withValues(alpha: 0.25),
                ),
              ),
              Positioned(
                bottom: -30,
                left: 110,
                child: _GlowCircle(
                  size: 160,
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                  child: const SizedBox(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.psychology_alt_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            style: Theme.of(context).textTheme.displayMedium
                                ?.copyWith(
                                  color: palette.homeTextPrimary,
                                  fontSize: 30,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: palette.homeTextPrimary.withValues(
                                    alpha: 0.84,
                                  ),
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
      ),
    );
  }
}

class _GameListCard extends StatelessWidget {
  const _GameListCard({
    required this.controller,
    required this.game,
    required this.palette,
    required this.onTap,
  });

  final AppController controller;
  final GameInfo game;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Color(game.cardAccent);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        height: 156,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: palette.cardSurface,
        ),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: _AssetCardImage(
                  controller: controller,
                  assetPath: game.bannerAssetPath,
                  fallbackPath: game.coverAssetPath,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.42),
                      palette.detailOverlayMid.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.34),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              top: 18,
              bottom: 18,
              child: Container(
                width: 106,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: _AssetCardImage(
                    controller: controller,
                    assetPath: game.coverAssetPath,
                    fallbackPath: game.bannerAssetPath,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 144,
              right: 18,
              top: 0,
              bottom: 0,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          game.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                color: palette.homeTextPrimary,
                                fontSize: 34,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          game.subtitle,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: palette.homeTextPrimary.withValues(
                                  alpha: 0.76,
                                ),
                              ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${game.playerCount} · ${game.playTime}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: palette.homeTextPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: palette.homeTextPrimary.withValues(alpha: 0.88),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetCardImage extends StatefulWidget {
  const _AssetCardImage({
    required this.controller,
    required this.assetPath,
    required this.fallbackPath,
  });

  final AppController controller;
  final String assetPath;
  final String fallbackPath;

  @override
  State<_AssetCardImage> createState() => _AssetCardImageState();
}

class _AssetCardImageState extends State<_AssetCardImage> {
  String? _resolvedPath;
  bool _triedFallback = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AssetCardImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _resolvedPath = null;
      _triedFallback = false;
      _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? path = _resolvedPath;
    if (path == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[const Color(0xFF102339), const Color(0xFF081426)],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.white54,
            size: 34,
          ),
        ),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        if (!_triedFallback && widget.fallbackPath != widget.assetPath) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) {
              return;
            }
            _triedFallback = true;
            final String? nextPath = await widget.controller.resolveImagePath(
              widget.fallbackPath,
            );
            if (!mounted) {
              return;
            }
            setState(() {
              _resolvedPath = nextPath;
            });
          });
        }
        return const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.white54,
            size: 34,
          ),
        );
      },
    );
  }

  Future<void> _resolve() async {
    final String? path = await widget.controller.resolveImagePath(
      widget.assetPath,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _resolvedPath = path;
    });
  }
}

class _HomeAssetsLoadingBanner extends StatelessWidget {
  const _HomeAssetsLoadingBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = controller.palette;
    final copy = controller.copy;
    final int total = controller.homeAssetsTotal;
    final int loaded = controller.homeAssetsLoaded.clamp(0, total);
    final double progress = total == 0 ? 0 : loaded / total;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: palette.cardSurface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    palette.accentSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  copy.homeAssetsLoadingTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.homeTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                copy.homeAssetsLoadingProgress(loaded, total),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.homeTextPrimary.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: palette.homeTextPrimary.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(
                palette.accentSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
