import 'dart:io';

import '../models/asset_source_config.dart';
import '../models/evidence_chunk.dart';
import '../models/game_info.dart';
import 'remote_asset_service.dart';

/// Loads the knowledge files associated with a game.
///
/// Retrieval is deliberately file-based for now. Each Markdown file becomes
/// one evidence chunk, leaving the service boundary ready for real chunking
/// and ranking later.
class RuleKnowledgeRetriever {
  const RuleKnowledgeRetriever({
    this.maxCharsPerAsset = 6000,
    this.maxCharsTotal = 24000,
  });

  final int maxCharsPerAsset;
  final int maxCharsTotal;

  Future<List<EvidenceChunk>> retrieve({
    required GameInfo game,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
  }) async {
    final List<EvidenceChunk> chunks = <EvidenceChunk>[];
    int totalChars = 0;

    for (final String remotePath in game.knowledgeAssetPaths) {
      if (!remotePath.endsWith('.md')) {
        continue;
      }

      try {
        String? content = await _loadLocalKnowledgeFile(remotePath);
        content =
            await remoteAssetService.loadTextFromAny(
              sources: assetSourceConfigs,
              remotePaths: <String>[remotePath],
            ) ??
            content;
        if (content == null) {
          continue;
        }

        content = _normalizeContent(content);
        if (content.isEmpty) {
          continue;
        }

        final int remaining = maxCharsTotal - totalChars;
        if (remaining <= 0) {
          break;
        }

        if (content.length > maxCharsPerAsset) {
          content =
              '${content.substring(0, maxCharsPerAsset)}\n\n[Truncated for prompt length]';
        }
        if (content.length > remaining) {
          content = content.substring(0, remaining);
        }

        chunks.add(EvidenceChunk(sourcePath: remotePath, content: content));
        totalChars += content.length;
      } catch (_) {
        // A missing or unreadable knowledge file should not block other files.
        continue;
      }
    }

    return List<EvidenceChunk>.unmodifiable(chunks);
  }

  /// Formats evidence for a prompt, applying an optional total character cap.
  String formatForPrompt(List<EvidenceChunk> chunks, {int? maxChars}) {
    final StringBuffer buffer = StringBuffer();
    int totalChars = 0;
    final int? limit = maxChars;

    for (final EvidenceChunk chunk in chunks) {
      if (limit != null && totalChars >= limit) {
        break;
      }

      String content = chunk.content;
      if (limit != null) {
        final int remaining = limit - totalChars;
        if (content.length > remaining) {
          content =
              '${content.substring(0, remaining)}\n\n[Truncated for prompt length]';
        }
      }

      buffer.writeln('### ${chunk.sourceName}');
      buffer.writeln(content);
      buffer.writeln();
      totalChars += content.length;
    }

    return buffer.toString().trim();
  }

  String _normalizeContent(String input) {
    return input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<String?> _loadLocalKnowledgeFile(String remotePath) async {
    final List<File> candidates = <File>[
      File(remotePath),
      File('${Directory.current.path}${Platform.pathSeparator}$remotePath'),
      File.fromUri(Uri.base.resolve(remotePath)),
    ];

    for (final File file in candidates) {
      try {
        if (await file.exists()) {
          return file.readAsString();
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
