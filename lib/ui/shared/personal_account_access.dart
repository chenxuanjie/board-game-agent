import 'package:flutter/material.dart';
import 'account_scope.dart';
import 'account_screen.dart';

bool requirePersonalAccount(BuildContext context) {
  final account = AccountScope.maybeOf(context);
  if (account == null || account.isSignedIn && account.dataScopeReady) {
    return true;
  }
  Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const AccountScreen()));
  return false;
}
