class MarkdownSanitizer {
  static String toSpeechPlainText(String input) {
    var text = input;
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    text = text.replaceAll(RegExp(r'`([^`]*)`'), r'$1');
    text = text.replaceAll(RegExp(r'(^|\n)\s{0,3}#{1,6}\s*', multiLine: true), '\n');
    text = text.replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1');
    text = text.replaceAll(RegExp(r'\*(.*?)\*'), r'$1');
    text = text.replaceAll(RegExp(r'_(.*?)_'), r'$1');
    text = text.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), ' ');
    text = text.replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1');
    text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
    text = text.replaceAll('|', ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }
}
