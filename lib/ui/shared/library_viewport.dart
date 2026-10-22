import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../app/state/browse_session.dart';

/// Restores a game anchor rather than a pixel offset when grid columns change.
/// A lazy grid first estimates the row, then corrects to the actual laid-out card.
class LibraryViewport extends StatefulWidget {
  const LibraryViewport({
    super.key,
    required this.state,
    required this.ids,
    required this.layout,
    required this.builder,
    this.controller,
    this.estimate,
  });
  final LibraryBrowseState state;
  final List<String> ids;
  final Object layout;
  final ScrollController? controller;
  final double Function(int index)? estimate;
  final Widget Function(Map<String, GlobalKey> keys) builder;
  @override
  State<LibraryViewport> createState() => _LibraryViewportState();
}

class _LibraryViewportState extends State<LibraryViewport> {
  final Map<String, GlobalKey> _keys = {};
  bool _restoring = false;
  int _generation = 0;
  int _positionRevision = 0;
  @override
  void initState() {
    super.initState();
    _positionRevision = widget.state.positionRevision;
    widget.controller?.addListener(_capture);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant LibraryViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_capture);
      widget.controller?.addListener(_capture);
    }
    if (oldWidget.state != widget.state ||
        _positionRevision != widget.state.positionRevision ||
        oldWidget.layout != widget.layout ||
        !_sameIds(oldWidget.ids, widget.ids)) {
      _schedule();
    }
    _positionRevision = widget.state.positionRevision;
  }

  bool _sameIds(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  double? _top(String id) {
    final render = _keys[id]?.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(render);
    return viewport?.getOffsetToReveal(render, 0).offset;
  }

  void _capture() {
    final scroll = widget.controller;
    if (_restoring || scroll == null || scroll.positions.length != 1) return;
    final offset = scroll.offset;
    if (offset <= 0) {
      widget.state
        ..offset = 0
        ..anchorId = null
        ..anchorIndex = 0
        ..anchorDelta = 0;
      return;
    }
    String? anchor;
    double? top;
    for (final id in widget.ids) {
      final candidate = _top(id);
      if (candidate == null || candidate > offset + 1) continue;
      if (top == null || candidate > top + 1) {
        anchor = id;
        top = candidate;
      }
    }
    if (anchor == null && widget.ids.isNotEmpty) {
      anchor = widget.ids.first;
      top = _top(anchor);
    }
    widget.state.offset = offset;
    if (anchor != null && top != null) {
      widget.state.anchorId = anchor;
      widget.state.anchorIndex = widget.ids.indexOf(anchor);
      widget.state.anchorDelta = offset - top;
    }
  }

  void _schedule() {
    _restoring = true;
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      final scroll = widget.controller;
      if (scroll == null || !scroll.hasClients || widget.ids.isEmpty) {
        _restoring = false;
        return;
      }
      var index = widget.ids.indexOf(widget.state.anchorId ?? '');
      if (index < 0) {
        index = widget.state.anchorIndex.clamp(0, widget.ids.length - 1);
      }
      final id = widget.ids[index];
      final hasAnchor = widget.state.anchorId != null;
      final top = _top(id) ?? widget.estimate?.call(index);
      final target = hasAnchor && top != null
          ? top + widget.state.anchorDelta
          : widget.state.offset;
      scroll.jumpTo(target.clamp(0.0, scroll.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation || !scroll.hasClients) return;
        final exact = _top(id);
        if (hasAnchor && exact != null) {
          scroll.jumpTo(
            (exact + widget.state.anchorDelta).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
        _restoring = false;
        _capture();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  @override
  void dispose() {
    _capture();
    _generation++;
    widget.controller?.removeListener(_capture);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _keys.removeWhere((id, _) => !widget.ids.contains(id));
    for (final id in widget.ids) {
      _keys.putIfAbsent(id, GlobalKey.new);
    }
    return widget.builder(_keys);
  }
}
