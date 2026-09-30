/// Consistent, compact display of the catalog's localized player and time data.
/// It never estimates a new value: both ends of a recorded range stay visible.
class GameMetadataText {
  const GameMetadataText._();

  static String players(String value) {
    final normalized = _range(value.trim());
    if (normalized.isEmpty || normalized == '-' || normalized == '—') {
      return '—';
    }
    return normalized.replaceAll('(plus 2-player variant)', '(+2 variant)');
  }

  /// A narrow card shows the primary player range; details remain available
  /// from the full value in its tooltip and game detail page.
  static String cardPlayers(String value) => players(value)
      .replaceFirst(RegExp(r'\s*（[^）]*）'), '')
      .replaceFirst(RegExp(r'\s*\([^)]*\)'), '')
      .replaceFirst(RegExp(r'\s*/.*$'), '')
      .replaceFirst(RegExp(r'\s+players?$', caseSensitive: false), '');

  static String playTime(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty || normalized == '-' || normalized == '—') {
      return '—';
    }
    normalized = normalized.replaceFirst(RegExp(r'^约\s*'), '');
    normalized = normalized.replaceFirst(
      RegExp(r'^about\s+', caseSensitive: false),
      '',
    );
    normalized = _range(normalized);
    normalized = normalized.replaceAll(RegExp(r'\s*/\s*'), '/');
    normalized = normalized.replaceAll('/每幕', '/幕');
    normalized = normalized.replaceAll(
      RegExp(r'\bminutes?\b', caseSensitive: false),
      'min',
    );
    return normalized;
  }

  /// The clock icon supplies the minute unit on compact recommendation cards.
  static String cardPlayTime(String value) => playTime(value)
      .replaceFirst(RegExp(r'\s*分钟'), '')
      .replaceFirst(RegExp(r'\s*\bmin\b', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+per\s+Act$', caseSensitive: false), '/Act');

  static String _range(String value) => value.replaceAllMapped(
    RegExp(r'(\d)\s*[-–—]\s*(\d)'),
    (match) => '${match[1]}–${match[2]}',
  );
}
