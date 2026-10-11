part of '../settings_pane.dart';

class _SyncBackupCard extends StatelessWidget {
  const _SyncBackupCard({
    required this.controller,
    required this.settingsController,
    required this.checking,
    required this.onCheckSources,
    this.onEditSource,
    this.transferMenu,
    this.onReorder,
  });
  final AppController controller;
  final WebDavSettingsController? settingsController;
  final bool checking;
  final VoidCallback onCheckSources;
  final ValueChanged<AssetSourceConfig>? onEditSource;
  final Widget? transferMenu;
  final void Function(int, int)? onReorder;
  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    return _SettingsCard(
      icon: Icons.cloud_outlined,
      title: copy.localized('服务器与资料', 'Servers & resources'),
      trailing: transferMenu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResourceAccessSummary(
            controller: controller,
            onEdit: onEditSource,
            onReorder: onReorder,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('desktop-settings-test-sources'),
                onPressed: checking ? null : onCheckSources,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(copy.localized('检测资源访问', 'Check resource access')),
              ),
              if (onEditSource != null &&
                  controller.assetSourceConfigs.isNotEmpty)
                TextButton.icon(
                  key: const ValueKey('desktop-settings-webdav-config'),
                  onPressed: checking
                      ? null
                      : () =>
                            onEditSource!(controller.assetSourceConfigs.first),
                  icon: const Icon(Icons.account_circle_outlined, size: 16),
                  label: Text(copy.localized('账号与连接', 'Account & connections')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutUpdatesCard extends StatelessWidget {
  const _AboutUpdatesCard({
    required this.controller,
    required this.version,
    required this.onOpenAbout,
    required this.onCheckUpdates,
  });

  final AppController controller;
  final Future<String> version;
  final VoidCallback onOpenAbout;
  final VoidCallback onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    return _SettingsCard(
      icon: Icons.info_outline_rounded,
      title: copy.localized('关于与更新', 'About & Updates'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _FieldLabel(
                  label: copy.localized('当前版本', 'Current version'),
                ),
              ),
              FutureBuilder<String>(
                future: version,
                builder: (context, snapshot) => Text(
                  snapshot.data ?? copy.localized('读取中…', 'Loading…'),
                  key: const ValueKey<String>('desktop-settings-app-version'),
                  style: TextStyle(
                    fontSize: _font(context, 13),
                    fontWeight: FontWeight.w600,
                    color: DesktopColors.text,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: _px(context, 11)),
          Row(
            children: <Widget>[
              if (!kIsWeb)
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>(
                      'desktop-settings-check-updates',
                    ),
                    onPressed: onCheckUpdates,
                    icon: Icon(
                      Icons.system_update_alt_rounded,
                      size: _px(context, 17),
                    ),
                    label: Text(
                      copy.localized('检查 Windows 更新', 'Check Windows updates'),
                    ),
                    style: _settingsButtonStyle(context),
                  ),
                ),
              SizedBox(width: _px(context, 9)),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey<String>('desktop-settings-open-about'),
                  onPressed: onOpenAbout,
                  icon: Icon(Icons.open_in_new_rounded, size: _px(context, 17)),
                  label: Text(copy.localized('关于应用', 'About app')),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(0, _px(context, 39)),
                    backgroundColor: DesktopColors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: _px(context, 8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_px(context, 9)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
