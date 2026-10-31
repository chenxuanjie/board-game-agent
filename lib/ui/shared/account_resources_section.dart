import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../features/identity/services/account_service.dart';
import 'resource_access_summary.dart';

/// Public resources use the selected application service for guests and members.
class AccountResourcesSection extends StatelessWidget {
  const AccountResourcesSection({
    super.key,
    required this.service,
    this.expanded = false,
  });
  final AccountService service;
  final bool expanded;
  @override
  Widget build(BuildContext context) => ResourceAccessSummary(
    controller: service.controller,
    onRefresh: service.controller.refreshAssetAccessStatus,
    refreshing: false,
    refreshEnabled: service.isConfigured,
  );
}
