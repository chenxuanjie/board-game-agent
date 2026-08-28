enum DesktopLibraryResourceType {
  rulebook,
  faq,
  assetIndex,
  reference,
  playerAid,
  supplement,
  other,
}

enum DesktopLibraryResourceFormat { markdown, pdf, html, text, image, other }

/// A document shown in the desktop library.
///
/// [isRemote] distinguishes a resource discovered from WebDAV from the local
/// bundled fallback used when the remote index cannot be reached.
class DesktopLibraryResource {
  const DesktopLibraryResource({
    required this.id,
    required this.gameSlug,
    required this.gameTitle,
    required this.remotePath,
    required this.title,
    required this.language,
    required this.type,
    required this.format,
    required this.isRemote,
    this.status = 'available',
    this.enabled = true,
    this.sourceClass = 'unknown',
  });

  final String id;
  final String gameSlug;
  final String gameTitle;
  final String remotePath;
  final String title;
  final String language;
  final DesktopLibraryResourceType type;
  final DesktopLibraryResourceFormat format;
  final bool isRemote;
  final String status;
  final bool enabled;
  final String sourceClass;

  bool get canOpen =>
      format == DesktopLibraryResourceFormat.markdown ||
      format == DesktopLibraryResourceFormat.pdf;

  String get fileName {
    final String normalized = remotePath.replaceAll('\\', '/');
    final int separator = normalized.lastIndexOf('/');
    return separator < 0 ? normalized : normalized.substring(separator + 1);
  }

  String get typeLabel {
    switch (type) {
      case DesktopLibraryResourceType.rulebook:
        return '规则书';
      case DesktopLibraryResourceType.faq:
        return 'FAQ';
      case DesktopLibraryResourceType.assetIndex:
        return '索引';
      case DesktopLibraryResourceType.reference:
        return '规则参考';
      case DesktopLibraryResourceType.playerAid:
        return '玩家辅助';
      case DesktopLibraryResourceType.supplement:
        return '补充资料';
      case DesktopLibraryResourceType.other:
        return '其他';
    }
  }

  String get formatLabel {
    switch (format) {
      case DesktopLibraryResourceFormat.markdown:
        return 'Markdown';
      case DesktopLibraryResourceFormat.pdf:
        return 'PDF';
      case DesktopLibraryResourceFormat.html:
        return 'HTML';
      case DesktopLibraryResourceFormat.text:
        return '文本';
      case DesktopLibraryResourceFormat.image:
        return '图片';
      case DesktopLibraryResourceFormat.other:
        return '文件';
    }
  }
}
