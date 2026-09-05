import 'package:flutter/material.dart';

/// Displays an active assistant feature above the composer.
///
/// The same affordance is used by the compact and desktop assistant shells so
/// the selected answer scope stays visible regardless of the window shape.
class AssistantFeatureChip extends StatelessWidget {
  const AssistantFeatureChip({
    super.key,
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onRemove,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: foregroundColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: foregroundColor),
              ),
              const SizedBox(width: 4),
              Icon(Icons.close_rounded, size: 15, color: foregroundColor),
            ],
          ),
        ),
      ),
    );
  }
}
