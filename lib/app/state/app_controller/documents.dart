part of '../app_controller.dart';

extension AppDocumentController on AppController {
  String _normalizeSource(String source) {
    return source.replaceAll('\r\n', '\n').trim();
  }

  Future<String?> cacheDocument(String remotePath) async {
    if (remotePath.trim().isEmpty || isOtherStoragePath(remotePath)) {
      return null;
    }

    CachedAsset? cached;
    try {
      cached = await _remoteAssetService.ensureCached(
        sources: _assetSourceConfigs,
        remotePath: remotePath,
      );
    } catch (_) {
      cached = null;
    }
    if (cached == null) {
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '文档暂时不可用',
        checkedAt: DateTime.now(),
      );
      _notifyListeners();
      return null;
    }
    _resolvedAssetPaths[remotePath] = cached.localPath;
    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.success,
      message: '文档已缓存',
      checkedAt: DateTime.now(),
    );
    _notifyListeners();
    return cached.localPath;
  }

  Future<List<int>?> loadDocumentBytes(String remotePath) async {
    if (remotePath.trim().isEmpty || isOtherStoragePath(remotePath)) {
      return null;
    }
    try {
      final bytes = await _remoteAssetService.loadBytes(
        sources: _assetSourceConfigs,
        remotePath: remotePath,
      );
      if (bytes == null || bytes.isEmpty) {
        _assetConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.failure,
          message: '文档暂时不可用',
          checkedAt: DateTime.now(),
        );
        _notifyListeners();
        return null;
      }
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.success,
        message: '文档已加载',
        checkedAt: DateTime.now(),
      );
      _notifyListeners();
      return bytes;
    } catch (_) {
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '文档暂时不可用',
        checkedAt: DateTime.now(),
      );
      _notifyListeners();
      return null;
    }
  }

  Future<String?> loadMarkdownDocument(String remotePath) async {
    return loadLibraryResourceText(remotePath);
  }

  Future<String?> loadLibraryResourceText(String remotePath) async {
    final String? localPath = await cacheDocument(remotePath);
    if (localPath == null) {
      if (remotePath.startsWith('assets/')) {
        try {
          return await rootBundle.loadString(remotePath);
        } catch (_) {
          return null;
        }
      }
      return null;
    }
    try {
      return await File(localPath).readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<ResolvedDocument?> resolveRulebookDocument(GameInfo game) {
    return _resolveDocument(
      game: game,
      baseName: 'rulebook',
      fallbackRemotePath: game.rulebookAssetPath,
      fallbackLabel: copy.rulesBook,
    );
  }

  Future<ResolvedDocument?> resolveFaqDocument(GameInfo game) {
    return _resolveDocument(
      game: game,
      baseName: 'faq',
      fallbackRemotePath: game.faqAssetPath,
      fallbackLabel: copy.faq,
    );
  }

  Future<String?> resolveImagePath(String remotePath) async {
    if (remotePath.trim().isEmpty || isOtherStoragePath(remotePath)) {
      return null;
    }
    try {
      return await _cacheImage(remotePath);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _cacheImage(String remotePath) async {
    if (remotePath.trim().isEmpty || isOtherStoragePath(remotePath)) {
      return null;
    }
    if (_resolvedAssetPaths.containsKey(remotePath)) {
      return _resolvedAssetPaths[remotePath];
    }
    final CachedAsset? cached = await _remoteAssetService.ensureCached(
      sources: _assetSourceConfigs,
      remotePath: remotePath,
    );
    if (cached == null) {
      return null;
    }
    _resolvedAssetPaths[remotePath] = cached.localPath;
    return cached.localPath;
  }

  Future<ResolvedDocument?> _resolveDocument({
    required GameInfo game,
    required String baseName,
    required String fallbackRemotePath,
    required String fallbackLabel,
  }) async {
    final String fallback = fallbackRemotePath.trim();
    final List<String> candidates = _documentCandidates(
      game: game,
      baseName: baseName,
    );
    if (candidates.isEmpty) {
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '文档暂时不可用',
        checkedAt: DateTime.now(),
      );
      _notifyListeners();
      return null;
    }

    if (kIsWeb) {
      for (final candidate in candidates) {
        try {
          final bytes = await _remoteAssetService.loadBytes(
            sources: _assetSourceConfigs,
            remotePath: candidate,
          );
          if (bytes != null && bytes.isNotEmpty) {
            return ResolvedDocument(
              remotePath: candidate,
              renderType: _documentRenderTypeForPath(candidate),
              label: fallbackLabel,
            );
          }
        } catch (_) {
          continue;
        }
      }
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '文档暂时不可用',
        checkedAt: DateTime.now(),
      );
      _notifyListeners();
      return null;
    }

    for (final candidate in candidates) {
      CachedAsset? cached;
      try {
        cached = await _remoteAssetService.ensureCached(
          sources: _assetSourceConfigs,
          remotePath: candidate,
        );
      } catch (_) {
        cached = null;
      }
      if (cached != null) {
        _resolvedAssetPaths[candidate] = cached.localPath;
        _assetConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.success,
          message: '文档已缓存',
          checkedAt: DateTime.now(),
        );
        _notifyListeners();
        return ResolvedDocument(
          remotePath: candidate,
          renderType: _documentRenderTypeForPath(candidate),
          label: fallbackLabel,
        );
      }
    }

    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.failure,
      message: '文档暂时不可用',
      checkedAt: DateTime.now(),
    );
    _notifyListeners();
    if (fallback.isNotEmpty && !isOtherStoragePath(fallback)) {
      return ResolvedDocument(
        remotePath: fallback,
        renderType: _documentRenderTypeForPath(fallback),
        label: fallbackLabel,
      );
    }
    return null;
  }

  DocumentRenderType _documentRenderTypeForPath(String path) {
    final String normalized = path.toLowerCase();
    if (normalized.endsWith('.pdf')) return DocumentRenderType.pdf;
    if (normalized.endsWith('.html') || normalized.endsWith('.htm')) {
      return DocumentRenderType.html;
    }
    if (normalized.endsWith('.txt')) return DocumentRenderType.text;
    if (RegExp(r'\.(png|jpe?g|webp|gif|bmp)$').hasMatch(normalized)) {
      return DocumentRenderType.image;
    }
    return DocumentRenderType.markdown;
  }

  List<String> _documentCandidates({
    required GameInfo game,
    required String baseName,
  }) {
    final Set<String> documentTypes = baseName == 'rulebook'
        ? <String>{'rulebook', 'how_to_play'}
        : <String>{'faq'};
    final List<GameResource> resources = game.resources
        .where(
          (resource) =>
              documentTypes.contains(resource.documentType) &&
              resource.isAvailable &&
              resource.enabled &&
              !resource.isInOthersDirectory &&
              resource.isRenderableDocument &&
              resource.path.trim().isNotEmpty,
        )
        .toList();
    resources.sort((a, b) {
      if (baseName == 'rulebook') {
        final int documentFormat = _documentFormatRank(
          a,
        ).compareTo(_documentFormatRank(b));
        if (documentFormat != 0) return documentFormat;
      }
      final int language = _documentLanguageRank(
        a.language,
      ).compareTo(_documentLanguageRank(b.language));
      if (language != 0) return language;
      final int priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      return a.id.compareTo(b.id);
    });

    final List<String> candidates = resources
        .map((resource) => resource.assetPathFor(game.slug))
        .toList();
    final String fallback = baseName == 'rulebook'
        ? game.rulebookAssetPath
        : game.faqAssetPath;
    if (fallback.trim().isNotEmpty &&
        !isOtherStoragePath(fallback) &&
        !candidates.contains(fallback)) {
      candidates.add(fallback);
    }
    return candidates;
  }

  int _documentFormatRank(GameResource resource) {
    if (resource.format == 'pdf' && resource.sourceClass == 'official') {
      return 0;
    }
    if (resource.format == 'pdf') {
      return 1;
    }
    return 2;
  }

  int _documentLanguageRank(String resourceLanguage) {
    final String normalized = resourceLanguage.toLowerCase();
    if (language == AppLanguage.zhHans) {
      if (normalized == 'cn' || normalized == 'zh' || normalized == 'zhhans') {
        return 0;
      }
      if (normalized == 'multi') return 1;
      if (normalized == 'en') return 2;
      return 3;
    }
    if (normalized == 'en') return 0;
    if (normalized == 'multi') return 1;
    if (normalized == 'cn' || normalized == 'zh' || normalized == 'zhhans') {
      return 2;
    }
    return 3;
  }

  Iterable<String> _trackedRemotePaths() sync* {
    final Set<String> paths = <String>{};
    void addPath(String path) {
      if (path.trim().isNotEmpty && !isOtherStoragePath(path)) {
        paths.add(path);
      }
    }

    for (final GameInfo game in _games) {
      addPath(game.coverAssetPath);
      addPath(game.bannerAssetPath);
      for (final String path in game.galleryAssetPaths) {
        addPath(path);
      }
      addPath(game.rulebookAssetPath);
      addPath(game.faqAssetPath);
      for (final GameResource resource in game.resources) {
        if (!resource.isInOthersDirectory) {
          addPath(resource.assetPathFor(game.slug));
        }
      }
      addPath('assets/games/${game.slug}/game.json');
      addPath('assets/games/${game.slug}/manifest.json');
    }
    yield* paths;
  }

  List<AssetSourceConfig> _preferredUpdateSources() {
    final List<AssetSourceConfig> successful = _assetSourceConfigs
        .where(
          (source) =>
              _assetSourceStatuses[source.id]?.state ==
              ConnectivityState.success,
        )
        .toList();
    if (successful.isNotEmpty) {
      return successful;
    }
    // At startup every source may still be unknown, and the first source is
    // not necessarily reachable. Try the full configured list so a healthy
    // fallback source can establish the update baseline.
    return List<AssetSourceConfig>.from(_assetSourceConfigs);
  }

  Future<List<GameInfo>> _loadGamesForLanguage(AppLanguage language) async {
    final manifests = await _gameManifestService.loadEnabledGames(
      remoteAssetService: _remoteAssetService,
      sources: _assetSourceConfigs,
      preferRemote: false,
    );
    return manifests.map((manifest) => manifest.toGameInfo(language)).toList();
  }

  String _resolveSelectedGameId(String preferredId) {
    if (_games.any((game) => game.id == preferredId)) {
      return preferredId;
    }
    if (_games.isNotEmpty) {
      return _games.first.id;
    }
    return preferredId;
  }
}
