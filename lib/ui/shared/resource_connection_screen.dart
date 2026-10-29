import 'package:flutter/material.dart';
import 'package:webdav_settings/webdav_settings.dart';
import '../../features/settings/services/settings_transfer_service.dart';

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
              onSettingsChanged: (_) async {},
            ),
          ),
        ),
      ),
    ),
  );
}
