/// Default credentials for the configured board-game WebDAV library.
///
/// Resource endpoints themselves remain user-configurable through
/// [AssetSourceConfig] and SharedPreferences. These constants only replace
/// the old bundled storage-endpoints asset for the existing authentication
/// fallback.
class BoardGameRemoteCredentials {
  const BoardGameRemoteCredentials._();

  static const String username = 'Shane';
  static const String password = '1';
}
