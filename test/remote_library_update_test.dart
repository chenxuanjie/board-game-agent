import 'package:board_game_agent/models/remote_library_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups changed paths by resource type', () {
    const RemoteLibraryUpdate update = RemoteLibraryUpdate(
      changedPaths: <String>[
        'assets/catalog.json',
        'assets/games/cabo/images/cover.jpg',
        'assets/games/cabo/images/banner.jpg',
        'assets/games/cabo/docs/rulebook_official_zh.pdf',
        'assets/games/cabo/docs/faq_zh.md',
        'assets/games/cabo/game.json',
      ],
      changedGameTitles: <String>['Cabo'],
    );

    expect(update.changedCount, 6);
    expect(update.changedResourceCounts, <RemoteLibraryResourceType, int>{
      RemoteLibraryResourceType.catalog: 1,
      RemoteLibraryResourceType.image: 2,
      RemoteLibraryResourceType.rulebook: 1,
      RemoteLibraryResourceType.faq: 1,
      RemoteLibraryResourceType.gameManifest: 1,
    });
  });
}
