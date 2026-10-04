import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Public connection metadata. Never accepts NAS passwords or admin keys.
final class AccountConfiguration {
  AccountConfiguration({
    required this.supabaseUrl,
    required this.publishableKey,
    this.providerId = 'custom:synology',
    required this.webCallback,
  }) {
    _validateHttps(supabaseUrl, 'Supabase 地址');
    _validateHttps(webCallback, 'Web 回调地址');
    if (supabaseUrl.path != '' && supabaseUrl.path != '/') {
      throw const FormatException('Supabase 地址应为项目根地址');
    }
    if (!RegExp(r'^custom:[a-z0-9][a-z0-9:-]{0,42}$').hasMatch(providerId)) {
      throw const FormatException('登录提供方应为 custom: 开头的标识');
    }
    _validatePublicKey(publishableKey);
  }

  factory AccountConfiguration.fromFields({
    required String supabaseUrl,
    required String publishableKey,
    String providerId = 'custom:synology',
    required String webCallback,
  }) => AccountConfiguration(
    supabaseUrl: Uri.parse(supabaseUrl.trim()),
    publishableKey: publishableKey.trim(),
    providerId: providerId.trim(),
    webCallback: Uri.parse(webCallback.trim()),
  );

  factory AccountConfiguration.fromJson(Map<String, dynamic> json) =>
      AccountConfiguration.fromFields(
        supabaseUrl: json['supabaseUrl'] as String,
        publishableKey: json['publishableKey'] as String,
        providerId: json['providerId'] as String? ?? 'custom:synology',
        webCallback: json['webCallback'] as String,
      );

  final Uri supabaseUrl;
  final String publishableKey;
  final String providerId;
  final Uri webCallback;
  static final Uri callback = Uri.parse(
    'org.dpdns.cznas.boardgame://auth/callback',
  );
  Uri get nativeCallback => callback;
  String get environmentId => sha256
      .convert(utf8.encode('${supabaseUrl.origin}|$providerId'))
      .toString();
  String accountScope(String userId) =>
      sha256.convert(utf8.encode('$environmentId|$userId')).toString();

  Map<String, dynamic> toJson() => {
    'version': 1,
    'supabaseUrl': supabaseUrl.toString(),
    'publishableKey': publishableKey,
    'providerId': providerId,
    'webCallback': webCallback.toString(),
  };

  static void _validateHttps(Uri uri, String label) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException('$label需要不含账号、查询参数的 HTTPS 地址');
    }
  }

  static void _validatePublicKey(String value) {
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]{16,}$').hasMatch(value)) {
      return;
    }
    try {
      final parts = value.split('.');
      if (parts.length == 3) {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (claims is Map && claims['role'] == 'anon') return;
      }
    } catch (_) {
      // Reject rather than exposing the supplied key in an exception.
    }
    throw const FormatException('请填写 publishable 或 anon 公钥，不接受管理密钥');
  }
}
