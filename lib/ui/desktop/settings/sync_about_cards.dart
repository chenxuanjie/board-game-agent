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

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    final List<AssetSourceConfig> sources = controller.assetSourceConfigs;
    final Map<String, ConnectivityStatus> statuses =
        controller.assetSourceStatuses;
    final int connected = sources.where((source) {
      return statuses[source.id]?.state == ConnectivityState.success;
    }).length;
    final bool isLoading =
        checking ||
        sources.any((source) {
          return statuses[source.id]?.state == ConnectivityState.loading;
        });
    final String stateLabel;
    final Color stateColor;
    if (sources.isEmpty) {
      stateLabel = copy.localized('未配置', 'Not configured');
      stateColor = DesktopColors.secondaryText;
    } else if (isLoading) {
      stateLabel = copy.localized('检测中', 'Checking');
      stateColor = DesktopColors.brown;
    } else if (connected > 0) {
      stateLabel = copy.localized(
        '已连接 $connected/${sources.length}',
        'Connected $connected/${sources.length}',
      );
      stateColor = const Color(0xFF497461);
    } else if (statuses.isEmpty ||
        sources.every((source) {
          return statuses[source.id] == null ||
              statuses[source.id]?.state == ConnectivityState.unknown;
        })) {
      stateLabel = copy.localized('尚未检测', 'Not checked');
      stateColor = DesktopColors.secondaryText;
    } else {
      stateLabel = copy.localized('连接失败', 'Connection failed');
      stateColor = const Color(0xFF9F4D5D);
    }

    return _SettingsCard(
      icon: Icons.cloud_outlined,
      title: copy.localized('同步与备份', 'Sync & Backup'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      copy.localized(
                        '桌游资料 WebDAV',
                        'Board Game Resources via WebDAV',
                      ),
                      style: TextStyle(
                        fontSize: _font(context, 13),
                        fontWeight: FontWeight.w600,
                        color: DesktopColors.text,
                      ),
                    ),
                    SizedBox(height: _px(context, 3)),
                    Text(
                      copy.localized(
                        '${sources.length} 个资料源；只用于游戏资源，不同步个人数据',
                        '${sources.length} resource sources; game resources only, personal data is not synced',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _font(context, 11),
                        height: 1.25,
                        color: DesktopColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: _px(context, 8)),
              _StatusPill(label: stateLabel, color: stateColor),
            ],
          ),
          SizedBox(height: _px(context, 8)),
          if (settingsController != null) ...<Widget>[
            _EditableValueField(
              fieldKey: const ValueKey<String>('desktop-settings-webdav-url'),
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
                key: const ValueKey<String>('desktop-settings-webdav-feedback'),
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
          ],
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
                  : Icon(Icons.network_check_rounded, size: _px(context, 17)),
              label: Text(
                checking
                    ? copy.localized('正在检测', 'Checking')
                    : settingsController == null
                    ? copy.localized('检测资料源', 'Check sources')
                    : copy.localized('保存并检测', 'Save & Test'),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, _px(context, 36)),
                padding: EdgeInsets.symmetric(horizontal: _px(context, 10)),
                foregroundColor: DesktopColors.brown,
                side: const BorderSide(color: Color(0x1FA76D48)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_px(context, 8)),
                ),
              ),
            ),
          ),
          SizedBox(height: _px(context, 5)),
          _SettingsDivider(height: _px(context, 9)),
          _UnavailableSettingRow(
            icon: Icons.sync_rounded,
            title: copy.localized('个人数据自动同步', 'Automatic Personal Data Sync'),
            subtitle: copy.localized(
              '当前版本不包含个人数据同步',
              'Personal data sync is not included in this version',
            ),
            unavailableLabel: copy.localized('暂不可用', 'Unavailable'),
            compact: true,
          ),
          SizedBox(height: _px(context, 6)),
          Row(
            children: <Widget>[
              Expanded(
                child: _DisabledButton(
                  label: copy.localized('立即同步', 'Sync now'),
                  icon: Icons.sync_rounded,
                  unavailableMessage: copy.localized(
                    '当前版本不可用',
                    'Unavailable in this version',
                  ),
                  key: const ValueKey<String>('desktop-settings-sync-disabled'),
                ),
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: _DisabledButton(
                  label: copy.localized('导入备份', 'Import backup'),
                  icon: Icons.file_download_outlined,
                  unavailableMessage: copy.localized(
                    '当前版本不可用',
                    'Unavailable in this version',
                  ),
                ),
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: _DisabledButton(
                  label: copy.localized('导出备份', 'Export backup'),
                  icon: Icons.file_upload_outlined,
                  unavailableMessage: copy.localized(
                    '当前版本不可用',
                    'Unavailable in this version',
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
          SizedBox(height: _px(context, 8)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _px(context, 11),
              vertical: _px(context, 9),
            ),
            decoration: BoxDecoration(
              color: DesktopColors.soft,
              borderRadius: BorderRadius.circular(_px(context, 8)),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  controller.checkForUpdates
                      ? Icons.update_rounded
                      : Icons.update_disabled_rounded,
                  size: _px(context, 18),
                  color: DesktopColors.orange,
                ),
                SizedBox(width: _px(context, 8)),
                Expanded(
                  child: Text(
                    controller.checkForUpdates
                        ? copy.localized(
                            '启动检查已开启（更新源仅支持 Android APK）',
                            'Startup checks are enabled (the update source supports Android APK only)',
                          )
                        : copy.localized(
                            '启动检查已关闭',
                            'Startup checks are disabled',
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: _font(context, 11.5),
                      height: 1.25,
                      color: DesktopColors.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
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
