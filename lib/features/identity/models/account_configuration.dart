import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Public application service metadata. No NAS credentials or OIDC settings.
final class AccountConfiguration {
  AccountConfiguration({required this.serviceUrl, required this.nasId}) {
    validateOrigin(serviceUrl);
    if (!RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(nasId)) {
      throw const FormatException('登录服务标识无效');
    }
  }
  factory AccountConfiguration.fromFields({
    required String serviceUrl,
    required String nasId,
  }) => AccountConfiguration(
    serviceUrl: Uri.parse(serviceUrl.trim()),
    nasId: nasId,
  );
  factory AccountConfiguration.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2 || json['authType'] != 'synology-api-auth') {
      throw const FormatException('登录服务协议不匹配');
    }
    return AccountConfiguration.fromFields(
      serviceUrl: json['serviceUrl'] as String,
      nasId: json['nasId'] as String,
    );
  }
  final Uri serviceUrl;
  final String nasId;
  String get environmentId => sha256
      .convert(utf8.encode('synology-auth-v1|${serviceUrl.origin}|$nasId'))
      .toString();
  String accountScope(String userId) =>
      sha256.convert(utf8.encode('$environmentId|$userId')).toString();
  Map<String, dynamic> toJson() => {
    'version': 2,
    'authType': 'synology-api-auth',
    'serviceUrl': serviceUrl.origin,
    'nasId': nasId,
  };
  static void validateOrigin(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path)) {
      throw const FormatException('需要不含账号和路径的 HTTPS 登录服务地址');
    }
  }
}
