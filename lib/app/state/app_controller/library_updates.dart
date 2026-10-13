part of '../app_controller.dart';

extension AppLibraryUpdateController on AppController {
  Future<void> _initializeRemoteLibrary() async {
    _initialLibraryFullPending = true;
    // The first successful catalog read both reports availability and starts
    // the deferred startup full check with that same response body. Neither
    // index discovery nor image prefetch may postpone this initial probe.
    _startAssetStatusPolling();
    try {
      await refreshAssetAccessStatus();
      await refreshLibraryResources();
      await prefetchHomeImages();
    } catch (error) {
      debugPrint('[updates] initial library check failed: $error');
    }
  }

  String get _updateSourceSignature => canonicalJson(
    _assetSourceConfigs.map((source) => source.toMap()).toList(),
  );

  Future<void> checkForLibraryUpdates({
    bool forcePromptReset = false,
    String? catalogSource,
  }) => _startLibraryCheck(
    complete: true,
    forcePromptReset: forcePromptReset,
    catalogSource: catalogSource,
  );

  Future<void> checkForLibraryUpdatesQuick({String? catalogSource}) =>
      _startLibraryCheck(complete: false, catalogSource: catalogSource);

  Future<void> _startLibraryCheck({
    required bool complete,
    bool forcePromptReset = false,
    String? catalogSource,
  }) {
    if (_controllerDisposed || _applyingLibraryUpdate) {
      return Future.value();
    }
    if (!_requireLibraryAccess()) {
      _libraryUpdateError = copy.localized(
        '请先登录后检查资料',
        'Sign in before checking library updates',
      );
      _notifyListeners();
      return Future.value();
    }
    if (forcePromptReset) _libraryUpdatePromptSeen = false;
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
            catalogSource: catalogSource,
            forcePromptReset: forcePromptReset,
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
        var source = catalogSource;
        do {
          _libraryUpdateCheckFull = _libraryFullRequested;
          _libraryFullRequested = false;
          await _runLibraryCheck(
            complete: _libraryUpdateCheckFull,
            catalogSource: source,
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
    String? catalogSource,
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
      final elapsed = Stopwatch()..start();
      final sources = _preferredUpdateSources();
      const catalogPath = 'assets/catalog.json';
      final remoteSource =
          catalogSource ??
          await _remoteAssetService.fetchRemoteText(
            sources: sources,
            remotePath: catalogPath,
          );
      if (!current()) return;
      if (remoteSource == null) throw StateError('Catalog unavailable');
      final localSource = await _gameManifestService.loadCatalogSource(
        remoteAssetService: _remoteAssetService,
      );
      final remote = jsonDecode(remoteSource) as Map<String, dynamic>;
      final local = jsonDecode(localSource) as Map<String, dynamic>;
      GameCatalogManifest.fromJson(remote);
      final paths = <String>{};
      final changes = <RemoteLibraryChange>[];
      final titles = <String>{};
      final remoteTexts = <String, String>{};
      Future<String> remoteText(String path) async => remoteTexts[path] ??=
          await _remoteAssetService.fetchRemoteText(
            sources: sources,
            remotePath: path,
          ) ??
          '';
      Future<String?> localText(String path) async {
        try {
          return await _gameManifestService.loadManifestSource(
            remotePath: path,
            remoteAssetService: _remoteAssetService,
          );
        } catch (_) {
          return null;
        }
      }

      if (canonicalJson(remote) != canonicalJson(local)) {
        paths.add(catalogPath);
        for (final change in catalogChanges(local, remote)) {
          final slug = change.title;
          var title = _gameTitleForRemotePath(change.path) ?? slug;
          if (change.kind == RemoteLibraryChangeKind.added) {
            final gameSource = await remoteText(change.path);
            if (gameSource.isEmpty) throw StateError('New game unavailable');
            final game = GameManifest.fromJson(jsonDecode(gameSource));
            final info = game.toGameInfo(_language);
            title = info.title;
            paths.add(change.path);
            final manifestPath = 'assets/games/$slug/manifest.json';
            final resourceSource = await remoteText(manifestPath);
            if (resourceSource.isNotEmpty) {
              paths.add(manifestPath);
              for (final resource in GameResourceManifest.fromJson(
                jsonDecode(resourceSource),
              ).resources) {
                if (resource.enabled &&
                    resource.isAvailable &&
                    !resource.isInOthersDirectory) {
                  paths.add(resource.assetPathFor(slug));
                }
              }
            }
            paths.addAll(
              [
                info.coverAssetPath,
                info.bannerAssetPath,
                ...info.galleryAssetPaths,
              ].where((path) => path.isNotEmpty),
            );
          }
          titles.add(title);
          changes.add(
            RemoteLibraryChange(
              path: change.kind == RemoteLibraryChangeKind.added
                  ? change.path
                  : catalogPath,
              title: title,
              kind: change.kind,
              fields: change.fields,
            ),
          );
        }
        if (changes.isEmpty) {
          changes.add(
            const RemoteLibraryChange(
              path: catalogPath,
              title: 'catalog',
              fields: ['catalog'],
            ),
          );
        }
      }
      if (complete) {
        final tracked = _trackedRemotePaths().toSet().toList();
        final probes = <String, bool>{};
        for (var start = 0; start < tracked.length; start += 4) {
          if (!current()) return;
          if (elapsed.elapsed > const Duration(minutes: 2)) {
            throw TimeoutException('Library check deadline');
          }
          final batch = tracked
              .skip(start)
              .take(4)
              .where((p) => !paths.contains(p));
          await Future.wait(
            batch.map((path) async {
              probes[path] = await _remoteAssetService.hasRemoteChanged(
                sources: sources,
                remotePath: path,
              );
            }),
          );
        }
        for (final path in tracked) {
          if (!current()) return;
          if (paths.contains(path) || path == catalogPath) continue;
          if (probes[path] != true) {
            continue;
          }
          paths.add(path);
          final title = _gameTitleForRemotePath(path);
          if (title != null) titles.add(title);
          final fields = <String>[];
          final valueChanges = <String, String>{};
          if (path.endsWith('/game.json') || path.endsWith('/manifest.json')) {
            final before = await localText(path);
            final after = await remoteText(path);
            if (after.isEmpty) throw StateError('Changed metadata unavailable');
            final previous = before == null
                ? <String, dynamic>{}
                : jsonDecode(before) as Map<String, dynamic>;
            final next = jsonDecode(after) as Map<String, dynamic>;
            if (path.endsWith('/game.json')) GameManifest.fromJson(next);
            fields.addAll(changedMetadataFields(previous, next));
            valueChanges.addAll(metadataValueChanges(previous, next));
            if (path.endsWith('/manifest.json')) {
              final slug = RegExp(
                r'assets/games/([^/]+)/',
              ).firstMatch(path)!.group(1)!;
              final oldResources = {
                for (final r in GameResourceManifest.fromJson(
                  previous,
                ).resources)
                  r.path: r,
              };
              final newResources = GameResourceManifest.fromJson(
                next,
              ).resources;
              final activePaths = newResources
                  .where(
                    (r) => r.enabled && r.isAvailable && !r.isInOthersDirectory,
                  )
                  .map((r) => r.path)
                  .toSet();
              for (final old in oldResources.values) {
                if (old.enabled &&
                    old.isAvailable &&
                    !old.isInOthersDirectory &&
                    !activePaths.contains(old.path)) {
                  changes.add(
                    RemoteLibraryChange(
                      path: old.assetPathFor(slug),
                      title: title ?? slug,
                      kind: RemoteLibraryChangeKind.disabled,
                    ),
                  );
                }
              }
              for (final resource in newResources) {
                if (!resource.enabled ||
                    !resource.isAvailable ||
                    resource.isInOthersDirectory) {
                  continue;
                }
                final old = oldResources[resource.path];
                if (old == null || !old.enabled || !old.isAvailable) {
                  final addedPath = resource.assetPathFor(slug);
                  paths.add(addedPath);
                  changes.add(
                    RemoteLibraryChange(
                      path: addedPath,
                      title: title ?? slug,
                      kind: RemoteLibraryChangeKind.added,
                    ),
                  );
                }
              }
            }
          }
          changes.add(
            RemoteLibraryChange(
              path: path,
              title: title ?? path.split('/').last,
              fields: fields,
              valueChanges: valueChanges,
            ),
          );
        }
      }
      if (!current()) return;
      if (complete) _initialLibraryFullPending = false;
      if (paths.isEmpty) {
        if (complete) _pendingLibraryUpdate = null;
      } else {
        // A quick catalog read cannot disprove earlier full resource findings.
        final previous = complete ? null : _pendingLibraryUpdate;
        _setPendingLibraryUpdate(
          RemoteLibraryUpdate(
            changedPaths: {...?previous?.changedPaths, ...paths}.toList(),
            changedGameTitles: {
              ...?previous?.changedGameTitles,
              ...titles,
            }.toList()..sort(),
            changes: [
              ...?previous?.changes.where(
                (old) => !changes.any(
                  (next) => next.path == old.path && next.title == old.title,
                ),
              ),
              ...changes,
            ],
          ),
          identityEpoch: epoch,
        );
      }
    } catch (_) {
      if (current()) {
        _libraryUpdateError = copy.localized(
          '无法检查资料更新，请检查连接后重试。',
          'Could not check for updates. Check your connection and retry.',
        );
      }
    }
  }

  Future<void> applyPendingLibraryUpdate() async {
    if (!_requireLibraryAccess()) return;
    final pending = _pendingLibraryUpdate;
    if (pending == null || _applyingLibraryUpdate || _checkingLibraryUpdate) {
      return;
    }
    final epoch = _identityScopeEpoch;
    final signature = _updateSourceSignature;
    final sources = List<AssetSourceConfig>.from(_assetSourceConfigs);
    bool current() =>
        !_controllerDisposed &&
        epoch == _identityScopeEpoch &&
        signature == _updateSourceSignature &&
        _identityScopeRequests == 0;
    _applyingLibraryUpdate = true;
    _libraryUpdateError = null;
    _libraryUpdateCompleted = 0;
    _notifyListeners();
    var notificationStarted = false;
    try {
      // Metadata last: failed downloads retain the pending review for retry.
      await _backgroundTransfers.start(
        id: 'library',
        title: '桌游资料更新',
        message: '正在更新 0/${pending.changedCount} 项',
        total: pending.changedCount,
      );
      notificationStarted = true;
      final ordered = pending.changedPaths.toList()
        ..sort((a, b) {
          int priority(String path) => path == 'assets/catalog.json'
              ? 2
              : path.endsWith('.json')
              ? 1
              : 0;
          return priority(a).compareTo(priority(b));
        });
      final elapsed = Stopwatch()..start();
      for (final path in ordered) {
        if (elapsed.elapsed > const Duration(minutes: 15)) {
          throw TimeoutException('Library update deadline');
        }
        if (!current()) throw StateError('Connection changed');
        final asset = await _remoteAssetService.ensureCached(
          sources: sources,
          remotePath: path,
          forceRefresh: true,
          allowCachedFallback: false,
        );
        if (asset == null || !asset.exists || !asset.fromRemote) {
          throw StateError('Resource download failed');
        }
        if (!current()) throw StateError('Connection changed');
        _libraryUpdateCompleted++;
        _backgroundTransfers.progress(
          id: 'library',
          message: '已更新 $_libraryUpdateCompleted/${pending.changedCount} 项',
          completed: _libraryUpdateCompleted,
          total: pending.changedCount,
        );
        _notifyListeners();
      }
      final remaining = const Duration(minutes: 15) - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Library update deadline');
      }
      final games = await _loadGamesForLanguage(_language).timeout(remaining);
      if (!current()) throw StateError('Connection changed');
      _games = games;
      _resolvedAssetPaths.clear();
      _selectedGameId = _resolveSelectedGameId(_selectedGameId);
      _pendingLibraryUpdate = null;
      _libraryUpdatePromptSeen = true;
      _libraryContentRevision++;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      _recordActivity(
        identityEpoch: epoch,
        kind: AppActivityKind.libraryUpdate,
        title: copy.localized('资料已更新', 'Library updated'),
        message: copy.localized(
          '已更新 ${pending.changedCount} 项资料。',
          '${pending.changedCount} resources updated.',
        ),
      );
      unawaited(refreshLibraryResources(force: true));
      await _backgroundTransfers.finish(
        id: 'library',
        message: '已更新 ${pending.changedCount} 项桌游资料',
      );
      notificationStarted = false;
    } catch (error) {
      if (current()) {
        _libraryUpdateError = error is BackgroundTransferFailure
            ? error.message.toString()
            : copy.localized(
                '更新未完成（$_libraryUpdateCompleted/${pending.changedCount}），请重试。',
                'Update incomplete ($_libraryUpdateCompleted/${pending.changedCount}). Retry.',
              );
      }
    } finally {
      if (notificationStarted) {
        await _backgroundTransfers.finish(
          id: 'library',
          message:
              '更新未完成 $_libraryUpdateCompleted/${pending.changedCount} 项，请重试',
          failed: true,
        );
      }
      _applyingLibraryUpdate = false;
      _notifyListeners();
    }
  }

  void dismissPendingLibraryUpdatePrompt() {
    _libraryUpdatePromptSeen = true;
    _notifyListeners();
  }

  bool shouldShowLibraryUpdatePrompt() =>
      !appUpdateInProgress &&
      _pendingLibraryUpdate != null &&
      !_libraryUpdatePromptSeen;

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

  String? _gameTitleForRemotePath(String path) {
    final slug = RegExp(r'assets/games/([^/]+)/').firstMatch(path)?.group(1);
    if (slug == null) return null;
    return _games.where((game) => game.slug == slug).firstOrNull?.title ?? slug;
  }
}
