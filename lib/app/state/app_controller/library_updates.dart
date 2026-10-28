part of '../app_controller.dart';

extension AppLibraryUpdateController on AppController {
  Future<void> _initializeRemoteLibrary() async {
    if (_controllerDisposed) return;
    _initialLibraryFullPending = true;
    // A revision response supplies availability and the update watermark.
    // Metadata refresh never downloads documents or scans a NAS directory.
    _startAssetStatusPolling();
    try {
      await refreshAssetAccessStatus();
      if (_controllerDisposed) return;
      await refreshLibraryResources();
      if (_controllerDisposed) return;
      await prefetchHomeImages();
    } catch (error) {
      debugPrint('[updates] initial library check failed: $error');
    }
  }

  String get _updateSourceSignature => canonicalJson(
    _assetSourceConfigs.map((source) => source.toMap()).toList(),
  );

  Future<void> checkForLibraryUpdates({int? knownRevision}) =>
      _startLibraryCheck(complete: true, knownRevision: knownRevision);

  Future<void> checkForLibraryUpdatesQuick({int? knownRevision}) =>
      _startLibraryCheck(complete: false, knownRevision: knownRevision);

  Future<void> _startLibraryCheck({
    required bool complete,
    int? knownRevision,
  }) {
    if (_controllerDisposed) {
      return Future.value();
    }
    if (!_requireLibraryAccess()) {
      _libraryUpdateError = copy.localized(
        '请先配置应用服务地址',
        'Configure the application service first',
      );
      _notifyListeners();
      return Future.value();
    }
    final active = _libraryCheckFuture;
    if (active != null) {
      final requestedEpoch = _identityScopeEpoch;
      final requestedSignature = _updateSourceSignature;
      if (_libraryCheckEpoch != requestedEpoch ||
          _libraryCheckSignature != requestedSignature) {
        return active.then<void>((_) {
          if (_controllerDisposed ||
              requestedEpoch != _identityScopeEpoch ||
              requestedSignature != _updateSourceSignature) {
            return Future<void>.value();
          }
          return _startLibraryCheck(
            complete: complete,
            knownRevision: knownRevision,
          );
        });
      }
      if (complete && !_libraryUpdateCheckFull) _libraryFullRequested = true;
      return active;
    }
    final done = Completer<void>();
    final epoch = _identityScopeEpoch;
    _libraryCheckFuture = done.future;
    _libraryCheckEpoch = epoch;
    _libraryCheckSignature = _updateSourceSignature;
    _checkingLibraryUpdate = true;
    _libraryFullRequested = complete;
    _notifyListeners();
    unawaited(() async {
      try {
        var source = knownRevision;
        do {
          _libraryUpdateCheckFull = _libraryFullRequested;
          _libraryFullRequested = false;
          await _runLibraryCheck(
            complete: _libraryUpdateCheckFull,
            knownRevision: source,
          );
          source = null;
        } while (_libraryFullRequested &&
            !_controllerDisposed &&
            epoch == _identityScopeEpoch);
      } finally {
        _libraryCheckFuture = null;
        _checkingLibraryUpdate = false;
        done.complete();
        _notifyListeners();
      }
    }());
    return done.future;
  }

  Future<void> _runLibraryCheck({
    required bool complete,
    int? knownRevision,
  }) async {
    final epoch = _identityScopeEpoch;
    final signature = _updateSourceSignature;
    bool current() =>
        !_controllerDisposed &&
        epoch == _identityScopeEpoch &&
        signature == _updateSourceSignature &&
        _identityScopeRequests == 0;
    _libraryUpdateError = null;
    _notifyListeners();
    try {
      final before = _remoteAssetService.catalog;
      final changed = await _remoteAssetService.refreshCatalog(
        knownRevision: knownRevision,
      );
      if (!current()) return;
      if (changed ||
          _gameCatalogFailed ||
          _gameCatalogLoadState == LibraryLoadState.idle) {
        await reloadGames();
        if (!current()) return;
        final next = _remoteAssetService.catalog;
        _resolvedAssetPaths.clear();
        _libraryContentRevision++;
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await refreshLibraryResources();
        if (!current()) return;
        if (before != null &&
            next != null &&
            before.revision != next.revision) {
          final ids = {...before.editions.keys, ...next.editions.keys}
              .where(
                (id) =>
                    canonicalJson(before.editions[id]) !=
                    canonicalJson(next.editions[id]),
              )
              .toList();
          final titles = {
            for (final game in before.games)
              game.id: game.toGameInfo(_language).title,
            for (final game in _games) game.id: game.title,
          };
          _lastLibraryUpdate = RemoteLibraryUpdate(
            changedPaths: [for (final id in ids) 'editions/$id'],
            changedGameTitles: [for (final id in ids) titles[id] ?? id],
            changes: [
              for (final id in ids)
                RemoteLibraryChange(
                  path: 'editions/$id',
                  title: titles[id] ?? id,
                  kind: next.editions[id] == null
                      ? RemoteLibraryChangeKind.disabled
                      : before.editions[id] == null
                      ? RemoteLibraryChangeKind.added
                      : RemoteLibraryChangeKind.modified,
                ),
            ],
          );
          _recordActivity(
            identityEpoch: epoch,
            kind: AppActivityKind.libraryUpdate,
            title: copy.localized('资料已更新', 'Library updated'),
            message: copy.localized(
              '已同步 ${ids.length} 个桌游的资料，版本 ${next.revision}。',
              'Updated ${ids.length} games to library revision ${next.revision}.',
            ),
          );
        }
      }
      if (complete && current()) _initialLibraryFullPending = false;
    } catch (_) {
      if (current()) {
        _libraryUpdateError = copy.localized(
          '无法检查资料更新，请检查连接后重试。',
          'Could not check for updates. Check your connection and retry.',
        );
      }
    }
  }

  bool get appUpdateInProgress => _appUpdateInteractions > 0;

  /// Holds unsolicited library prompts while an app update is being reviewed,
  /// downloaded or installed. Releasing does not consume the pending update.
  VoidCallback suspendLibraryUpdatePrompts() {
    _appUpdateInteractions++;
    _notifyListeners();
    var released = false;
    return () {
      if (released) return;
      released = true;
      _appUpdateInteractions--;
      _notifyListeners();
    };
  }
}
