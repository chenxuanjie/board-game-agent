import 'package:flutter/material.dart';
import '../../features/library/models/asset_source_config.dart';
import '../../features/settings/services/settings_transfer_service.dart';
import 'account_screen.dart';

class ResourceConnectionScreen extends StatelessWidget {
  const ResourceConnectionScreen({
    super.key,
    required this.service,
    this.source,
  });
  final SettingsTransferService service;
  final AssetSourceConfig? source;
  @override
  Widget build(BuildContext context) =>
      const AccountScreen(showConnections: true);
}
