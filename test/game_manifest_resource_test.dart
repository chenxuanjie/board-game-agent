import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/features/games/models/game_catalog_manifest.dart';
import 'package:board_game_agent/features/library/models/published_catalog.dart';
import 'support/catalog_fixture.dart';

void main() {
  Map<String, dynamic> definition() => catalogEditionFixture(
    {
      'id': 'cabo',
      'slug': 'cabo',
      'score': '8.2',
      'supportedPlayers': [2, 3, 4],
      'recommendedPlayer': 3,
      'editionLabel': {'zhHans': '第二版'},
      'aliases': {
        'zhHans': ['卡波别名'],
      },
      'coverAsset': 'images/cover.jpg',
      'locales': {
        'zhHans': {
          'title': '卡波',
          'summary': '规则简介',
          'playTime': '45 分钟',
          'quickPrompts': ['如何开始？'],
        },
        'en': {'title': 'Cabo', 'summary': 'Rules summary'},
      },
    },
    resourceManifest: {
      'resources': [
        resource('cover', 'images/cover.jpg', type: 'cover', ai: false),
        resource(
          'official',
          'docs/official/rules/rules_en.pdf',
          language: 'en',
          ai: false,
          source: 'official',
        ),
        resource('cn', 'docs/local/knowledge/rules_cn.md', language: 'cn'),
        resource('en', 'docs/local/knowledge/rules_en.md', language: 'en'),
      ],
    },
  );
  test(
    'SQL editions preserve localized metadata, image bindings and AI permission',
    () {
      final model = GameManifest.fromCatalog(definition());
      final cn = model.toGameInfo(AppLanguage.zhHans),
          en = model.toGameInfo(AppLanguage.en);
      expect(cn.title, '卡波');
      expect(cn.summary, '规则简介');
      expect(cn.playTime, '45 分钟');
      expect(cn.aliases, ['卡波别名']);
      expect(cn.editionLabel, '第二版');
      expect(
        cn.rulebookAssetPath,
        'assets/games/cabo/docs/official/rules/rules_en.pdf',
      );
      expect(cn.knowledgeAssetPaths, [
        'assets/games/cabo/docs/local/knowledge/rules_cn.md',
      ]);
      expect(en.knowledgeAssetPaths, [
        'assets/games/cabo/docs/local/knowledge/rules_en.md',
      ]);
      expect(cn.coverAssetPath, 'assets/games/cabo/images/cover.jpg');
      expect(cn.resources.every((r) => r.sha256?.length == 64), isTrue);
    },
  );
  test('SQL input cannot invent bindings from a legacy documents field', () {
    final value = definition()..['bindings'] = [];
    value['documents'] = {
      'faq': {'zhHans': 'docs/absent.md'},
    };
    expect(
      GameManifest.fromCatalog(
        value,
      ).toGameInfo(AppLanguage.zhHans).faqAssetPath,
      isEmpty,
    );
  });
  test(
    'invalid, archived and off-origin resource data cannot become a snapshot',
    () {
      for (final edit in <void Function(Map<String, dynamic>)>[
        (r) => r['visibility'] = 'archive',
        (r) => r['enabled'] = false,
        (r) => r['content_url'] = 'https://untrusted.invalid/content',
        (r) => r['file_sha256'] = 'bad',
        (r) => r['path'] = 'docs/others/private.md',
      ]) {
        final value = definition();
        edit((value['resources'] as List).first as Map<String, dynamic>);
        expect(
          () => PublishedCatalog.fromJson({
            'protocol': 1,
            'revision': 1,
            'editions': [value],
          }),
          throwsFormatException,
        );
      }
    },
  );
}

Map<String, dynamic> resource(
  String id,
  String path, {
  String type = 'rulebook',
  String language = 'none',
  bool ai = true,
  String source = 'official_extracted',
}) => {
  'id': id,
  'path': path,
  'documentType': type,
  'language': language,
  'sourceClass': source,
  'enabled': true,
  'status': 'available',
  'aiEnabled': ai,
};
