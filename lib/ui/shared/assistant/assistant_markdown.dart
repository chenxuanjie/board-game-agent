import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Retains complete top-level blocks while only the unfinished block changes.
/// Fences, indented/list continuations and block quotes stay together. Reference
/// definitions and HTML use the complete document because their scope is global.
class StreamingMarkdownDocument {
  String _text = '';
  int _scan = 0, _start = 0;
  int? _boundary;
  String? _fence;
  bool _globalSyntax = false;
  final List<String> blocks = [];
  static final _fences = RegExp(r'^ {0,3}(`{3,}|~{3,})');
  static final _continuation = RegExp(r'^(?:[ \t]+|>|[-+*] |\d+[.)] )');
  static final _global = RegExp(
    r'^ {0,3}(?:\[[^\]]+\]:|<[A-Za-z!/]\w*(?:\s|>))',
  );

  String get tail => _text.substring(_start);

  void update(String text) {
    if (text == _text) return;
    if (!text.startsWith(_text)) {
      _scan = _start = 0;
      _boundary = null;
      _fence = null;
      _globalSyntax = false;
      blocks.clear();
    }
    _text = text;
    if (_globalSyntax) return;
    while (true) {
      final end = text.indexOf('\n', _scan);
      if (end < 0) return;
      final line = text.substring(_scan, end).replaceAll('\r', '');
      _scan = end + 1;
      if (_fence == null && _global.hasMatch(line)) {
        _globalSyntax = true;
        blocks.clear();
        _start = 0;
        return;
      }
      if (line.trim().isEmpty && _fence == null) {
        if (_start < _scan) _boundary ??= _scan;
        continue;
      }
      if (_boundary case final boundary?) {
        if (!_continuation.hasMatch(line)) {
          final block = text.substring(_start, boundary);
          if (block.trim().isNotEmpty) blocks.add(block);
          _start = boundary;
        }
        _boundary = null;
      }
      final marker = _fences.firstMatch(line)?.group(1);
      if (_fence == null) {
        _fence = marker;
      } else if (marker != null &&
          marker[0] == _fence![0] &&
          marker.length >= _fence!.length &&
          line.trim() == marker) {
        _fence = null;
      }
    }
  }
}

class AssistantMarkdown extends StatefulWidget {
  const AssistantMarkdown({
    super.key,
    required this.data,
    required this.streaming,
    required this.styleSheet,
  });
  final String data;
  final bool streaming;
  final MarkdownStyleSheet styleSheet;
  @override
  State<AssistantMarkdown> createState() => _AssistantMarkdownState();
}

class _AssistantMarkdownState extends State<AssistantMarkdown> {
  final _document = StreamingMarkdownDocument();
  final List<Widget> _stable = [];
  MarkdownStyleSheet? _style;
  List<String> _rendered = [];

  @override
  Widget build(BuildContext context) {
    if (!widget.streaming) {
      return MarkdownBody(
        data: widget.data,
        selectable: true,
        styleSheet: widget.styleSheet,
      );
    }
    _document.update(widget.data);
    final blocks = _document.blocks;
    if (_style != widget.styleSheet ||
        blocks.length < _rendered.length ||
        _rendered.asMap().entries.any((e) => blocks[e.key] != e.value)) {
      _stable.clear();
      _rendered = [];
      _style = widget.styleSheet;
    }
    while (_stable.length < blocks.length) {
      final i = _stable.length;
      _stable.add(
        RepaintBoundary(
          child: MarkdownBody(
            key: ValueKey('stream-block-$i'),
            data: blocks[i],
            selectable: true,
            styleSheet: widget.styleSheet,
          ),
        ),
      );
      _rendered.add(blocks[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in _stable) ...[
          block,
          SizedBox(height: widget.styleSheet.blockSpacing ?? 8),
        ],
        MarkdownBody(
          key: const ValueKey('stream-tail'),
          data: _document.tail,
          selectable: true,
          styleSheet: widget.styleSheet,
        ),
      ],
    );
  }
}
