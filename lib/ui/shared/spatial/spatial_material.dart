import 'dart:ui';
import 'package:flutter/material.dart';

/// One full-window gradient, shared by the title bar and client content.
const spatialDesktopSurface = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2C2A22), Color(0xFF161813), Color(0xFF24261D)],
  ),
);

/// Material values taken from the supplied Flutter reference, not V4 surfaces.
class SpatialGlass extends StatelessWidget {
  const SpatialGlass({super.key, required this.child, this.embedded = false});
  final Widget child;
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    if (embedded) {
      // The native frame owns the single continuous surface, including chrome.
      return child;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .65),
            blurRadius: 65,
            spreadRadius: 10,
            offset: const Offset(0, 32),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2C2A22).withValues(alpha: .79),
                  const Color(0xFF161813).withValues(alpha: .83),
                  const Color(0xFF24261D).withValues(alpha: .72),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: .22),
                width: 1.1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class SpatialScene extends StatelessWidget {
  const SpatialScene({super.key});
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/mobile/mine/header_background_card.jpg',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xA6090A08), Color(0x59090A08), Color(0xB3090A08)],
          ),
        ),
      ),
    ],
  );
}

/// Original static capsule is decoration, not a device battery measurement.
class SpatialCapsule extends StatelessWidget {
  const SpatialCapsule({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 10,
            padding: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2.5),
              border: Border.all(color: Colors.white.withValues(alpha: .75)),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Container(
            width: 1.8,
            height: 3.5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .75),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(1),
                bottomRight: Radius.circular(1),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
