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
      title: copy.localized('资料与同步', 'Resources & Sync'),
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
                        '${sources.length} 个资料源',
                        '${sources.length} resource sources',
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
              Tooltip(
                message: copy.localized(
                  '资料源用于桌游资源；国庆投票使用 WebDAV 设置同步，其他个人数据不在此备份。',
                  'Sources provide game resources. National Day votes use the WebDAV settings to sync; other personal data is not backed up here.',
                ),
                child: Padding(
                  padding: EdgeInsets.only(right: _px(context, 8)),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: _px(context, 18),
                    color: DesktopColors.secondaryText,
                  ),
                ),
              ),
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
