import 'package:flutter/material.dart';

import '../app_copy.dart';
import '../../theme/app_palette.dart';

enum DocumentFailureKind { load, render }

class DocumentFailureView extends StatelessWidget {
  const DocumentFailureView({
    super.key,
    required this.copy,
    required this.title,
    required this.kind,
    this.onRetry,
    this.onBack,
  });

  final AppCopy copy;
  final String title;
  final DocumentFailureKind kind;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final bool renderFailed = kind == DocumentFailureKind.render;
    final String message = renderFailed
        ? copy.documentRenderFailed(title)
        : copy.documentLoadFailed(title);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                renderFailed
                    ? Icons.description_outlined
                    : Icons.cloud_off_rounded,
                size: 46,
                color: palette.warning,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: palette.textPrimary,
                  height: 1.5,
                ),
              ),
              if (onRetry != null || onBack != null) ...<Widget>[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    if (onRetry != null)
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(copy.retry),
                      ),
                    if (onBack != null)
                      TextButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: Text(copy.back),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
