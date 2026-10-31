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

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'address': address,
    'testUrl': testUrl,
  };
}
