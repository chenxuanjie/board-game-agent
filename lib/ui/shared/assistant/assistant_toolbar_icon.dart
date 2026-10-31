import 'package:flutter/material.dart';

class AssistantToolbarIcon extends StatelessWidget {
  const AssistantToolbarIcon({
    super.key,
    required this.asset,
    required this.size,
    this.color,
  });

  final String asset;
  final double size;
  final Color? color;

  // The supplied PNGs have different canvas margins. Fit their ink rather than
  // their full canvases so toolbar and menu icons share one visual size.
  static const _inkBounds = <String, Rect>{
    'menu.png': Rect.fromLTRB(443, 556, 811, 720),
    'edit.png': Rect.fromLTRB(286, 289, 1022, 991),
    'more.png': Rect.fromLTRB(562, 353, 692, 911),
    'share.png': Rect.fromLTRB(370, 346, 875, 903),
    'find.png': Rect.fromLTRB(405, 407, 839, 845),
    'delete.png': Rect.fromLTRB(386, 355, 868, 899),
  };

  @override
  Widget build(BuildContext context) {
    final Color tint = color ?? Theme.of(context).colorScheme.onSurface;
    final name = asset.split('/').last;
    // Retain the antialiased edge around the measured dark pixels.
    final bounds = (_inkBounds[name] ?? const Rect.fromLTWH(0, 0, 1254, 1254))
        .inflate(8);
    final factor =
        size / (bounds.width > bounds.height ? bounds.width : bounds.height);
    final hasWhiteBackground = const {
      'share.png',
      'find.png',
      'delete.png',
    }.contains(name);
    final Widget image = Image.asset(
      asset,
      fit: BoxFit.fill,
      excludeFromSemantics: true,
      cacheWidth: (1254 * factor * MediaQuery.devicePixelRatioOf(context))
          .ceil(),
      filterQuality: FilterQuality.high,
    );
    final ColorFilter colorFilter = !hasWhiteBackground
        ? ColorFilter.mode(tint, BlendMode.srcIn)
        : ColorFilter.matrix(<double>[
            0,
            0,
            0,
            0,
            tint.r * 255,
            0,
            0,
            0,
            0,
            tint.g * 255,
            0,
            0,
            0,
            0,
            tint.b * 255,
            -0.299 * tint.a,
            -0.587 * tint.a,
            -0.114 * tint.a,
            tint.a,
            0,
          ]);
    final tintedImage = ColorFiltered(colorFilter: colorFilter, child: image);

    return SizedBox.square(
      dimension: size,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: (size - bounds.width * factor) / 2 - bounds.left * factor,
              top: (size - bounds.height * factor) / 2 - bounds.top * factor,
              width: 1254 * factor,
              height: 1254 * factor,
              child: tintedImage,
            ),
          ],
        ),
      ),
    );
  }
}
