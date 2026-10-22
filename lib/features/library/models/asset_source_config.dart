import 'dart:convert';

import '../services/board_game_remote_layout.dart';

class AssetSourceConfig {
  const AssetSourceConfig({
    required this.id,
    required this.name,
    required this.address,
    required this.testUrl,
  });

  final String id;
  final String name;
  final String address;
  final String testUrl;

  AssetSourceConfig copyWith({
    String? id,
    String? name,
    String? address,
    String? testUrl,
  }) {
    return AssetSourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      testUrl: testUrl ?? this.testUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'address': address,
      'testUrl': testUrl,
    };
  }

  static AssetSourceConfig fromMap(Map<String, dynamic> map) {
    return normalize(
      AssetSourceConfig(
        id: map['id'] as String,
        name: map['name'] as String,
        address: map['address'] as String,
        testUrl: map['testUrl'] as String,
      ),
    );
  }

  static AssetSourceConfig normalize(AssetSourceConfig source) {
    final uri = Uri.tryParse(source.testUrl.trim());
    final normalizedUri = uri == null || !uri.hasScheme || !uri.hasAuthority
        ? null
        : BoardGameRemoteLayout.normalizeBaseUri(uri);
    final normalizedAddress = source.address.replaceFirst(
      RegExp(r'[\\/]board-game-lib[\\/]?$'),
      '',
    );
    final legacyDefault =
        ['cznas_dev', 'configured_webdav'].contains(source.id) &&
        normalizedUri?.host == 'cznas.dev' &&
        normalizedUri?.port == 5006 &&
        normalizedUri?.path == '/friend/';
    return source.copyWith(
      name: legacyDefault && source.name == 'cznas.dev' ? '外网访问' : source.name,
      address: legacyDefault
          ? BoardGameRemoteLayout.defaultBaseUrl
          : normalizedAddress,
      testUrl: legacyDefault
          ? BoardGameRemoteLayout.defaultBaseUrl
          : normalizedUri?.toString() ?? source.testUrl,
    );
  }

  static const List<AssetSourceConfig> defaults = <AssetSourceConfig>[
    AssetSourceConfig(
      id: 'lan_share',
      name: '内网访问',
      address: r'\\192.168.1.55\friend',
      testUrl: 'https://192.168.1.55:5006/friend/',
    ),
    AssetSourceConfig(
      id: 'cznas_dev',
      name: '外网访问',
      address: BoardGameRemoteLayout.defaultBaseUrl,
      testUrl: BoardGameRemoteLayout.defaultBaseUrl,
    ),
  ];

  static String encodeList(List<AssetSourceConfig> items) {
    return jsonEncode(items.map((item) => item.toMap()).toList());
  }

  static List<AssetSourceConfig> decodeList(String? source) {
    if (source == null || source.trim().isEmpty) {
      return defaults;
    }

    try {
      final json = jsonDecode(source) as List<dynamic>;
      final items = json
          .map(
            (item) => AssetSourceConfig.fromMap(item as Map<String, dynamic>),
          )
          .toList();
      return items.isEmpty ? defaults : items;
    } catch (_) {
      return defaults;
    }
  }
}
