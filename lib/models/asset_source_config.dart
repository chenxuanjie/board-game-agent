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
    return source.copyWith(
      address: normalizedAddress,
      testUrl: normalizedUri?.toString() ?? source.testUrl,
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
      name: 'cznas.dev',
      address: r'\\cznas.dev\friend',
      testUrl: 'https://cznas.dev:5006/friend/',
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
