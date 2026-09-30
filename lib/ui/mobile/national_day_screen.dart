import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/services/game_vote_service.dart';
import '../shared/national_day_game_picker.dart';
import 'game_cover.dart';

part 'national_day_artwork.dart';
part 'national_day_cards.dart';

const _cream = Color(0xFFFFF1DE);
const _wine = Color(0xFFA7230B);
const _brown = Color(0xFF8D4D2D);
const _orange = Color(0xFFFF6232);

/// The compact seasonal route uses the same durable list and votes as desktop.
class MobileNationalDayScreen extends StatefulWidget {
  const MobileNationalDayScreen({
    super.key,
    required this.controller,
    required this.onOpenGame,
  });
  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;

  @override
  State<MobileNationalDayScreen> createState() =>
      _MobileNationalDayScreenState();
}

class _MobileNationalDayScreenState extends State<MobileNationalDayScreen> {
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.nationalDayList.load());
    unawaited(widget.controller.gameVotes.sync());
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save(Iterable<String> slugs) async {
    final saved = await widget.controller.nationalDayList.save(slugs);
    if (!saved && mounted) _notice('清单保存失败，请重试');
  }

  Future<void> _add() async {
    final game = await showNationalDayGamePicker(
      context,
      controller: widget.controller,
      selected: widget.controller.nationalDayList.slugs.toSet(),
      coverBuilder: (game) =>
          MobileGameCover(controller: widget.controller, game: game),
    );
    if (!mounted || game == null) return;
    await _save([...widget.controller.nationalDayList.slugs, game.slug]);
  }

  Future<void> _vote(GameInfo game) async {
    final saved = await widget.controller.gameVotes.toggle(game.slug);
    if (!saved && mounted) _notice('投票保存失败，请重试');
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await Clipboard.setData(
        ClipboardData(text: widget.controller.nationalDayShareText),
      ).timeout(const Duration(seconds: 8));
      if (mounted) _notice('清单已复制，可以分享给朋友');
    } catch (_) {
      if (mounted) _notice('复制失败，请重试');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Noto Sans SC'),
      primaryTextTheme: Theme.of(
        context,
      ).primaryTextTheme.apply(fontFamily: 'Noto Sans SC'),
    ),
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        key: const ValueKey('mobile-national-day-root'),
        backgroundColor: const Color(0xFF7A2916),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            widget.controller,
            widget.controller.nationalDayList,
            widget.controller.gameVotes,
          ]),
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/mobile/national_day/background.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    key: const ValueKey('mobile-national-day-scroll'),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 560,
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          children: [
                            _header(),
                            LayoutBuilder(
                              builder: (context, constraints) => SizedBox(
                                height: constraints.maxWidth * .47,
                                child: const _HolidayTitle(),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: _panel(),
                            ),
                            const SizedBox(height: 68),
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
    ),
  );

  Widget _header() {
    final votes = widget.controller.gameVotes;
    final syncing = votes.status == GameVoteSyncStatus.syncing;
    final label =
        votes.loadError ??
        switch (votes.status) {
          GameVoteSyncStatus.localOnly => '投票已保存在本机',
          GameVoteSyncStatus.syncing => '正在同步投票',
          GameVoteSyncStatus.synced => '投票已同步',
          GameVoteSyncStatus.pending => '投票已保存在本机，点此重试同步',
        };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('mobile-national-day-back'),
            tooltip: '返回首页',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
          ),
          const Expanded(
            child: Text(
              '◇  国庆专题  ◇',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: label,
            onPressed: syncing ? null : votes.sync,
            icon: syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    votes.status == GameVoteSyncStatus.synced
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    size: 20,
                    color: Colors.white.withValues(alpha: .85),
                  ),
          ),
          IconButton(
            key: const ValueKey('mobile-national-day-share'),
            tooltip: '分享清单',
            onPressed: _sharing || !widget.controller.nationalDayList.ready
                ? null
                : _share,
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _panel() {
    final list = widget.controller.nationalDayList;
    final games = widget.controller.nationalDayGames;
    return ClipPath(
      clipper: const _CloudPanelClipper(),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF3E3), Color(0xFFFFE4BF), Color(0xFFFFF0DC)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_florist_rounded, color: _orange, size: 18),
                    SizedBox(width: 10),
                    Text(
                      '本次想玩',
                      style: TextStyle(
                        fontFamily: 'National Day Display',
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: _wine,
                      ),
                    ),
                    SizedBox(width: 10),
                    Icon(Icons.local_florist_rounded, color: _orange, size: 18),
                  ],
                ),
              ),
              if (!list.ready && list.error == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                )
              else if (list.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(list.error!),
                      TextButton(
                        onPressed: list.load,
                        child: const Text('重新加载'),
                      ),
                    ],
                  ),
                )
              else ...[
                if (games.isNotEmpty) ...[
                  _card(games.first, featured: true),
                  const SizedBox(height: 10),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '添加一款桌游，邀请朋友一起投票',
                      style: TextStyle(color: _brown),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 16) / 3;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        for (final game in games.skip(1))
                          SizedBox(width: width, child: _card(game)),
                        SizedBox(
                          width: width,
                          child: _AddGameCard(onTap: list.saving ? null : _add),
                        ),
                      ],
                    );
                  },
                ),
                if (list.saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(GameInfo game, {bool featured = false}) => _HolidayGameCard(
    controller: widget.controller,
    game: game,
    featured: featured,
    onOpen: () => widget.onOpenGame(game),
    onVote: () => _vote(game),
    onRemove: widget.controller.nationalDayList.saving
        ? null
        : () => _save(
            widget.controller.nationalDayList.slugs.where(
              (slug) => slug != game.slug,
            ),
          ),
  );
}
