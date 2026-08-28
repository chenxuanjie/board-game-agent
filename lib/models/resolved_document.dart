enum DocumentRenderType { pdf, markdown, html, text, image }

class ResolvedDocument {
  const ResolvedDocument({
    required this.remotePath,
    required this.renderType,
    required this.label,
  });

  final String remotePath;
  final DocumentRenderType renderType;
  final String label;
}
