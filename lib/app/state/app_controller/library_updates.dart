part of '../app_controller.dart';

extension AppLibraryUpdateController on AppController {
  Future<void> _initializeRemoteLibrary() async {
    try {
      await refreshLibraryResources();
      // Warm the image cache first so the update probe has a stable baseline
      // and cannot race with the version manifest writes performed by
      // ensureCached().
      await prefetchHomeImages();
      await refreshAssetAccessStatus();
      await checkForLibraryUpdates();
    } catch (error, stackTrace) {
      debugPrint('[updates] initial remote library warm-up failed: $error');
      debugPrint('$stackTrace');
    } finally {
      _startAssetStatusPolling();
    }
  }

  Future<void> checkForLibraryUpdates({bool forcePromptReset = false}) async {
    if (_checkingLibraryUpdate) {
      return;
    }

    _checkingLibraryUpdate = true;
    if (forcePromptReset) {
      _libraryUpdatePromptSeen = false;
    }
    _notifyListeners();

    try {
      debugPrint('[updates] checkForLibraryUpdates started');
      final List<String> changedPaths = <String>[];
      final Set<String> changedGameTitles = <String>{};
      const String catalogPath = 'assets/catalog.json';
      final List<AssetSourceConfig> sourcesForCheck = _preferredUpdateSources();
      debugPrint(
        '[updates] sourcesForCheck: ${sourcesForCheck.map((s) => s.id).join(', ')}',
      );
      final String? remoteCatalogSource = await _remoteAssetService
          .fetchRemoteText(sources: sourcesForCheck, remotePath: catalogPath);
      final String localCatalogSource = await _gameManifestService
          .loadCatalogSource(remoteAssetService: _remoteAssetService);
      debugPrint(
        '[updates] remote catalog fetched: ${remoteCatalogSource != null} len=${remoteCatalogSource?.length ?? 0}',
      );
      debugPrint('[updates] local catalog len=${localCatalogSource.length}');
      if (remoteCatalogSource != null &&
          _normalizeSource(remoteCatalogSource) !=
              _normalizeSource(localCatalogSource)) {
        changedPaths.add(catalogPath);
        changedGameTitles.addAll(
          await _diffCatalogGameTitles(remoteCatalogSource),
        );
        debugPrint('[updates] catalog changed');
        final List<String> titles = changedGameTitles.toList()..sort();
        _setPendingLibraryUpdate(
          RemoteLibraryUpdate(
            changedPaths: changedPaths,
            changedGameTitles: titles,
          ),
        );
        debugPrint('[updates] pending update titles: ${titles.join(', ')}');
        return;
      } else {
        debugPrint('[updates] catalog unchanged');
      }

      final Iterable<String> assetPaths = _trackedRemotePaths().toSet();
      for (final String remotePath in assetPaths) {
        if (remotePath == catalogPath) {
          continue;
        }
        final bool changed = await _remoteAssetService.hasRemoteChanged(
          sources: sourcesForCheck,
          remotePath: remotePath,
        );
        if (changed) {
          changedPaths.add(remotePath);
          final String? title = _gameTitleForRemotePath(remotePath);
          if (title != null) {
            changedGameTitles.add(title);
          }
          debugPrint('[updates] changed path: $remotePath');
        }
      }

      if (changedPaths.isNotEmpty) {
        final List<String> titles = changedGameTitles.toList()..sort();
        _setPendingLibraryUpdate(
          RemoteLibraryUpdate(
            changedPaths: changedPaths,
            changedGameTitles: titles,
          ),
        );
        debugPrint('[updates] pending update titles: ${titles.join(', ')}');
      } else {
        debugPrint('[updates] no remote library updates detected');
      }
    } catch (error, stackTrace) {
      debugPrint('[updates] checkForLibraryUpdates failed: $error');
      debugPrint('$stackTrace');
    } finally {
      _checkingLibraryUpdate = false;
      _notifyListeners();
    }
  }

  Future<void> applyPendingLibraryUpdate() async {
    final RemoteLibraryUpdate? pending = _pendingLibraryUpdate;
    if (pending == null || _applyingLibraryUpdate) {
      return;
    }

    _applyingLibraryUpdate = true;
    _notifyListeners();

    try {
      for (final String remotePath in pending.changedPaths) {
        debugPrint('[updates] applying update for: $remotePath');
        await _remoteAssetService.ensureCached(
          sources: _assetSourceConfigs,
          remotePath: remotePath,
          forceRefresh: true,
          allowCachedFallback: false,
        );
      }

      _resolvedAssetPaths.clear();
      _games = await _loadGamesForLanguage(_language);
      _selectedGameId = _resolveSelectedGameId(_selectedGameId);
      _pendingLibraryUpdate = null;
      _libraryUpdatePromptSeen = false;
      await prefetchHomeImages();
      debugPrint('[updates] apply complete');
    } finally {
      _applyingLibraryUpdate = false;
      _notifyListeners();
    }
  }

  void dismissPendingLibraryUpdatePrompt() {
    _libraryUpdatePromptSeen = true;
    _notifyListeners();
  }

  bool shouldShowLibraryUpdatePrompt() {
    return _pendingLibraryUpdate != null && !_libraryUpdatePromptSeen;
  }

  Future<List<String>> _diffCatalogGameTitles(
    String remoteCatalogSource,
  ) async {
    try {
      final remoteCatalog = GameCatalogManifest.fromJson(
        jsonDecode(remoteCatalogSource) as Map<String, dynamic>,
      );
      final GameCatalogManifest localCatalog = await _gameManifestService
          .loadBundledCatalogManifest();

      final Map<String, GameCatalogEntry> localEntries =
          <String, GameCatalogEntry>{
            for (final entry in localCatalog.games) entry.slug: entry,
          };
      final Map<String, GameCatalogEntry> remoteEntries =
          <String, GameCatalogEntry>{
            for (final entry in remoteCatalog.games) entry.slug: entry,
          };

      final Set<String> changedSlugs = <String>{};
      for (final String slug in remoteEntries.keys) {
        final local = localEntries[slug];
        final remote = remoteEntries[slug];
        if (remote == null) {
          continue;
        }
        if (local == null) {
          changedSlugs.add(slug);
          continue;
        }
        if (local.enabled != remote.enabled || local.order != remote.order) {
          changedSlugs.add(slug);
        }
      }
      debugPrint(
        '[updates] changed slugs from catalog diff: ${changedSlugs.join(', ')}',
      );

      final List<String> titles = <String>[];
      for (final String slug in changedSlugs) {
        final String? title = await _titleForSlug(slug);
        if (title != null) {
          titles.add(title);
        }
      }
      return titles;
    } catch (_) {
      return <String>[];
    }
  }

  Future<String?> _titleForSlug(String slug) async {
    final GameInfo? local = _games
        .where((game) => game.slug == slug)
        .cast<GameInfo?>()
        .firstWhere((game) => game != null, orElse: () => null);
    if (local != null) {
      return _composeDisplayTitle(local.title, local.subtitle);
    }

    try {
      final String source = await _gameManifestService.loadManifestSource(
        remotePath: 'assets/games/$slug/game.json',
        remoteAssetService: _remoteAssetService,
        sources: _assetSourceConfigs,
      );
      final GameManifest manifest = GameManifest.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
      );
      final GameInfo info = manifest.toGameInfo(_language);
      return _composeDisplayTitle(info.title, info.subtitle);
    } catch (_) {
      return slug;
    }
  }

  String? _gameTitleForRemotePath(String remotePath) {
    final RegExpMatch? match = RegExp(
      r'assets/games/([^/]+)/',
    ).firstMatch(remotePath);
    if (match == null) {
      return null;
    }
    final String slug = match.group(1)!;
    final GameInfo? game = _games
        .where((item) => item.slug == slug)
        .cast<GameInfo?>()
        .firstWhere((item) => item != null, orElse: () => null);
    if (game == null) {
      return slug;
    }
    return _composeDisplayTitle(game.title, game.subtitle);
  }

  String _composeDisplayTitle(String title, String subtitle) {
    final String normalizedTitle = title.trim();
    final String normalizedSubtitle = subtitle.trim();
    if (normalizedTitle.isEmpty) {
      return normalizedSubtitle;
    }
    if (normalizedSubtitle.isEmpty ||
        normalizedSubtitle.toLowerCase() == normalizedTitle.toLowerCase()) {
      return normalizedTitle;
    }
    return '$normalizedTitle / $normalizedSubtitle';
  }
}
