import 'package:board_game_agent/features/games/services/national_day_list_controller.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'tied votes retain ranking until a strictly higher count crosses it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService();
      final list = NationalDayListController(
        preferences: preferences,
        defaultSlugs: () => ['a', 'b', 'c'],
      );
      addTearDown(list.dispose);
      await list.load();
      final votes = <String, int>{};
      List<String> ranked() => list.rankByVotes((slug) => votes[slug] ?? 0);
      expect(ranked(), ['a', 'b', 'c']);
      votes['c'] = 1;
      expect(ranked(), ['c', 'a', 'b']);
      votes['c'] = 0;
      expect(ranked(), ['c', 'a', 'b']);
      votes['b'] = 1;
      expect(ranked(), ['b', 'c', 'a']);
      votes['c'] = 1;
      expect(ranked(), ['b', 'c', 'a']);
      votes['c'] = 2;
      expect(ranked(), ['c', 'b', 'a']);
      votes['c'] = 1;
      expect(ranked(), ['c', 'b', 'a']);
      expect(list.slugs, ['a', 'b', 'c']);

      await list.save(['a', 'b']);
      votes.clear();
      await list.save(['a', 'b', 'c']);
      expect(ranked(), ['b', 'a', 'c']);
      expect(await preferences.loadNationalDayGameSlugs(), ['a', 'b', 'c']);

      // A new workspace starts with its own list, never another workspace's rank.
      final other = NationalDayListController(
        preferences: preferences,
        defaultSlugs: () => [],
      );
      addTearDown(other.dispose);
      await other.load();
      expect(other.rankByVotes((_) => 0), ['a', 'b', 'c']);
    },
  );
}
