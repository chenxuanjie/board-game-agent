/// First-install credentials supplied by a private release defaults file.
/// Saved, editable secure settings take precedence; never commit seed values.
class BoardGameRemoteCredentials {
  const BoardGameRemoteCredentials._();

  // Release seeds come from a private file outside the repository. Once saved,
  // the editable secure WebDAV settings always take precedence.
  static const String username = String.fromEnvironment(
    'BOARD_GAME_WEBDAV_USERNAME',
  );
  static const String password = String.fromEnvironment(
    'BOARD_GAME_WEBDAV_PASSWORD',
  );
}
