part of '../app_controller.dart';

/// Catalog availability is independent of app readiness and document downloads.
extension AppCatalogController on AppController {
  void _cancelGameCatalogRequest() {
    _gameCatalogDeadline?.cancel();
    final abort = _gameCatalogAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  LibraryLoadState get gameCatalogLoadState => _gameCatalogLoadState;
  int get gameCatalogRequestRevision => _gameCatalogGeneration;
  bool get gameCatalogFailed => _gameCatalogFailed;
  bool get showGameCatalogNotice =>
      _gameCatalogFailed && !_gameCatalogNoticeDismissed;
  String get gameCatalogFailureMessage => hasGames
      ? copy.localized('暂时无法刷新桌游资料。', 'Could not refresh game data.')
      : copy.localized('桌游资料暂时无法加载。', 'Game data is unavailable.');

  void dismissGameCatalogNotice() {
    _gameCatalogNoticeDismissed = true;
    _notifyListeners();
  }

  /// All entry points join the same catalog request. Failure remains visible in
  /// state; retries never rerun app initialization or reset personal data.
  Future<void> retryGameCatalog() async {
    _gameCatalogNoticeDismissed = false;
    try {
      await reloadGames();
    } catch (_) {
      // The UI reads this lane's failure. No unhandled button/background future.
    }
  }

  Future<bool> _loadGameCatalog() {
    final epoch = _identityScopeEpoch;
    final language = _language;
    final key = '$epoch|${language.name}|$_updateSourceSignature';
    if (_gameCatalogFuture != null && _gameCatalogRequestKey == key) {
      return _gameCatalogFuture!;
    }
    _cancelGameCatalogRequest();
    final abort = Completer<void>();
    _gameCatalogAbort = abort;
    final generation = ++_gameCatalogGeneration;
    bool current() =>
        !_controllerDisposed &&
        generation == _gameCatalogGeneration &&
        epoch == _identityScopeEpoch &&
        language == _language &&
        key == '$epoch|${_language.name}|$_updateSourceSignature';
    _gameCatalogRequestKey = key;
    _gameCatalogLoadState = LibraryLoadState.loading;
    final future = Future<bool>.microtask(() async {
      if (!current()) return false;
      final deadline = Completer<List<GameInfo>>();
      // All platforms share the published catalog lane. Keep UI loading bounded
      // even if a transport or storage provider does not settle promptly.
      final timer = _remoteAssetService.usesPublishedLibrary
          ? Timer(const Duration(seconds: 65), () {
              deadline.completeError(
                TimeoutException('Catalog loading timed out'),
              );
            })
          : null;
      _gameCatalogDeadline = timer;
      try {
        final games = await Future.any([
          _loadGamesForLanguage(language),
          deadline.future,
          abort.future.then<List<GameInfo>>(
            (_) => throw StateError('Catalog request cancelled'),
          ),
        ]);
        if (!current()) return false;
        // Commit only a complete validated catalog. A failed fetch cannot erase
        // the last good list or masquerade as a successful empty library.
        _games = games;
        _selectedGameId = _resolveSelectedGameId(_selectedGameId);
        _libraryResources = _catalogLibraryResources(_games);
        _libraryLoadState = _libraryResources.isEmpty
            ? LibraryLoadState.empty
            : LibraryLoadState.success;
        _libraryLoadError = null;
        _gameCatalogFailed = false;
        _gameCatalogNoticeDismissed = false;
        _gameCatalogLoadState = games.isEmpty
            ? LibraryLoadState.empty
            : LibraryLoadState.success;
        return true;
      } catch (error) {
        if (current()) {
          _gameCatalogFailed = true;
          _gameCatalogLoadState = LibraryLoadState.failure;
          debugPrint('[catalog] load failed (${error.runtimeType})');
        }
        rethrow;
      } finally {
        timer?.cancel();
        if (identical(_gameCatalogAbort, abort)) {
          _gameCatalogAbort = null;
          _gameCatalogDeadline = null;
        }
      }
    });
    _gameCatalogFuture = future;
    future
        .whenComplete(() {
          if (identical(_gameCatalogFuture, future)) _gameCatalogFuture = null;
          if (!_controllerDisposed &&
              generation == _gameCatalogGeneration &&
              epoch == _identityScopeEpoch) {
            if (!current()) {
              _gameCatalogLoadState = _gameCatalogFailed
                  ? LibraryLoadState.failure
                  : hasGames
                  ? LibraryLoadState.success
                  : LibraryLoadState.idle;
            }
            _notifyListeners();
          }
        })
        .catchError((Object _) => false);
    _notifyListeners();
    return future;
  }
}
