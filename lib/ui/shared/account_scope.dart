import 'package:flutter/widgets.dart';

import '../../features/identity/services/account_service.dart';

class AccountScope extends InheritedNotifier<AccountService> {
  const AccountScope({
    super.key,
    required AccountService service,
    required super.child,
  }) : super(notifier: service);

  static AccountService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()?.notifier;

  static AccountService of(BuildContext context) {
    final service = maybeOf(context);
    if (service == null) throw StateError('AccountScope is missing');
    return service;
  }
}
