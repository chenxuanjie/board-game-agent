import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../core/models/connectivity_status.dart';
import '../../core/theme/app_palette.dart';
import '../../features/library/models/asset_source_config.dart';
import 'resource_source_list.dart';

/// One resource device, several network entrances. Per-entrance diagnostics are
/// shown on demand while the main settings surface only reports availability.
class ResourceAccessSummary extends StatelessWidget {
  const ResourceAccessSummary({
    super.key,
    required this.controller,
    this.onEdit,
    this.onReorder,
  });
  final AppController controller;
  final ValueChanged<AssetSourceConfig>? onEdit;
  final void Function(int, int)? onReorder;

  String _label(ConnectivityState state) => controller.copy.localized(
    switch (state) {
      ConnectivityState.success => '资源可用',
      ConnectivityState.loading => '正在检测',
      ConnectivityState.failure => '暂不可用',
      _ => '尚未检测',
    },
    switch (state) {
      ConnectivityState.success => 'Available',
      ConnectivityState.loading => 'Checking',
      ConnectivityState.failure => 'Unavailable',
      _ => 'Not checked',
    },
  );

  Widget _availability(BuildContext context) {
    final state = controller.assetConnectivityStatus.state;
    final palette = AppPalette.of(context);
    final color = switch (state) {
      ConnectivityState.success => palette.success,
      ConnectivityState.failure => palette.error,
      _ => palette.textSecondary,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          state == ConnectivityState.success
              ? Icons.check_circle_outline_rounded
              : Icons.circle_outlined,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _label(state),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  void _details(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final checking = controller.assetSourceStatuses.values.any(
            (s) => s.isLoading,
          );
          return AlertDialog(
            title: Text(controller.copy.localized('访问入口', 'Access entrances')),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _availability(context),
                    const SizedBox(height: 12),
                    Text(
                      controller.copy.localized(
                        '这些地址访问同一台设备',
                        'These addresses access the same device',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ResourceSourceList(
                      sources: controller.assetSourceConfigs,
                      statuses: controller.assetSourceStatuses,
                      copy: controller.copy,
                      checking: checking,
                      showDetails: true,
                      // Close before editing so navigation is not hidden by the modal.
                      onEdit: onEdit == null
                          ? null
                          : (source) {
                              Navigator.of(context).pop();
                              onEdit!(source);
                            },
                      onReorder: onReorder,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(controller.copy.dialogClose),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ListTile(
      key: const ValueKey('resource-access-summary'),
      contentPadding: EdgeInsets.zero,
      title: Text(controller.copy.assetStatusTitle),
      subtitle: _availability(context),
      trailing: const Icon(Icons.info_outline_rounded),
      onTap: () => _details(context),
    ),
  );
}
