part of '../settings_pane.dart';

class _SyncBackupCard extends StatelessWidget {
  const _SyncBackupCard({
    required this.controller,
    required this.settingsController,
    required this.urlController,
    required this.usernameController,
    required this.passwordController,
    required this.checking,
    required this.showPassword,
    required this.feedback,
    required this.feedbackSucceeded,
    required this.onTogglePassword,
    required this.onSaveAndCheck,
    required this.onCheckSources,
    this.transferMenu,
    this.onEditSource,
  });

  final AppController controller;
  final WebDavSettingsController? settingsController;
  final TextEditingController urlController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool checking;
  final bool showPassword;
  final String? feedback;
  final bool? feedbackSucceeded;
  final VoidCallback onTogglePassword;
  final VoidCallback onSaveAndCheck;
  final VoidCallback onCheckSources;
  final Widget? transferMenu;
  final ValueChanged<AssetSourceConfig>? onEditSource;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    final List<AssetSourceConfig> sources = controller.assetSourceConfigs;
    final Map<String, ConnectivityStatus> statuses =
        controller.assetSourceStatuses;
    return _SettingsCard(
      icon: Icons.cloud_outlined,
      title: copy.localized('资料与同步', 'Resources & Sync'),
      trailing: settingsController == null ? null : transferMenu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ResourceSourceList(
            sources: sources,
            statuses: statuses,
            copy: copy,
            checking: checking,
            onEdit: onEditSource,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('desktop-settings-test-sources'),
              onPressed: checking ? null : onCheckSources,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(copy.localized('检测资料源', 'Check sources')),
            ),
          ),
          if (settingsController != null)
            ExpansionTile(
              key: const ValueKey('desktop-settings-webdav-config'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                copy.localized('WebDAV 连接设置', 'WebDAV connection'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              children: [
                _EditableValueField(
                  fieldKey: const ValueKey<String>(
                    'desktop-settings-webdav-url',
                  ),
                  label: copy.localized('WebDAV 地址', 'WebDAV URL'),
                  controller: urlController,
                  enabled: !checking,
                ),
                SizedBox(height: _px(context, 8)),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _EditableValueField(
                        fieldKey: const ValueKey<String>(
                          'desktop-settings-webdav-username',
                        ),
                        label: copy.localized('账号', 'Username'),
                        controller: usernameController,
                        enabled: !checking,
                      ),
                    ),
                    SizedBox(width: _px(context, 8)),
                    Expanded(
                      child: _EditableValueField(
                        fieldKey: const ValueKey<String>(
                          'desktop-settings-webdav-password',
                        ),
                        label: copy.localized('密码', 'Password'),
                        controller: passwordController,
                        enabled: !checking,
                        obscureText: !showPassword,
                        trailing: IconButton(
                          tooltip: showPassword
                              ? copy.localized('隐藏密码', 'Hide password')
                              : copy.localized('显示密码', 'Show password'),
                          onPressed: checking ? null : onTogglePassword,
                          icon: Icon(
                            showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: _px(context, 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (feedback != null) ...<Widget>[
                  SizedBox(height: _px(context, 8)),
                  Text(
                    feedback!,
                    key: const ValueKey<String>(
                      'desktop-settings-webdav-feedback',
                    ),
                    style: TextStyle(
                      fontSize: _font(context, 11),
                      height: 1.3,
                      color: feedbackSucceeded == true
                          ? const Color(0xFF497461)
                          : const Color(0xFF9F4D5D),
                    ),
                  ),
                ],
                SizedBox(height: _px(context, 8)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>(
                      'desktop-settings-check-resource-sources',
                    ),
                    onPressed: checking ? null : onSaveAndCheck,
                    icon: checking
                        ? SizedBox.square(
                            dimension: _px(context, 15),
                            child: CircularProgressIndicator(
                              strokeWidth: _px(context, 1.8),
                            ),
                          )
                        : Icon(
                            Icons.network_check_rounded,
                            size: _px(context, 17),
                          ),
                    label: Text(
                      checking
                          ? copy.localized('正在检测', 'Checking')
                          : settingsController == null
                          ? copy.localized('检测资料源', 'Check sources')
                          : copy.localized('保存并检测', 'Save & Test'),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, _px(context, 36)),
                      padding: EdgeInsets.symmetric(
                        horizontal: _px(context, 10),
                      ),
                      foregroundColor: DesktopColors.brown,
                      side: const BorderSide(color: Color(0x1FA76D48)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_px(context, 8)),
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

class _AboutUpdatesCard extends StatelessWidget {
  const _AboutUpdatesCard({
    required this.controller,
    required this.version,
    required this.onOpenAbout,
  });

  final AppController controller;
  final Future<String> version;
  final VoidCallback onOpenAbout;

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
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('desktop-settings-check-updates'),
                  onPressed: onOpenAbout,
                  icon: Icon(
                    Icons.system_update_alt_rounded,
                    size: _px(context, 17),
                  ),
                  label: Text(copy.localized('检查更新', 'Check for updates')),
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
