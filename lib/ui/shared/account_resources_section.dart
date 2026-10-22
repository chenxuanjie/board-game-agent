import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/ui_tokens.dart';
import '../../features/identity/services/account_service.dart';
import '../../features/settings/models/configuration_transfer.dart';
import '../../features/settings/services/settings_transfer_service.dart';
import 'nas_connection_section.dart';
import 'resource_access_summary.dart';
import 'settings_transfer_screen.dart';

/// Resource actions share the account service; layout belongs to AccountScreen.
class AccountResourcesSection extends StatefulWidget {
  const AccountResourcesSection({
    super.key,
    required this.service,
    this.expanded = false,
  });
  final AccountService service;
  final bool expanded;

  @override
  State<AccountResourcesSection> createState() =>
      _AccountResourcesSectionState();
}

class _AccountResourcesSectionState extends State<AccountResourcesSection> {
  late final _transfer = SettingsTransferService(
    controller: widget.service.controller,
    account: widget.service,
    webDav: widget.service.webDav,
  );
  bool _checking = false;
  String? _feedback;
  int _connectionsRevision = 0;
  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : zh;

  Future<void> _check() async {
    if (_checking ||
        widget.service.isBusy ||
        !widget.service.resourceCredentialsReady) {
      return;
    }
    setState(() {
      _checking = true;
      _feedback = null;
    });
    try {
      await widget.service.controller.refreshAssetAccessStatus();
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedback = _text('检测失败，请重试', 'Could not check access. Retry.');
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final locked = _checking || service.isBusy;
    return Column(
      key: const ValueKey('account-resources'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _text('知识库连接', 'Knowledge library'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (service.webDav != null)
              SettingsTransferMenu(
                service: _transfer,
                scope: ConfigurationScope.webDav,
                enabled: !locked,
                onApplied: () {
                  if (mounted) {
                    setState(() {
                      _feedback = null;
                      _connectionsRevision++;
                    });
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: UiTokens.itemGap),
        if (service.isSignedIn)
          ResourceAccessSummary(
            controller: service.controller,
            onRefresh: _check,
            refreshing: _checking,
            refreshEnabled: !locked && service.resourceCredentialsReady,
          )
        else
          Text(_text('登录后使用知识库', 'Sign in to use the knowledge library')),
        NasConnectionSection(
          key: ValueKey('nas-$_connectionsRevision'),
          service: service,
          expanded: widget.expanded,
        ),
        if (_feedback != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _feedback!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
