// Body primitives adapted from the read-only Desktop reference layout.
import 'package:flutter/material.dart';
import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import '../widgets/desktop_resolved_image.dart';

class HoverSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double lift;
  final bool addShadow;

  const HoverSurface({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.lift = 2,
    this.addShadow = true,
  });

  @override
  State<HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<HoverSurface> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(
            0,
            _hovering ? -widget.lift : 0,
            0,
          ),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: widget.addShadow && _hovering
                ? const [
                    BoxShadow(
                      color: Color(0x1A7D4D2C),
                      blurRadius: 15,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

String desktopContentValue(String value) =>
    value.trim().isEmpty || value == '—' ? '-' : value;

class DesktopContentGame {
  const DesktopContentGame(this.data, this.controller);
  final GameInfo data;
  final AppController controller;
  String get title => desktopContentValue(data.title);
  String get englishTitle => desktopContentValue(data.subtitle);
  String get score => desktopContentValue(data.score);
  String get reviewCount => desktopContentValue(data.scoreCountLabel);
  List<String> get tags => data.keywords.isEmpty ? ['-'] : data.keywords;
  String get tagA => tags.first;
  String get tagB => tags.length > 1 ? tags[1] : '-';
  String get players => desktopContentValue(data.playerCount);
  String get duration => desktopContentValue(data.playTime);
  String get difficulty => desktopContentValue(data.complexity);
  String get description => desktopContentValue(data.summary);
  String get quote => desktopContentValue(data.heroTagline);
  List<String> get mechanisms =>
      tags; // The source provides keywords, not a separate mechanism taxonomy.
  Widget cover() => DesktopResolvedImage(
    controller: controller,
    assetPath: data.coverAssetPath,
    palette: controller.palette,
  );
}

void desktopContentPending(BuildContext context, String feature) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text('$feature · 未开放')));
}

class DesktopContentColumns extends StatelessWidget {
  const DesktopContentColumns({
    super.key,
    required this.main,
    required this.right,
    required this.rightWidth,
    required this.wide,
    this.gap = 14,
  });
  final Widget main, right;
  final double rightWidth, gap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (!wide) return main;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        SizedBox(width: gap),
        SizedBox(width: rightWidth, child: right),
      ],
    );
  }
}

class DesktopContentStatus extends StatelessWidget {
  const DesktopContentStatus({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final loading = controller.homeAssetsLoading;
    if (!loading) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [const LinearProgressIndicator(), const Text('正在加载游戏…')],
      ),
    );
  }
}
