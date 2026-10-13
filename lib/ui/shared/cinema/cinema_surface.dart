import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/cinema_theme.dart';
import '../../../app/state/app_controller.dart';
import '../../desktop/desktop_resolved_image.dart';

enum CinemaSurfaceRole { navigation, overlay }

class CinemaAmbient extends StatelessWidget {
  const CinemaAmbient({
    super.key,
    required this.controller,
    required this.child,
    required this.path,
  });
  final AppController controller;
  final Widget child;
  final String path;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: AppPalette.of(context).pageBackground),
      if (path.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: .12,
                child: DesktopResolvedImage(
                  controller: controller,
                  assetPath: path,
                  palette: AppPalette.of(context),
                ),
              ),
            ),
          ),
        ),
      child,
    ],
  );
}

/// The role describes an interface surface's purpose, not an image's subject.
class CinemaSurface extends StatelessWidget {
  const CinemaSurface({
    super.key,
    required this.child,
    this.role = CinemaSurfaceRole.navigation,
    this.radius = 20,
  });
  final Widget child;
  final CinemaSurfaceRole role;
  final double radius;
  @override
  Widget build(BuildContext context) {
    if (!isCinema(context)) return child;
    final palette = AppPalette.of(context);
    final enabled =
        Theme.of(context).extension<CinemaMaterialTheme>()?.glassEnabled ==
            true &&
        !MediaQuery.highContrastOf(context);
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final overlay = role == CinemaSurfaceRole.overlay;
    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceContainer.withValues(
          alpha: enabled ? (overlay ? .94 : .90) : 1,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: palette.outline.withValues(alpha: .24)),
      ),
      child: child,
    );
    if (enabled && wide) {
      content = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: overlay ? 16 : 12,
          sigmaY: overlay ? 16 : 12,
        ),
        child: content,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );
  }
}

class CinemaGlassSetting extends StatelessWidget {
  const CinemaGlassSetting({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    key: const ValueKey('cinema-glass-setting'),
    contentPadding: EdgeInsets.zero,
    title: Text(controller.copy.localized('玻璃效果', 'Glass surfaces')),
    subtitle: Text(
      controller.copy.localized('关闭后使用实体底色', 'Use solid surfaces when off'),
    ),
    value: controller.cinemaGlassEnabled,
    onChanged: (value) async {
      try {
        await controller.setCinemaGlassEnabled(value);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                controller.copy.localized(
                  '外观设置未保存，请重试',
                  'Could not save appearance. Retry.',
                ),
              ),
            ),
          );
        }
      }
    },
  );
}
