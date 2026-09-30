import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/services/game_vote_service.dart';
import 'desktop_resolved_image.dart';
import 'window_controls.dart';

part 'national_day_artwork.dart';

const _cream = Color(0xFFFFF1DE);
const _wine = Color(0xFF8B200E);
const _brown = Color(0xFF8D4D2D);

/// A full-window seasonal page. The 1448 × 1086 composition follows the
/// supplied artwork; controls stay separate from the decorative title.
class DesktopNationalDayPage extends StatefulWidget {
  const DesktopNationalDayPage({
    super.key,
    required this.controller,
    required this.onOpenGame,
    this.enableNativeWindowControls = false,
  });

  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;
  final bool enableNativeWindowControls;

  @override
  State<DesktopNationalDayPage> createState() => _DesktopNationalDayPageState();
}

class _DesktopNationalDayPageState extends State<DesktopNationalDayPage> {
  final _scroll = ScrollController();
  List<String> _slugs = [];
  bool _loading = true;
  bool _saving = false;
  bool _sharing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(widget.controller.gameVotes.sync());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<GameInfo> get _games => _slugs
      .expand(
        (slug) => widget.controller.games.where((game) => game.slug == slug),
      )
      .toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final stored = await widget.controller.loadNationalDayGameSlugs().timeout(
        const Duration(seconds: 8),
      );
      if (!mounted) return;
      setState(() {
        _slugs =
            stored?.toSet().toList() ??
            widget.controller.defaultNationalDayGames
                .map((game) => game.slug)
                .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '清单读取失败';
      });
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save(List<String> next) async {
    if (_saving || _loading || _loadError != null) return;
    setState(() => _saving = true);
    try {
      await widget.controller
          .saveNationalDayGameSlugs(next)
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _slugs = next);
    } catch (_) {
      if (mounted) _notice('清单保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add() async {
    final game = await showDialog<GameInfo>(
      context: context,
      builder: (_) =>
          _GamePicker(controller: widget.controller, selected: _slugs.toSet()),
    );
    if (!mounted || game == null || _slugs.contains(game.slug)) return;
    await _save([..._slugs, game.slug]);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _scroll.hasClients) {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final games = _games;
      await Clipboard.setData(
        ClipboardData(
          text:
              '国庆聚会 · 桌游清单\n${games.map((game) => '• ${game.title}｜${game.playerCount}｜${game.playTime}').join('\n')}',
        ),
      ).timeout(const Duration(seconds: 8));
      if (mounted) _notice('清单已复制，可以分享给朋友');
    } catch (_) {
      if (mounted) _notice('复制失败，请重试');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.controller,
      widget.controller.gameVotes,
    ]),
    builder: (context, _) {
      final native = widget.enableNativeWindowControls;
      final page = Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/desktop/national_day/background.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
          Positioned.fill(
            top: native ? 32 : 0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = math.min(
                  constraints.maxWidth / 1448,
                  constraints.maxHeight / 1086,
                );
                return Stack(
                  children: [
                    Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 1448,
                          height: 1086,
                          child: Stack(
                            children: [
                              const Positioned(
                                left: 210,
                                right: 160,
                                top: -160,
                                height: 770,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      radius: .5,
                                      colors: [
                                        Color(0xFFFFEBD1),
                                        Color(0xFFFEE6C8),
                                        Color(0xB3FFE8CC),
                                        Color(0x00FFE8CC),
                                      ],
                                      stops: [0, .35, .63, 1],
                                    ),
                                  ),
                                ),
                              ),
                              const Positioned(
                                left: 420,
                                top: 92,
                                width: 610,
                                height: 342,
                                child: _HolidayTitle(),
                              ),
                              Positioned(
                                left: 234,
                                top: 474,
                                width: 996,
                                height: 410,
                                child: _tray(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 60 * scale,
                      right: 42 * scale,
                      top: 0,
                      height: 64 * scale,
                      child: _navigation(scale),
                    ),
                  ],
                );
              },
            ),
          ),
          if (native) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 150,
              height: 32,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
              ),
            ),
            const Positioned(top: 0, right: 0, child: WindowControls()),
          ],
        ],
      );
      return Scaffold(
        key: const ValueKey('desktop-national-day-page'),
        backgroundColor: _brown,
        body: native ? DragToResizeArea(resizeEdgeSize: 6, child: page) : page,
      );
    },
  );

  Widget _navigation(double scale) => Container(
    decoration: BoxDecoration(
      color: _cream.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(40 * scale),
    ),
    padding: EdgeInsets.symmetric(horizontal: 12 * scale),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, color: _wine, size: 18 * scale),
            SizedBox(width: 20 * scale),
            Text(
              '国庆专题',
              style: TextStyle(
                fontFamily: 'National Day Display',
                fontSize: 23 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 3 * scale,
                color: _wine,
              ),
            ),
            SizedBox(width: 20 * scale),
            Icon(Icons.auto_awesome_outlined, color: _wine, size: 18 * scale),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              key: const ValueKey('national-day-back'),
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.chevron_left_rounded, size: 24 * scale),
              label: const Text('返回首页'),
              style: TextButton.styleFrom(
                foregroundColor: _wine,
                backgroundColor: const Color(0xFFFFF6E8),
                textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.w500,
                ),
                padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              ),
            ),
            Row(
              children: [
                _voteSyncControl(scale),
                SizedBox(width: 10 * scale),
                TextButton.icon(
                  key: const ValueKey('national-day-share'),
                  onPressed:
                      _loading || _saving || _sharing || _loadError != null
                      ? null
                      : _share,
                  icon: Icon(Icons.ios_share_rounded, size: 22 * scale),
                  label: const Text('分享'),
                  style: TextButton.styleFrom(
                    foregroundColor: _wine,
                    textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  Widget _voteSyncControl(double scale) {
    final votes = widget.controller.gameVotes;
    final (icon, label, hint) = votes.loadError != null
        ? (Icons.refresh_rounded, '读取失败', '重新读取本地投票')
        : switch (votes.status) {
            GameVoteSyncStatus.localOnly => (
              Icons.phone_android_rounded,
              '仅本地',
              '投票保存在本地；可在设置中配置 WebDAV',
            ),
            GameVoteSyncStatus.syncing => (
              Icons.sync_rounded,
              '同步中',
              '正在同步想玩投票',
            ),
            GameVoteSyncStatus.synced => (
              Icons.cloud_done_outlined,
              '已同步',
              '刷新 WebDAV 投票',
            ),
            GameVoteSyncStatus.pending => (
              Icons.cloud_off_outlined,
              '待同步',
              '本地投票已保留，点击重试同步',
            ),
          };
    return Tooltip(
      message: hint,
      child: TextButton.icon(
        key: const ValueKey('national-day-vote-sync'),
        onPressed: votes.status == GameVoteSyncStatus.syncing
            ? null
            : () => votes.sync(),
        icon: Icon(icon, size: 18 * scale),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: _brown,
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge!.copyWith(fontSize: 16 * scale),
        ),
      ),
    );
  }

  Widget _tray() => ClipRRect(
    borderRadius: BorderRadius.circular(34),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xD9FFE9CE), Color(0xE6F7B887)],
          ),
          border: Border.all(color: const Color(0xBFFFFFF1), width: 2),
          borderRadius: BorderRadius.circular(34),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _wine))
            : _loadError != null
            ? Center(
                child: TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('$_loadError，重试'),
                ),
              )
            : Scrollbar(
                controller: _scroll,
                thumbVisibility: _games.length > 3,
                child: ListView.separated(
                  key: const ValueKey('national-day-games'),
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  itemCount: _games.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 20),
                  itemBuilder: (context, index) => index == _games.length
                      ? _addCard()
                      : _gameCard(_games[index]),
                ),
              ),
      ),
    ),
  );

  Widget _gameCard(GameInfo game) => SizedBox(
    key: ValueKey('national-day-game-${game.slug}'),
    width: 226,
    child: Stack(
      children: [
        Positioned.fill(
          child: Material(
            color: _cream,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
              side: const BorderSide(color: Color(0xFFFFF5E7), width: 2),
            ),
            child: Column(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onOpenGame(game),
                    child: SizedBox.expand(
                      child: _GameCover(
                        controller: widget.controller,
                        game: game,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 94,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          game.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF491E0D),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: widget.controller.gameVotes.hasVoted(game.slug)
                            ? '取消想玩投票'
                            : '投一票：想玩${game.title}',
                        child: TextButton.icon(
                          key: ValueKey('national-day-vote-${game.slug}'),
                          onPressed:
                              widget.controller.gameVotes.saving ||
                                  !widget.controller.gameVotes.ready
                              ? null
                              : () async {
                                  final saved = await widget
                                      .controller
                                      .gameVotes
                                      .toggle(game.slug);
                                  if (!saved && mounted) _notice('投票保存失败，请重试');
                                },
                          icon: Icon(
                            widget.controller.gameVotes.hasVoted(game.slug)
                                ? Icons.thumb_up_rounded
                                : Icons.thumb_up_outlined,
                            color: const Color(0xFFD70A27),
                            size: 29,
                          ),
                          label: Text(
                            '${widget.controller.gameVotes.hasVoted(game.slug) ? '已投' : '想玩'} ${widget.controller.gameVotes.count(game.slug)}',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: _wine,
                            textStyle: Theme.of(
                              context,
                            ).textTheme.labelLarge!.copyWith(fontSize: 19),
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
        Positioned(
          top: 2,
          right: 2,
          child: IconButton.filled(
            key: ValueKey('national-day-remove-${game.slug}'),
            tooltip: '移除${game.title}',
            onPressed: _saving
                ? null
                : () =>
                      _save(_slugs.where((slug) => slug != game.slug).toList()),
            icon: const Icon(Icons.close_rounded, size: 25),
            style: IconButton.styleFrom(
              minimumSize: const Size(38, 38),
              backgroundColor: const Color(0xFFFFF9F0),
              foregroundColor: _wine,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _addCard() => SizedBox(
    width: 226,
    child: Material(
      color: _cream.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        key: const ValueKey('national-day-add'),
        onTap: _saving ? null : _add,
        borderRadius: BorderRadius.circular(25),
        child: CustomPaint(
          painter: const _DashedFrame(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFFBD4B3),
                  shape: BoxShape.circle,
                ),
                child: _saving
                    ? const Padding(
                        padding: EdgeInsets.all(27),
                        child: CircularProgressIndicator(color: _brown),
                      )
                    : const Icon(Icons.add_rounded, size: 62, color: _brown),
              ),
              const SizedBox(height: 12),
              const Text(
                '添加桌游',
                style: TextStyle(
                  color: _brown,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GameCover extends StatelessWidget {
  const _GameCover({required this.controller, required this.game});
  final AppController controller;
  final GameInfo game;

  @override
  Widget build(BuildContext context) => Image.asset(
    game.coverAssetPath,
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => kIsWeb
        ? _placeholder(context)
        : DesktopResolvedImage(
            controller: controller,
            assetPath: game.coverAssetPath,
            palette: controller.palette,
            placeholderBuilder: _placeholder,
          ),
  );

  Widget _placeholder(BuildContext context) => const ColoredBox(
    color: _cream,
    child: Center(child: Icon(Icons.casino_rounded, color: _brown, size: 48)),
  );
}

class _GamePicker extends StatefulWidget {
  const _GamePicker({required this.controller, required this.selected});
  final AppController controller;
  final Set<String> selected;

  @override
  State<_GamePicker> createState() => _GamePickerState();
}

class _GamePickerState extends State<_GamePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final games = widget.controller.games
        .where(
          (game) =>
              !widget.selected.contains(game.slug) &&
              '${game.title} ${game.subtitle} ${game.categoryLine}'
                  .toLowerCase()
                  .contains(_query.toLowerCase().trim()),
        )
        .toList();
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      child: SizedBox(
        width: math.min(560, viewport.width - 64),
        height: math.min(560, viewport.height - 64),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '添加桌游',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('national-day-picker-search'),
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索桌游',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: games.isEmpty
                    ? const Center(child: Text('没有可添加的桌游'))
                    : ListView.builder(
                        itemCount: games.length,
                        itemBuilder: (_, index) {
                          final game = games[index];
                          return ListTile(
                            key: ValueKey('national-day-pick-${game.slug}'),
                            leading: SizedBox(
                              width: 40,
                              height: 48,
                              child: _GameCover(
                                controller: widget.controller,
                                game: game,
                              ),
                            ),
                            title: Text(game.title),
                            subtitle: Text(game.categoryLine),
                            trailing: const Icon(Icons.add_rounded),
                            onTap: () => Navigator.pop(context, game),
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
}
