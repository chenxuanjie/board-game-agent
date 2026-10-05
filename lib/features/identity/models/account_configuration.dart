import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:crypto/crypto.dart';
import '../../library/models/asset_source_config.dart';

/// One NAS, several trusted network entrances. Credentials never belong here.
final class NasServerAddress {
  NasServerAddress({
    required this.id,
    required this.name,
    required String address,
    this.loginPort = 5001,
    this.webDavPort = 5006,
  }) : address = normalizeAddress(address) {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        loginPort < 1 ||
        loginPort > 65535 ||
        webDavPort < 1 ||
        webDavPort > 65535) {
      throw const FormatException('地址名称和端口无效');
    }
  }
  final String id, name, address;
  final int loginPort, webDavPort;
  static String normalizeAddress(String value) {
    final uri = Uri.tryParse(
      value.trim().contains('://') ? value.trim() : 'https://${value.trim()}',
    );
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path) ||
        uri.hasPort) {
      throw const FormatException('请输入不含端口和目录的 HTTPS 地址');
    }
    return Uri(scheme: 'https', host: uri.host).origin;
  }

  Uri get loginOrigin => Uri.parse(address).replace(port: loginPort);
  Uri webDavRoot(String folder) => Uri.parse(address).replace(
    port: webDavPort,
    path: '/${AccountConfiguration.normalizeFolder(folder)}/',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'loginPort': loginPort,
    'webDavPort': webDavPort,
  };
  factory NasServerAddress.fromJson(Map<String, dynamic> value) =>
      NasServerAddress(
        id: value['id'] as String,
        name: value['name'] as String,
        address: value['address'] as String,
        loginPort: value['loginPort'] as int,
        webDavPort: value['webDavPort'] as int,
      );
}

final class AccountConfiguration {
  AccountConfiguration({
    required Uri nasOrigin,
    List<NasServerAddress>? servers,
    String storageFolder = 'friend',
    Uri? identityOrigin,
    this.activeServerId,
  }) : servers = List.unmodifiable(
         servers ??
             [
               NasServerAddress(
                 id: 'nas',
                 name: '群晖',
                 address: Uri(scheme: 'https', host: nasOrigin.host).origin,
                 loginPort: nasOrigin.port,
               ),
             ],
       ),
       identityOrigin = identityOrigin ?? nasOrigin,
       storageFolder = normalizeFolder(storageFolder) {
    SynologyIdentityGateway.validateOrigin(this.identityOrigin);
    if (this.servers.isEmpty ||
        this.servers.length > 8 ||
        this.servers.map((s) => s.id).toSet().length != this.servers.length ||
        this.servers.map((s) => s.loginOrigin.origin).toSet().length !=
            this.servers.length) {
      throw const FormatException('请配置不同的服务器地址');
    }
    SynologyIdentityGateway.validateOrigin(nasOrigin);
  }
  final List<NasServerAddress> servers;
  final String storageFolder;

  /// Stable environment across aliases and reordering, preserving v3 accounts.
  final Uri identityOrigin;
  final String? activeServerId;
  NasServerAddress get activeServer => servers.firstWhere(
    (s) => s.id == activeServerId,
    orElse: () => servers.first,
  );
  Uri get nasOrigin => activeServer.loginOrigin;
  static String normalizeFolder(String input) {
    final value = input
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    if (value.isEmpty ||
        value.length > 240 ||
        value
            .split('/')
            .any(
              (s) =>
                  s.isEmpty ||
                  s == '.' ||
                  s == '..' ||
                  !RegExp(r'^[\p{L}\p{N} _.-]+$', unicode: true).hasMatch(s),
            )) {
      throw const FormatException('请输入有效的存储目录，例如 friend');
    }
    return value;
  }

  static AccountConfiguration get defaults => AccountConfiguration.fromFields(
    nasUrl: const String.fromEnvironment(
      'SYNOLOGY_ORIGIN',
      defaultValue: 'https://cznas.dpdns.org:5001',
    ),
  );
  factory AccountConfiguration.fromFields({required String nasUrl}) {
    try {
      return AccountConfiguration(nasOrigin: Uri.parse(nasUrl.trim()));
    } catch (_) {
      throw const FormatException('需要不含账号和路径的群晖 HTTPS 地址');
    }
  }
  factory AccountConfiguration.fromResources({
    required List<AssetSourceConfig> sources,
    AccountConfiguration? previous,
  }) {
    final addresses = <NasServerAddress>[];
    String folder = 'friend';
    for (final source in sources) {
      final uri = Uri.tryParse(source.testUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        continue;
      }
      if (addresses.any(
        (s) =>
            s.address == Uri(scheme: 'https', host: uri.host).origin &&
            s.webDavPort == uri.port,
      )) {
        continue;
      }
      if (addresses.isEmpty &&
          uri.pathSegments.where((s) => s.isNotEmpty).isNotEmpty) {
        folder = normalizeFolder(
          uri.pathSegments.where((s) => s.isNotEmpty).join('/'),
        );
      }
      final known = previous?.servers
          .where(
            (s) => s.address == Uri(scheme: 'https', host: uri.host).origin,
          )
          .firstOrNull;
      addresses.add(
        NasServerAddress(
          id: source.id,
          name: source.name,
          address: Uri(scheme: 'https', host: uri.host).origin,
          loginPort:
              known?.loginPort ??
              (previous?.nasOrigin.host == uri.host
                  ? previous!.nasOrigin.port
                  : 5001),
          webDavPort: uri.port,
        ),
      );
    }
    if (addresses.isEmpty) return previous ?? defaults;
    final canonical = previous?.identityOrigin ?? defaults.identityOrigin;
    final active = addresses
        .where((s) => s.loginOrigin == canonical)
        .firstOrNull;
    return AccountConfiguration(
      nasOrigin: addresses.first.loginOrigin,
      servers: addresses,
      storageFolder: folder,
      identityOrigin: canonical,
      activeServerId: active?.id,
    );
  }
  AccountConfiguration withServer(String id) => AccountConfiguration(
    nasOrigin: nasOrigin,
    servers: servers,
    storageFolder: storageFolder,
    identityOrigin: identityOrigin,
    activeServerId: id,
  );
  AccountConfiguration edited({
    required List<NasServerAddress> servers,
    required String folder,
  }) {
    final sameEntrances =
        servers.length == this.servers.length &&
        servers.every(
          (s) => this.servers.any(
            (old) => old.id == s.id && old.loginOrigin == s.loginOrigin,
          ),
        );
    return AccountConfiguration(
      nasOrigin: servers.first.loginOrigin,
      servers: servers,
      storageFolder: folder,
      identityOrigin: sameEntrances
          ? identityOrigin
          : servers.first.loginOrigin,
      activeServerId: sameEntrances ? activeServerId : null,
    );
  }

  factory AccountConfiguration.fromJson(Map<String, dynamic> json) {
    if (json['authType'] != 'synology-direct') {
      throw const FormatException('账号配置版本不匹配');
    }
    if (json['version'] == 3) {
      return AccountConfiguration.fromFields(nasUrl: json['nasUrl'] as String);
    }
    if (json['version'] != 4) throw const FormatException('账号配置版本不匹配');
    final servers = (json['servers'] as List)
        .map(
          (s) => NasServerAddress.fromJson(Map<String, dynamic>.from(s as Map)),
        )
        .toList();
    return AccountConfiguration(
      nasOrigin: Uri.parse(json['nasUrl'] as String),
      servers: servers,
      storageFolder: json['storageFolder'] as String,
      identityOrigin: Uri.parse(json['identityOrigin'] as String),
      activeServerId: json['activeServerId'] as String?,
    );
  }
  String get environmentId => sha256
      .convert(utf8.encode('synology-direct-v1|${identityOrigin.origin}'))
      .toString();
  String accountScope(String userId) =>
      sha256.convert(utf8.encode('$environmentId|$userId')).toString();
  List<AssetSourceConfig> get resourceSources => servers
      .map(
        (s) => AssetSourceConfig(
          id: s.id,
          name: s.name,
          address: s.webDavRoot(storageFolder).toString(),
          testUrl: s.webDavRoot(storageFolder).toString(),
        ),
      )
      .toList();
  Map<String, dynamic> toJson() => {
    'version': 4,
    'authType': 'synology-direct',
    'nasUrl': nasOrigin.origin,
    'identityOrigin': identityOrigin.origin,
    'servers': servers.map((s) => s.toJson()).toList(),
    'storageFolder': storageFolder,
    'activeServerId': activeServerId,
  };
}
