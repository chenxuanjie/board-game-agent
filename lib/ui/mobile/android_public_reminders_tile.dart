import 'package:flutter/material.dart';
import '../../core/platform/android_public_reminders.dart';
import '../../features/identity/models/service_configuration.dart';
import '../shared/account_scope.dart';

/// Optional system-scheduled public reminders; available to guests as well.
class AndroidPublicRemindersTile extends StatefulWidget {
  const AndroidPublicRemindersTile({
    super.key,
    required this.checkUpdates,
    this.isChinese = true,
  });
  final bool checkUpdates;
  final bool isChinese;
  @override
  State<AndroidPublicRemindersTile> createState() =>
      _AndroidPublicRemindersTileState();
}

class _AndroidPublicRemindersTileState extends State<AndroidPublicRemindersTile>
    with WidgetsBindingObserver {
  bool _enabled = false, _allowed = false, _busy = true, _changing = false;
  int _generation = 0;
  final _cancellation = ReminderCancellation();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _cancellation.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_changing) return;
    final generation = _generation;
    try {
      final value = await AndroidPublicReminders.state(
        cancellation: _cancellation,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _enabled = value.enabled;
        _allowed = value.allowed;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _change(bool enabled) async {
    if (_busy) return;
    final origin =
        AccountScope.maybeOf(context)?.serviceConfiguration?.origin ??
        Uri.parse(ServiceConfiguration.defaultUpdateOrigin);
    ++_generation;
    setState(() {
      _busy = true;
      _changing = true;
    });
    try {
      await AndroidPublicReminders.configure(
        origin,
        widget.checkUpdates,
        cancellation: _cancellation,
      );
      await AndroidPublicReminders.setEnabled(
        enabled,
        cancellation: _cancellation,
      );
      final value = await AndroidPublicReminders.state(
        cancellation: _cancellation,
      );
      if (!mounted) return;
      setState(() {
        _enabled = value.enabled;
        _allowed = value.allowed;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isChinese
                  ? '无法启用后台提醒，请检查系统通知权限和服务地址'
                  : 'Could not enable reminders. Check notification permission and the service address.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _changing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    key: const ValueKey('android-public-reminders'),
    contentPadding: EdgeInsets.zero,
    value: _enabled,
    onChanged: _busy ? null : _change,
    secondary: const Icon(Icons.notifications_active_outlined),
    title: Text(widget.isChinese ? 'NAS 实时更新提醒' : 'NAS live update reminders'),
    subtitle: Text(
      _enabled && !_allowed
          ? (widget.isChinese
                ? '系统通知已关闭，请在系统设置中允许通知'
                : 'Enable notifications in system settings')
          : (widget.isChinese
                ? '后台保持连接并显示常驻通知，系统限制可能中断'
                : 'Keeps a connection and ongoing notification; system limits may interrupt it'),
    ),
  );
}
