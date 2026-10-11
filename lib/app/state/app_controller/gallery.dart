part of '../app_controller.dart';

extension AppGalleryController on AppController {
  int gameGalleryIndex(GameInfo game, List<String> paths) {
    final path = _gameGallerySelections[game.slug];
    final index = path == null ? -1 : paths.indexOf(path);
    return index < 0 ? 0 : index;
  }

  /// Browsing positions are local per-account UI state, outside cloud/public data.
  Future<void> rememberGameGalleryImage(GameInfo game, String path) {
    if (_controllerDisposed || _switchingIdentityScope || path.isEmpty) {
      return Future<void>.value();
    }
    _gameGallerySelections[game.slug] = path;
    // Pin the immutable store to the current account. The detail view redraws
    // locally, avoiding a cloud synchronization trigger for a browsing change.
    return _preferencesService.saveGameGallerySelection(game.slug, path);
  }

  Future<void> _restoreGameGallerySelections() async {
    try {
      _gameGallerySelections = await _preferencesService
          .loadGameGallerySelections()
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      _gameGallerySelections = {};
      debugPrint('[gallery] Could not restore browsing positions');
    }
  }
}
