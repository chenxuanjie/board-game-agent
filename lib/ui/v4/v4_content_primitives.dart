// Body primitives adapted from the read-only V4 reference layout.
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

String v4ContentValue(String value) =>
    value.trim().isEmpty || value == '—' ? '-' : value;

class V4ContentGame {
  const V4ContentGame(this.data, this.controller);
  final GameInfo data;
  final AppController controller;
  String get title => v4ContentValue(data.title);
  String get englishTitle => v4ContentValue(data.subtitle);
  String get score => v4ContentValue(data.score);
  String get reviewCount => v4ContentValue(data.scoreCountLabel);
  List<String> get tags => data.keywords.isEmpty ? ['-'] : data.keywords;
  String get tagA => tags.first;
  String get tagB => tags.length > 1 ? tags[1] : '-';
  String get players => v4ContentValue(data.playerCount);
  String get duration => v4ContentValue(data.playTime);
  String get difficulty => v4ContentValue(data.complexity);
  String get description => v4ContentValue(data.summary);
  String get quote => v4ContentValue(data.heroTagline);
  List<String> get mechanisms =>
      tags; // The source provides keywords, not a separate mechanism taxonomy.
  Widget cover() => DesktopResolvedImage(
    controller: controller,
    assetPath: data.coverAssetPath,
    palette: controller.palette,
  );
}

void v4ContentPending(BuildContext context, String feature) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text('$feature · 未开放')));
}

class V4ContentColumns extends StatelessWidget {
  const V4ContentColumns({
    super.key,
    required this.main,
    required this.right,
    required this.rightWidth,
    this.gap = 14,
  });
  final Widget main, right;
  final double rightWidth, gap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final narrow = box.maxWidth < 900;
      return narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                main,
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: rightWidth),
                    child: right,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: main),
                SizedBox(width: gap),
                SizedBox(width: rightWidth, child: right),
              ],
            );
    },
  );
}

class V4ContentStatus extends StatelessWidget {
  const V4ContentStatus({
    super.key,
    required this.controller,
    required this.onOpenLibrary,
  });
  final AppController controller;
  final VoidCallback onOpenLibrary;
  @override
  Widget build(BuildContext context) {
    final loading = controller.homeAssetsLoading;
    final error = controller.libraryLoadError;
    if (!loading && error == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (loading) const LinearProgressIndicator(),
          Text(error != null ? '资料加载失败，请在资料库重试。' : '正在加载游戏…'),
          if (error != null)
            TextButton(onPressed: onOpenLibrary, child: const Text('打开资料库')),
        ],
      ),
    );
  }
}
