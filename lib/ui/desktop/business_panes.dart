import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/models/app_activity.dart';
import '../../features/assistant/models/ai_api_config.dart';
import '../../features/assistant/models/ai_conversation.dart';
import '../../features/assistant/models/ai_run.dart';
import '../../features/assistant/models/answer_source.dart';
import '../../features/assistant/models/chat_message.dart';
import '../../core/theme/color_scheme_option.dart';
import '../../features/library/models/desktop_library_resource.dart';
import '../../features/games/models/game_info.dart';
import '../../features/library/models/game_resource.dart';
import '../../features/library/models/resolved_document.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/localization/app_copy.dart';
import '../shared/assistant/ai_run_activity.dart';
import '../shared/assistant/assistant_feature_chip.dart';
import '../shared/assistant/message_bubble.dart';
import '../shared/documents/markdown_document_screen.dart';
import '../shared/documents/pdf_document_screen.dart';
import '../shared/documents/library_resource_document_screen.dart';
part 'rules_drawer.dart';
part 'activity_popup.dart';
part 'assistant/assistant_pane.dart';
part 'assistant/assistant_sessions.dart';
part 'assistant/assistant_composer.dart';
part 'library/library_pane.dart';

Color _desktopFeatureColor(
  BuildContext context,
  Color original,
  Color replacement,
) => AppPalette.of(context).scheme == ColorSchemeOption.warmwoodStudy
    ? replacement
    : original;

ButtonStyle _desktopIconButtonStyle(AppPalette palette) => IconButton.styleFrom(
  foregroundColor: palette.textSecondary,
  backgroundColor: Colors.transparent,
  minimumSize: const Size.square(34),
  maximumSize: const Size.square(34),
  fixedSize: const Size.square(34),
  padding: EdgeInsets.zero,
  visualDensity: VisualDensity.standard,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
);

BoxDecoration _desktopOptionDecoration(
  AppPalette palette, {
  required bool selected,
  double radius = 8,
}) => BoxDecoration(
  color: selected ? palette.surfaceContainer : Colors.transparent,
  borderRadius: BorderRadius.circular(radius),
  border: Border(
    left: BorderSide(
      color: selected ? palette.primary : Colors.transparent,
      width: 3,
    ),
  ),
);

class _DesktopNoGamesPane extends StatefulWidget {
  const _DesktopNoGamesPane({
    required this.controller,
    this.title,
    this.message,
  });

  final AppController controller;
  final String? title;
  final String? message;

  @override
  State<_DesktopNoGamesPane> createState() => _DesktopNoGamesPaneState();
}

class _DesktopNoGamesPaneState extends State<_DesktopNoGamesPane> {
  bool _loading = false;
  String? _error;

  Future<void> _reload() async {
    if (_loading) return;
    final AppCopy copy = widget.controller.copy;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.controller.reloadGames();
      if (mounted && !widget.controller.hasGames) {
        setState(() => _error = copy.desktopNoGamesMissing);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = copy.desktopNoGamesLoadFailed(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    final String title = widget.title ?? copy.desktopNoGamesTitle;
    final String message = widget.message ?? copy.desktopNoGamesMessage;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: palette.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.inventory_2_outlined,
                  size: 48,
                  color: palette.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.error,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _loading ? null : _reload,
                      icon: _loading
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        _loading
                            ? copy.desktopNoGamesLoading
                            : copy.desktopNoGamesRetry,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(copy.desktopCheckSettingsHint),
                          ),
                        ),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(copy.desktopCheckSettings),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
