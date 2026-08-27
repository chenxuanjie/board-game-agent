import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/game_catalog_manifest.dart';
import 'package:board_game_agent/models/game_resource.dart';

void main() {
  test('companion manifest prefers the official PDF for the rulebook', () {
    final GameManifest game = GameManifest.fromJson(
      <String, dynamic>{
        'id': 'cabo',
        'slug': 'cabo',
        'coverAsset': 'images/cover.jpg',
        'bannerAsset': 'images/background.jpg',
        'locales': <String, dynamic>{
          'zhHans': <String, dynamic>{'title': '卡波'},
          'en': <String, dynamic>{'title': 'Cabo'},
        },
      },
      resourceManifest: GameResourceManifest.fromJson(<String, dynamic>{
        'schemaVersion': 3,
        'game': <String, dynamic>{
          'id': 'cabo',
          'slug': 'cabo',
          'edition': 'second_edition_2019',
        },
        'resources': <Map<String, dynamic>>[
          _resource(
            id: 'official-rulebook',
            path: 'docs/official/rules/rulebook_en.pdf',
            documentType: 'rulebook',
            language: 'en',
            aiEnabled: false,
            priority: 10,
          ),
          _resource(
            id: 'english-knowledge',
            path: 'docs/local/knowledge/rulebook_en.md',
            documentType: 'rulebook',
            sourceClass: 'official_extracted',
            language: 'en',
            priority: 20,
          ),
          _resource(
            id: 'chinese-knowledge',
            path: 'docs/local/knowledge/rulebook_cn.md',
            documentType: 'rulebook',
            sourceClass: 'local_translated',
            language: 'cn',
            priority: 30,
          ),
          _resource(
            id: 'chinese-ruling',
            path: 'docs/community/answers/ruling_cn.md',
            documentType: 'ruling',
            sourceClass: 'community',
            language: 'cn',
            priority: 60,
          ),
          _resource(
            id: 'missing-knowledge',
            path: 'docs/local/knowledge/missing_cn.md',
            documentType: 'faq',
            language: 'cn',
            status: 'missing',
            priority: 1,
          ),
        ],
      }),
    );

    final infoCn = game.toGameInfo(AppLanguage.zhHans);
    expect(
      infoCn.rulebookAssetPath,
      'assets/games/cabo/docs/official/rules/rulebook_en.pdf',
    );
    expect(infoCn.knowledgeAssetPaths, <String>[
      'assets/games/cabo/docs/local/knowledge/rulebook_cn.md',
      'assets/games/cabo/docs/community/answers/ruling_cn.md',
    ]);
    expect(infoCn.resources.length, 5);

    final infoEn = game.toGameInfo(AppLanguage.en);
    expect(
      infoEn.rulebookAssetPath,
      'assets/games/cabo/docs/official/rules/rulebook_en.pdf',
    );
    expect(infoEn.knowledgeAssetPaths, <String>[
      'assets/games/cabo/docs/local/knowledge/rulebook_en.md',
    ]);
  });

  test('legacy game.json documents remain a compatibility fallback', () {
    final GameManifest game = GameManifest.fromJson(<String, dynamic>{
      'id': 'legacy',
      'slug': 'legacy',
      'documents': <String, dynamic>{
        'rulebook': <String, dynamic>{'zhHans': 'docs/rulebook_cn.md'},
        'faq': <String, dynamic>{'zhHans': 'docs/faq_cn.md'},
        'knowledge': <String, dynamic>{
          'zhHans': <String>['docs/rulebook_cn.md', 'docs/faq_cn.md'],
        },
      },
      'locales': <String, dynamic>{
        'zhHans': <String, dynamic>{'title': 'Legacy'},
      },
    });

    final info = game.toGameInfo(AppLanguage.zhHans);
    expect(info.rulebookAssetPath, 'assets/games/legacy/docs/rulebook_cn.md');
    expect(info.faqAssetPath, 'assets/games/legacy/docs/faq_cn.md');
    expect(info.knowledgeAssetPaths, <String>[
      'assets/games/legacy/docs/rulebook_cn.md',
      'assets/games/legacy/docs/faq_cn.md',
    ]);
  });

  test('all bundled game pairs parse through the runtime models', () {
    final Directory gamesDirectory = Directory('assets/games');
    final List<Directory> gameDirectories =
        gamesDirectory.listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    expect(gameDirectories.length, 21);
    for (final Directory directory in gameDirectories) {
      final String gameJson = File(
        '${directory.path}${Platform.pathSeparator}game.json',
      ).readAsStringSync();
      final String resourceJson = File(
        '${directory.path}${Platform.pathSeparator}manifest.json',
      ).readAsStringSync();
      final GameManifest manifest = GameManifest.fromJson(
        jsonDecode(gameJson) as Map<String, dynamic>,
        resourceManifest: GameResourceManifest.fromJson(
          jsonDecode(resourceJson) as Map<String, dynamic>,
        ),
      );

      expect(manifest.slug, directory.path.split(Platform.pathSeparator).last);
      expect(manifest.resources, isNotEmpty);
      expect(manifest.toGameInfo(AppLanguage.zhHans).slug, manifest.slug);
      expect(manifest.toGameInfo(AppLanguage.en).slug, manifest.slug);
    }
  });
}

Map<String, dynamic> _resource({
  required String id,
  required String path,
  required String documentType,
  required String language,
  String sourceClass = 'official_extracted',
  String status = 'available',
  bool aiEnabled = true,
  int priority = 50,
}) {
  return <String, dynamic>{
    'id': id,
    'path': path,
    'documentType': documentType,
    'sourceClass': sourceClass,
    'origin': 'test',
    'language': language,
    'edition': 'second_edition_2019',
    'status': status,
    'enabled': true,
    'aiEnabled': aiEnabled,
    'priority': priority,
    'derivedFrom': <String>[],
    'sourceUrl': null,
    'reviewStatus': 'checked',
    'notes': null,
  };
}
