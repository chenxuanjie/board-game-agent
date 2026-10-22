import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../core/models/connectivity_status.dart';
import 'library_update_review.dart';

/// Manual check actions share the same availability gate on every layout.
class LibraryCheckActions extends StatelessWidget {
  const LibraryCheckActions({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final copy = controller.copy;
      final state = controller.assetConnectivityStatus.state;
      final checking = controller.checkingLibraryUpdate;
      final updating = controller.applyingLibraryUpdate;
      final enabled =
          controller.libraryAccessAllowed &&
          state == ConnectivityState.success &&
          !updating;
      final hint = !controller.libraryAccessAllowed
          ? copy.localized(
              '请先登录并连接 WebDAV',
              'Sign in and connect to WebDAV first',
            )
          : updating
          ? copy.localized('正在更新资料，请稍候', 'Updating resources. Please wait.')
          : switch (state) {
              ConnectivityState.loading => copy.localized(
                '正在检测资源访问，请稍候',
                'Checking resource access. Please wait.',
              ),
              ConnectivityState.unknown => copy.localized(
                '尚未检测资源访问，请先刷新',
                'Resource access has not been checked. Refresh first.',
              ),
              _ => copy.localized(
                'WebDAV 暂不可用，请刷新资源访问',
                'WebDAV is unavailable. Refresh resource access.',
              ),
            };
      Widget action(bool complete) => Tooltip(
        message: enabled
            ? copy.localized(
                complete ? '检查已登记资料的服务器版本信息' : '检查桌游目录变化',
                complete
                    ? 'Check server versions of registered resources'
                    : 'Check game catalog changes',
              )
            : hint,
        child: OutlinedButton.icon(
          key: ValueKey(
            complete ? 'library-check-full' : 'library-check-quick',
          ),
          onPressed: enabled
              ? () => showLibraryUpdateReview(
                  context,
                  controller,
                  completeCheck: complete,
                )
              : null,
          icon: Icon(
            complete ? Icons.fact_check_outlined : Icons.bolt_outlined,
            size: 20,
          ),
          label: Text(
            copy.localized(
              complete ? '完整性检查' : '快速检查',
              complete ? 'Full check' : 'Quick check',
            ),
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          action(false),
          const SizedBox(height: 8),
          action(true),
          if (checking || updating) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    copy.localized(
                      updating ? '正在更新资料' : '正在检查资料',
                      updating ? 'Updating resources' : 'Checking resources',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );
}
