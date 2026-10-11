import 'package:flutter/material.dart';
import '../../core/localization/app_copy.dart';
import '../../core/models/connectivity_status.dart';
import '../../core/theme/app_palette.dart';
import '../../features/library/models/asset_source_config.dart';

/// Entrance identities and individual results, used in the access detail view.
class ResourceSourceList extends StatelessWidget {
  const ResourceSourceList({
    super.key,
    required this.sources,
    required this.statuses,
    required this.copy,
    this.checking = false,
    this.onEdit,
    this.onReorder,
    this.showDetails = false,
  });
  final List<AssetSourceConfig> sources;
  final Map<String, ConnectivityStatus> statuses;
  final AppCopy copy;
  final bool checking;
  final ValueChanged<AssetSourceConfig>? onEdit;
  final void Function(int, int)? onReorder;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (sources.isEmpty) {
      return Text(copy.localized('尚未配置资料源', 'No sources configured'));
    }
    if (onReorder != null) {
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: sources.length,
        onReorder: (from, to) {
          if (!checking) onReorder!(from, to);
        },
        itemBuilder: (context, index) => Padding(
          key: ValueKey(sources[index].id),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: _row(context, sources[index])),
              ReorderableDragStartListener(
                index: index,
                enabled: !checking,
                child: Tooltip(
                  message: copy.localized('拖动排序', 'Drag to reorder'),
                  child: const SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.drag_handle_rounded, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < sources.length; index++) ...[
          if (index > 0)
            Divider(height: 17, color: palette.outline.withValues(alpha: .5)),
          _row(context, sources[index]),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, AssetSourceConfig source) {
    final palette = AppPalette.of(context);
    final uri = Uri.tryParse(source.testUrl);
    final address = uri != null && uri.hasAuthority
        ? uri
              .replace(userInfo: '', query: null, fragment: null)
              .toString()
              .split('?')
              .first
              .split('#')
              .first
        : source.address;
    final state = statuses[source.id]?.state ?? ConnectivityState.unknown;
    final label = switch (state) {
      ConnectivityState.success => copy.localized('已连接', 'Connected'),
      ConnectivityState.failure => copy.localized('未连接', 'Unavailable'),
      ConnectivityState.loading => copy.localized('检测中', 'Checking'),
      ConnectivityState.unknown => copy.localized('未检测', 'Not checked'),
      ConnectivityState.warning => copy.localized('需检查', 'Needs attention'),
    };
    final color = switch (state) {
      ConnectivityState.success => palette.success,
      ConnectivityState.failure => palette.error,
      ConnectivityState.loading => palette.primary,
      ConnectivityState.unknown => palette.textSecondary,
      ConnectivityState.warning => palette.warning,
    };
    return Row(
      key: ValueKey('resource-source-${source.id}'),
      children: [
        Icon(
          source.id == 'lan_share' ? Icons.lan_outlined : Icons.public_rounded,
          size: 19,
          color: palette.textSecondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                label: '${source.name}: $label',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      state == ConnectivityState.success
                          ? Icons.check_circle_outline_rounded
                          : state == ConnectivityState.failure
                          ? Icons.error_outline_rounded
                          : Icons.circle_outlined,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              if (showDetails && statuses[source.id] != null) ...[
                const SizedBox(height: 4),
                Text(
                  copy.localized(
                    statuses[source.id]!.message,
                    switch (statuses[source.id]!.message) {
                      '知识库可读取' => 'Knowledge catalog is readable',
                      '知识库目录内容无效' => 'Invalid knowledge catalog',
                      '需要重新登录' => 'Sign in again',
                      '没有资料访问权限' => 'Resource access denied',
                      '找不到知识库目录' => 'Knowledge directory not found',
                      '资料服务不可用' => 'Resource service unavailable',
                      '连接超时' => 'Connection timed out',
                      '地址无效' => 'Invalid address',
                      '正在检测' => 'Checking',
                      '未检测' => 'Not checked',
                      '地址暂时无法访问' => 'Entrance temporarily unreachable',
                      _ => statuses[source.id]!.message,
                    },
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (onEdit != null)
          IconButton(
            key: ValueKey('edit-resource-source-${source.id}'),
            tooltip: copy.localized('编辑资料源', 'Edit source'),
            onPressed: checking ? null : () => onEdit!(source),
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
      ],
    );
  }
}
