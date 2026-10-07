part of '../app_controller.dart';

extension AppLibraryUpdateController on AppController {
  Future<void> _initializeRemoteLibrary() async {
    try {
      await refreshLibraryResources();
      await prefetchHomeImages();
      await refreshAssetAccessStatus();
      await checkForLibraryUpdates();
    } catch (error) {
      debugPrint('[updates] initial library check failed: $error');
    } finally {
      _startAssetStatusPolling();
    }
  }

  String get _updateSourceSignature => canonicalJson(
    _assetSourceConfigs.map((source) => source.toMap()).toList(),
  );

  Future<void> checkForLibraryUpdates({bool forcePromptReset = false}) async {
    if (!_requireLibraryAccess()) return;
    if (_checkingLibraryUpdate || _applyingLibraryUpdate) return;
    final epoch = _identityScopeEpoch;
    final signature = _updateSourceSignature;
    bool current() =>
        epoch == _identityScopeEpoch &&
        signature == _updateSourceSignature &&
        !_switchingIdentityScope;
    _checkingLibraryUpdate = true;
    _libraryUpdateError = null;
    if (forcePromptReset) _libraryUpdatePromptSeen = false;
    _notifyListeners();
    try {
      final elapsed = Stopwatch()..start();
      final sources = _preferredUpdateSources();
      const catalogPath = 'assets/catalog.json';
      final remoteSource = await _remoteAssetService.fetchRemoteText(
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
              for (final r in GameResourceManifest.fromJson(previous).resources)
                r.path: r,
            };
            final newResources = GameResourceManifest.fromJson(next).resources;
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
      if (!current()) return;
      if (paths.isEmpty) {
        _pendingLibraryUpdate = null;
      } else {
        _setPendingLibraryUpdate(
          RemoteLibraryUpdate(
            changedPaths: paths.toList(),
            changedGameTitles: titles.toList()..sort(),
            changes: changes,
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
    } finally {
      _checkingLibraryUpdate = false;
      _notifyListeners();
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
        epoch == _identityScopeEpoch &&
        signature == _updateSourceSignature &&
        !_switchingIdentityScope;
    _applyingLibraryUpdate = true;
    _libraryUpdateError = null;
    _libraryUpdateCompleted = 0;
    _notifyListeners();
    try {
      // Metadata last: failed downloads retain the pending review for retry.
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
        _notifyListeners();
      }
      final games = await _loadGamesForLanguage(_language);
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
    } catch (_) {
      if (current()) {
        _libraryUpdateError = copy.localized(
          '更新未完成（$_libraryUpdateCompleted/${pending.changedCount}），请重试。',
          'Update incomplete ($_libraryUpdateCompleted/${pending.changedCount}). Retry.',
        );
      }
    } finally {
      _applyingLibraryUpdate = false;
      _notifyListeners();
    }
  }

  void dismissPendingLibraryUpdatePrompt() {
    _libraryUpdatePromptSeen = true;
    _notifyListeners();
  }

  bool shouldShowLibraryUpdatePrompt() =>
      _pendingLibraryUpdate != null && !_libraryUpdatePromptSeen;

  String? _gameTitleForRemotePath(String path) {
    final slug = RegExp(r'assets/games/([^/]+)/').firstMatch(path)?.group(1);
    if (slug == null) return null;
    return _games.where((game) => game.slug == slug).firstOrNull?.title ?? slug;
  }
}
