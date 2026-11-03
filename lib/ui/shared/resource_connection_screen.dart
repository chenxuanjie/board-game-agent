import 'package:flutter/material.dart';
import 'package:webdav_settings/webdav_settings.dart';
import '../../features/settings/services/settings_transfer_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/color_scheme_option.dart';
import 'loading_action_button.dart';

/// WebDAV is an independent optional connection, never a catalog or login source.
class ResourceConnectionScreen extends StatelessWidget {
  const ResourceConnectionScreen({super.key, required this.service});
  final SettingsTransferService service;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WebDAV 备用连接')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: WebDavSettingsSection(
              controller: service.webDav!,
              presentation: const WebDavSyncPresentation(
                detail: '备用连接已保存；当前未配置备份任务。',
              ),
              webDavLabel: 'WebDAV 备用连接',
              useThemeStyle: true,
              testButtonBuilder:
                  AppPalette.of(context).scheme ==
                      ColorSchemeOption.warmwoodStudy
                  ? (context, testing, succeeded, onPressed) {
                      final palette = AppPalette.of(context);
                      return LoadingActionButton(
                        key: const ValueKey('webdav-test-connection'),
                        onPressed: onPressed,
                        loading: testing,
                        succeeded: succeeded,
                        label: '测试连接',
                        loadingLabel: '正在检查',
                        doneLabel: '完成',
                        background: palette.surfaceContainer,
                        foreground: palette.textPrimary,
                        successBackground: palette.success,
                        successForeground: palette.onSuccess,
                      );
                    }
                  : null,
              onSettingsChanged: (_) async {},
            ),
          ),
        ),
      ),
    ),
  );
}
