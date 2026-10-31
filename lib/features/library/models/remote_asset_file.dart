/// A resource selected from a published SQL catalog snapshot.
class RemoteAssetFile {
  const RemoteAssetFile({
    required this.remotePath,
    required this.name,
    required this.sourceId,
    this.etag,
  });

  final String remotePath;
  final String name;
  final String sourceId;
  final String? etag;
}
