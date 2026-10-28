import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import 'library_update_review.dart';

class LibraryCheckActions extends StatelessWidget {
  const LibraryCheckActions({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => OutlinedButton.icon(
      key: const ValueKey('library-check-quick'),
      onPressed: controller.checkingLibraryUpdate
          ? null
          : () => showLibraryUpdateReview(context, controller),
      icon: controller.checkingLibraryUpdate
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 20),
      label: Text(controller.copy.localized('检查资料更新', 'Check library updates')),
    ),
  );
}
