import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/models/recent_game_record.dart';
import 'package:board_game_agent/models/search_history_record.dart';
import 'package:board_game_agent/services/preferences_service.dart';

void main() {
  test('recent searches are normalized, deduplicated, and capped', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'recent_searches_v1': <String>[
        ' 卡坦岛 ',
        '阿瓦隆',
        '卡坦岛',
        '',
        '璀璨宝石',
        '花砖物语',
        '波多黎各',
        '卡卡颂',
        '卡坦岛扩展',
        '诡镇奇谈',
      ],
    });

    final service = PreferencesService();
    expect(await service.loadRecentSearches(), <String>[
      '卡坦岛',
      '阿瓦隆',
      '璀璨宝石',
      '花砖物语',
      '波多黎各',
      '卡卡颂',
      '卡坦岛扩展',
      '诡镇奇谈',
    ]);

    await service.saveRecentSearches(<String>[' 新搜索 ', '新搜索', '']);
    expect(await service.loadRecentSearches(), <String>['新搜索']);
  });

  test('recent history records round trip as versioned JSON', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = PreferencesService();
    final searchedAt = DateTime.utc(2026, 9, 15, 8);
    final viewedAt = DateTime.utc(2026, 9, 15, 9);

    await service.saveSearchHistory(<SearchHistoryRecord>[
      SearchHistoryRecord(query: 'Catan', searchedAt: searchedAt),
    ]);
    await service.saveRecentGames(<RecentGameRecord>[
      RecentGameRecord(gameSlug: 'catan', viewedAt: viewedAt),
    ]);

    expect(
      (await service.loadSearchHistory()).single.toMap(),
      <String, dynamic>{
        'query': 'Catan',
        'searchedAt': searchedAt.toIso8601String(),
      },
    );
    expect((await service.loadRecentGames()).single.toMap(), <String, dynamic>{
      'gameSlug': 'catan',
      'viewedAt': viewedAt.toIso8601String(),
    });
  });
}
