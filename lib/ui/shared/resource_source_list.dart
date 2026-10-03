import 'package:flutter/material.dart';
import '../../core/localization/app_copy.dart';
import '../../core/models/connectivity_status.dart';
import '../../core/theme/app_palette.dart';
import '../../features/library/models/asset_source_config.dart';

/// Source identities and individual results, rather than an aggregate fraction.
class ResourceSourceList extends StatelessWidget {
  const ResourceSourceList({
    super.key,
    required this.sources,
    required this.statuses,
    required this.copy,
    this.checking = false,
    this.onEdit,
  });
  final List<AssetSourceConfig> sources;
  final Map<String, ConnectivityStatus> statuses;
  final AppCopy copy;
  final bool checking;
  final ValueChanged<AssetSourceConfig>? onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (sources.isEmpty) {
      return Text(copy.localized('尚未配置资料源', 'No sources configured'));
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
    final state = checking
        ? ConnectivityState.loading
        : statuses[source.id]?.state ?? ConnectivityState.unknown;
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
            ],
          ),
        ),
        const SizedBox(width: 8),
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
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
