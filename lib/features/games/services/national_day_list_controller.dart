import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../settings/services/preferences_service.dart';

/// One durable list shared by the desktop and compact seasonal pages.
class NationalDayListController extends ChangeNotifier {
  NationalDayListController({
    required this.preferences,
    required this.defaultSlugs,
  });

  final PreferencesService preferences;
  final List<String> Function() defaultSlugs;
  List<String> _slugs = [];
  List<String> get slugs => List.unmodifiable(_slugs);
  final List<String> _rankedSlugs = [];

  /// Keep the last visible order when votes tie, without changing the saved list.
  List<String> rankByVotes(int Function(String) voteCount) {
    _reconcileRankedSlugs();
    final previous = {
      for (final (index, slug) in _rankedSlugs.indexed) slug: index,
    };
    final counts = {for (final slug in _rankedSlugs) slug: voteCount(slug)};
    _rankedSlugs.sort((left, right) {
      final difference = counts[right]!.compareTo(counts[left]!);
      return difference != 0
          ? difference
          : previous[left]!.compareTo(previous[right]!);
    });
    return List.unmodifiable(_rankedSlugs);
  }

  void _reconcileRankedSlugs() {
    final members = _slugs.toSet();
    _rankedSlugs.removeWhere((slug) => !members.contains(slug));
    final ranked = _rankedSlugs.toSet();
    _rankedSlugs.addAll(_slugs.where((slug) => !ranked.contains(slug)));
  }

  bool loading = false;
  bool saving = false;
  bool ready = false;
  String? error;
  bool Function()? canMutate;
  VoidCallback? onSaved;
  Future<void>? _loadFuture;
  bool _disposed = false;

  Future<void> load() {
    if (_disposed || ready) return Future.value();
    return _loadFuture ??= _load().whenComplete(() => _loadFuture = null);
  }

  Future<void> reload() async {
    if (_disposed || saving) throw StateError('清单数据暂忙');
    ready = false;
    await load();
  }

  Future<void> _load() async {
    loading = true;
    error = null;
    _notify();
    try {
      final stored = await preferences.loadNationalDayGameSlugs().timeout(
        const Duration(seconds: 8),
      );
      if (_disposed) return;
      _slugs = (stored ?? defaultSlugs()).toSet().toList();
      _reconcileRankedSlugs();
      ready = true;
    } catch (_) {
      if (!_disposed) error = '清单读取失败';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> save(Iterable<String> slugs) async {
    if (_disposed || !ready || saving || canMutate?.call() == false) {
      return false;
    }
    saving = true;
    var committed = false;
    _notify();
    try {
      final next = slugs.toSet().toList();
      await preferences
          .saveNationalDayGameSlugs(next)
          .timeout(const Duration(seconds: 8));
      if (_disposed) return false;
      _slugs = next;
      _reconcileRankedSlugs();
      committed = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      saving = false;
      _notify();
      if (committed) onSaved?.call();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
