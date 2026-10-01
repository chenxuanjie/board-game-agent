import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';

Future<GameInfo?> showNationalDayGamePicker(
  BuildContext context, {
  required AppController controller,
  required Set<String> selected,
  required Widget Function(GameInfo) coverBuilder,
}) {
  final viewport = MediaQuery.sizeOf(context);
  final compact = viewport.width < 600;
  Widget content(BuildContext context) => SizedBox(
    width: compact ? double.infinity : math.min(560, viewport.width - 64),
    height: math
        .min(
          560,
          math.min(
            viewport.height * (compact ? .7 : .85),
            viewport.height -
                MediaQuery.viewInsetsOf(context).bottom -
                MediaQuery.paddingOf(context).vertical -
                64,
          ),
        )
        .clamp(180.0, 560.0)
        .toDouble(),
    child: _PickerContent(
      controller: controller,
      selected: selected,
      coverBuilder: coverBuilder,
      autofocus: !compact,
    ),
  );
  if (compact) {
    return showModalBottomSheet<GameInfo>(
      context: context,
      sheetAnimationStyle: AppMotion.panelStyle(context),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: content(context),
      ),
    );
  }
  return showDialog<GameInfo>(
    context: context,
    animationStyle: AppMotion.menuStyle(context),
    builder: (context) => Dialog(child: content(context)),
  );
}

class _PickerContent extends StatefulWidget {
  const _PickerContent({
    required this.controller,
    required this.selected,
    required this.coverBuilder,
    required this.autofocus,
  });
  final AppController controller;
  final Set<String> selected;
  final Widget Function(GameInfo) coverBuilder;
  final bool autofocus;
  @override
  State<_PickerContent> createState() => _PickerContentState();
}

class _PickerContentState extends State<_PickerContent> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final copy = widget.controller.copy;
    final games = widget.controller.games
        .where(
          (game) =>
              !widget.selected.contains(game.slug) &&
              '${game.title} ${game.subtitle} ${game.categoryLine}'
                  .toLowerCase()
                  .contains(_query.toLowerCase().trim()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  copy.localized('添加桌游', 'Add a game'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: copy.localized('关闭', 'Close'),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('national-day-picker-search'),
            autofocus: widget.autofocus,
            decoration: InputDecoration(
              hintText: copy.localized('搜索桌游', 'Search games'),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: games.isEmpty
                ? Center(
                    child: Text(copy.localized('没有可添加的桌游', 'No games to add')),
                  )
                : ListView.builder(
                    itemCount: games.length,
                    itemBuilder: (_, index) {
                      final game = games[index];
                      return ListTile(
                        key: ValueKey('national-day-pick-${game.slug}'),
                        leading: SizedBox(
                          width: 40,
                          height: 48,
                          child: widget.coverBuilder(game),
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
    );
  }
}
