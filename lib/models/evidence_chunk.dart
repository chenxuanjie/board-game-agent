/// A piece of local knowledge supplied to the board-game AI.
///
/// The first implementation creates one chunk per Markdown knowledge file.
/// The model is intentionally independent from the current retrieval strategy
/// so semantic chunking can be added later without changing the AI contract.
class EvidenceChunk {
  const EvidenceChunk({
    required this.sourcePath,
    required this.content,
    this.title,
  });

  final String sourcePath;
  final String content;
  final String? title;

  String get sourceName {
    final String normalized = sourcePath.replaceAll('\\', '/');
    return normalized.split('/').last;
  }
}
