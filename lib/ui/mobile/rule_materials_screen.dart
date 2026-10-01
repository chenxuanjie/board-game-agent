import 'package:flutter/material.dart';

import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../features/games/models/game_info.dart';
import '../../features/library/models/game_resource.dart';
import '../../features/library/models/resolved_document.dart';
import '../shared/documents/document_viewer_launcher.dart';
import 'game_cover.dart';

/// A document index, rather than another filtered game search.
class MobileRuleMaterialsScreen extends StatefulWidget {
  const MobileRuleMaterialsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileRuleMaterialsScreen> createState() =>
      _MobileRuleMaterialsScreenState();
}

class _MobileRuleMaterialsScreenState extends State<MobileRuleMaterialsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant MobileRuleMaterialsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<_RuleMaterial> _materials(GameInfo game) {
    final resources = game.resources.where(
      (resource) =>
          resource.enabled &&
          resource.isAvailable &&
          !resource.isInOthersDirectory &&
          resource.isRenderableDocument &&
          const {
            'rulebook',
            'how_to_play',
            'faq',
          }.contains(resource.documentType),
    );
    final items = resources
        .map(
          (resource) => _RuleMaterial(
            path: resource.assetPathFor(game.slug),
            type: resource.documentType,
            language: resource.language,
            official: resource.sourceClass == 'official',
          ),
        )
        .where((item) => item.path.isNotEmpty)
        .toList();
    if (items.isNotEmpty) return items;
    if (game.rulebookAssetPath.trim().isNotEmpty &&
        !isOtherStoragePath(game.rulebookAssetPath)) {
      items.add(
        _RuleMaterial(
          path: game.rulebookAssetPath,
          type: 'rulebook',
          language: '',
          official: false,
        ),
      );
    }
    if (game.faqAssetPath.trim().isNotEmpty &&
        !isOtherStoragePath(game.faqAssetPath)) {
      items.add(
        _RuleMaterial(
          path: game.faqAssetPath,
          type: 'faq',
          language: '',
          official: false,
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.controller.copy;
    final palette = AppPalette.of(context);
    final query = _search.text.trim().toLowerCase();
    final entries = widget.controller.games
        .map((game) => (game: game, materials: _materials(game)))
        .where((entry) => entry.materials.isNotEmpty)
        .where(
          (entry) =>
              query.isEmpty ||
              <String>[
                entry.game.title,
                entry.game.subtitle,
                ...entry.game.aliases,
                ...entry.materials.map((item) => item.path),
              ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList(growable: false);

    return Scaffold(
      key: const ValueKey('mobile-rule-materials-root'),
      backgroundColor: palette.pageBackground,
      appBar: AppBar(title: Text(copy.localized('规则资料', 'Rule materials'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TextField(
                  key: const ValueKey('mobile-rule-materials-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: copy.localized(
                      '搜索游戏或资料',
                      'Search games or documents',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          copy.localized('没有找到规则资料', 'No rule materials found'),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return Card(
                            child: ExpansionTile(
                              key: ValueKey(
                                'mobile-rule-game-${entry.game.id}',
                              ),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 38,
                                  height: 46,
                                  child: MobileGameCover(
                                    controller: widget.controller,
                                    game: entry.game,
                                  ),
                                ),
                              ),
                              title: Text(entry.game.title),
                              subtitle: Text(
                                copy.localized(
                                  '${entry.materials.length} 份资料',
                                  '${entry.materials.length} documents',
                                ),
                              ),
                              children: [
                                for (final item in entry.materials)
                                  ListTile(
                                    key: ValueKey(
                                      'mobile-rule-document-${item.path}',
                                    ),
                                    leading: Icon(
                                      item.path.toLowerCase().endsWith('.pdf')
                                          ? Icons.picture_as_pdf_outlined
                                          : Icons.article_outlined,
                                    ),
                                    title: Text(item.title(copy.isChinese)),
                                    subtitle: Text(
                                      item.description(copy.isChinese),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => DocumentViewerLauncher.open(
                                      context,
                                      controller: widget.controller,
                                      document: ResolvedDocument(
                                        remotePath: item.path,
                                        renderType:
                                            item.path.toLowerCase().endsWith(
                                              '.pdf',
                                            )
                                            ? DocumentRenderType.pdf
                                            : DocumentRenderType.markdown,
                                        label: item.title(copy.isChinese),
                                      ),
                                      title:
                                          '${entry.game.title} · ${item.title(copy.isChinese)}',
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleMaterial {
  const _RuleMaterial({
    required this.path,
    required this.type,
    required this.language,
    required this.official,
  });

  final String path;
  final String type;
  final String language;
  final bool official;

  String title(bool zh) => switch (type) {
    'faq' => zh ? '常见问题' : 'FAQ',
    'how_to_play' => zh ? '玩法说明' : 'How to play',
    _ => zh ? '规则书' : 'Rulebook',
  };

  String description(bool zh) {
    final languageLabel = switch (language.toLowerCase()) {
      'cn' || 'zh' => zh ? '中文' : 'Chinese',
      'en' => zh ? '英文' : 'English',
      'de' => zh ? '德文' : 'German',
      _ => zh ? '未标注语言' : 'Language unspecified',
    };
    final source = official
        ? (zh ? '官方原件' : 'Official source')
        : (zh ? '整理资料' : 'Prepared material');
    return '$languageLabel · $source';
  }
}
