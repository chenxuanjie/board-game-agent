import '../../features/games/models/game_info.dart';

/// Account-local presentation state, kept only for this application run.
/// Resource/cache and account synchronization never serialize this object.
class BrowseSession {
  String destination = 'home';
  String detailReturn = 'games';
  LibraryBrowseState library = LibraryBrowseState();
  final Map<String, double> pageOffsets = {};

  void reset() {
    destination = 'home';
    detailReturn = 'games';
    library = LibraryBrowseState();
    pageOffsets.clear();
  }
}

class LibraryBrowseState {
  String query = '';
  int category = 0;
  String sort = 'catalog';
  String? player, duration, weight;
  double? minScore;
  final Set<String> types = {};
  final Set<String> revealed = {};
  String? anchorId;
  int anchorIndex = 0;
  double anchorDelta = 0;
  double offset = 0;
  int positionRevision = 0;

  bool get hasFilters =>
      player != null ||
      duration != null ||
      weight != null ||
      minScore != null ||
      types.isNotEmpty;

  void resetPosition() {
    positionRevision++;
    anchorId = null;
    anchorIndex = 0;
    anchorDelta = offset = 0;
  }

  void clearFilters() {
    player = duration = weight = null;
    minScore = null;
    types.clear();
    sort = 'catalog';
    resetPosition();
  }

  void reset() {
    query = '';
    category = 0;
    clearFilters();
    revealed.clear();
  }

  List<GameInfo> filter(List<GameInfo> source) {
    const categories = [
      'all',
      'strategy',
      'family',
      'party',
      'cooperative',
      'two_player',
    ];
    final needle = query.trim().toLowerCase();
    final result = source.where((game) {
      if (category > 0 &&
          category < categories.length &&
          !(category == 5
              ? game.supportedPlayers.contains(2)
              : game.browseCategories.contains(categories[category]))) {
        return false;
      }
      final text =
          '${game.title} ${game.subtitle} ${game.categoryLine} '
          '${game.aliases.join(' ')} ${game.designers.join(' ')} ${game.keywords.join(' ')}';
      if (needle.isNotEmpty && !text.toLowerCase().contains(needle)) {
        return false;
      }
      if (player != null &&
          !(player == '5+'
              ? game.supportedPlayers.any((p) => p >= 5)
              : game.supportedPlayers.contains(int.tryParse(player!)))) {
        return false;
      }
      if (types.isNotEmpty && !types.any(text.contains)) return false;
      if (minScore != null && (double.tryParse(game.score) ?? -1) < minScore!) {
        return false;
      }
      if (weight != null) {
        final value = '${game.complexity} ${game.learningDifficulty}';
        if (!(switch (weight) {
          '入门' => value.contains('入门') || value.contains('简单'),
          '轻度' => value.contains('轻'),
          '重度' => value.contains('重') || value.contains('困难'),
          _ => value.contains('中'),
        })) {
          return false;
        }
      }
      if (duration != null) {
        final values =
            RegExp(r'\d+')
                .allMatches('${game.playTime} ${game.perPlayerTime}')
                .map((m) => int.parse(m.group(0)!))
                .toList()
              ..sort();
        if (values.isEmpty ||
            !(switch (duration) {
              '<30' => values.first < 30,
              '30-60' => values.last >= 30 && values.first <= 60,
              '60-120' => values.last >= 60 && values.first <= 120,
              '>120' => values.last > 120,
              _ => true,
            })) {
          return false;
        }
      }
      return true;
    }).toList();
    if (sort == 'name') result.sort((a, b) => a.title.compareTo(b.title));
    if (sort == 'score') {
      result.sort(
        (a, b) => (double.tryParse(b.score) ?? -1).compareTo(
          double.tryParse(a.score) ?? -1,
        ),
      );
    }
    return result;
  }
}
