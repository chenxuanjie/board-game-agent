import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:crypto/crypto.dart';

/// Application API selection, independent of NAS resource connections.
final class ServiceConfiguration {
  ServiceConfiguration(Uri origin)
    : origin = AppJsonClient.parseOrigin('$origin');
  final Uri origin;
  static const applicationId = 'board_game_agent';
  static const defaultUpdateOrigin = String.fromEnvironment(
    'APP_SERVICE_ORIGIN',
    defaultValue: 'https://cznas.pp.ua:18281',
  );
  String get environmentId => sha256
      .convert(utf8.encode('app-service-v1|$applicationId|${origin.origin}'))
      .toString();
  String accountScope(String userId) =>
      sha256.convert(utf8.encode('$environmentId|$userId')).toString();
}
