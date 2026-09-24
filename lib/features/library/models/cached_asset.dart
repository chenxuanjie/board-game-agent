class CachedAsset {
  const CachedAsset({
    required this.remotePath,
    required this.localPath,
    required this.exists,
    required this.fromRemote,
    this.sourceId,
  });

  final String remotePath;
  final String localPath;
  final bool exists;
  final bool fromRemote;
  final String? sourceId;
}
