import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:crypto/crypto.dart';

/// Public DSM connection only. No bridge address, user password or API secret.
final class AccountConfiguration {
  AccountConfiguration({required this.nasOrigin}) {
    try {
      SynologyIdentityGateway.validateOrigin(nasOrigin);
    } catch (_) {
      throw const FormatException('需要不含账号和路径的群晖 HTTPS 地址');
    }
  }
  static AccountConfiguration get defaults => AccountConfiguration.fromFields(
    nasUrl: const String.fromEnvironment(
      'SYNOLOGY_ORIGIN',
      defaultValue: 'https://cznas.dpdns.org:5001',
    ),
  );
  factory AccountConfiguration.fromFields({required String nasUrl}) =>
      AccountConfiguration(nasOrigin: Uri.parse(nasUrl.trim()));
  factory AccountConfiguration.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 3 || json['authType'] != 'synology-direct') {
      throw const FormatException('账号配置版本不匹配');
    }
    return AccountConfiguration.fromFields(nasUrl: json['nasUrl'] as String);
  }
  final Uri nasOrigin;
  String get environmentId => sha256
      .convert(utf8.encode('synology-direct-v1|${nasOrigin.origin}'))
      .toString();
  String accountScope(String userId) =>
      sha256.convert(utf8.encode('$environmentId|$userId')).toString();
  Map<String, dynamic> toJson() => {
    'version': 3,
    'authType': 'synology-direct',
    'nasUrl': nasOrigin.origin,
  };
}
