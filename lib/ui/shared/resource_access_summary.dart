import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../core/models/connectivity_status.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_motion.dart';
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
    this.onRefresh,
    this.refreshing = false,
    this.refreshEnabled = true,
  });
  final AppController controller;
  final ValueChanged<AssetSourceConfig>? onEdit;
  final void Function(int, int)? onReorder;
  final VoidCallback? onRefresh;
  final bool refreshing;
  final bool refreshEnabled;

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
    builder: (context, _) {
      final checking =
          refreshing ||
          controller.assetConnectivityStatus.isLoading ||
          controller.assetSourceStatuses.values.any(
            (status) => status.isLoading,
          );
      return ListTile(
        key: const ValueKey('resource-access-summary'),
        contentPadding: EdgeInsets.zero,
        title: Text(controller.copy.assetStatusTitle),
        subtitle: _availability(context),
        trailing: onRefresh == null
            ? const Icon(Icons.info_outline_rounded)
            : _ResourceRefreshButton(
                checking: checking,
                tooltip: controller.copy.localized(
                  checking ? '正在刷新资源访问' : '刷新资源访问',
                  checking
                      ? 'Refreshing resource access'
                      : 'Refresh resource access',
                ),
                onPressed: refreshEnabled && !checking ? onRefresh : null,
              ),
        onTap: () => _details(context),
      );
    },
  );
}

class _ResourceRefreshButton extends StatefulWidget {
  const _ResourceRefreshButton({
    required this.checking,
    required this.tooltip,
    this.onPressed,
  });
  final bool checking;
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  State<_ResourceRefreshButton> createState() => _ResourceRefreshButtonState();
}

class _ResourceRefreshButtonState extends State<_ResourceRefreshButton>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: AppMotion.refreshCycle,
  );
  void _updateRotation() {
    if (widget.checking && !AppMotion.reduced(context)) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
      _rotation.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRotation();
  }

  @override
  void didUpdateWidget(_ResourceRefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateRotation();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('resource-access-refresh'),
    tooltip: widget.tooltip,
    onPressed: widget.onPressed,
    icon: RotationTransition(
      key: const ValueKey('resource-access-refresh-rotation'),
      turns: _rotation,
      child: const Icon(Icons.refresh_rounded),
    ),
  );
}
