part of '../app_controller.dart';

extension AppLibraryController on AppController {
  Future<void> prefetchHomeImages() async {
    final imagePaths = <String>{
      for (final game in games.take(6)) ...[
        game.coverAssetPath,
        game.bannerAssetPath,
      ],
    }.toList();

    _homeAssetsLoading = imagePaths.isNotEmpty;
    _homeAssetsLoaded = 0;
    _homeAssetsTotal = imagePaths.length;
    _notifyListeners();

    for (final String path in imagePaths) {
      await _cacheImage(path);
      _homeAssetsLoaded += 1;
      _notifyListeners();
    }

    _homeAssetsLoading = false;
    _notifyListeners();
  }

  /// Loads the persisted index first, then checks the published SQL
  /// catalog in the background. A single in-flight request is shared by all
  /// callers so opening the page and pressing refresh cannot race each other.
  /// Existing cached rows stay visible while this network request runs.
  Future<void> refreshLibraryResources({bool force = false}) {
    if (!_remoteAssetService.accessAllowed) return Future<void>.value();
    final Future<void>? active = _libraryRefreshFuture;
    if (active != null) {
      return active;
    }

    final int generation = ++_libraryRefreshGeneration;
    // Only a cold start without any local index should occupy the content
    // area with a spinner. Refresh-button callers can force a network check,
    // but still keep already-rendered rows in place.
    if (_libraryResources.isEmpty) {
      _libraryLoadState = LibraryLoadState.loading;
      _libraryLoadError = null;
      _notifyListeners();
    } else if (force) {
      _libraryLoadError = null;
      _notifyListeners();
    }

    final Future<void> future = _refreshLibraryResources(
      generation,
      force: force,
    );
    _libraryRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_libraryRefreshFuture, future)) {
            _libraryRefreshFuture = null;
          }
        })
        .catchError((Object _) {});
    return future;
  }

  Future<void> _refreshLibraryResources(
    int generation, {
    bool force = false,
  }) async {
    final identityEpoch = _identityScopeEpoch;
    await _ensureLibraryCacheLoaded();
    if (generation != _libraryRefreshGeneration) {
      return;
    }

    // Cache loading can provide the first visible rows when this method is
    // called before AppController.initialize() has completed.
    if (_libraryResources.isNotEmpty &&
        _libraryLoadState == LibraryLoadState.loading) {
      _libraryLoadState = LibraryLoadState.success;
      _notifyListeners();
    }

    try {
      if (force) {
        final changed = await _remoteAssetService.refreshCatalog();
        if (generation != _libraryRefreshGeneration) return;
        if (changed) {
          _resolvedAssetPaths.clear();
          _libraryContentRevision++;
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          await reloadGames();
        }
      }
      final index = await _loadRemoteLibraryIndex();
      if (generation != _libraryRefreshGeneration) {
        return;
      }

      final List<DesktopLibraryResource> remoteResources =
          _localizeLibraryResources(index);
      final nextResources = remoteResources;
      final bool changed = !_sameLibraryIndex(_libraryResources, nextResources);
      if (changed || _libraryResources.isEmpty) {
        _libraryResources = nextResources;
      }
      _libraryLoadState = index.isEmpty
          ? LibraryLoadState.empty
          : LibraryLoadState.success;
      _libraryLoadError = null;
    } catch (error) {
      if (generation != _libraryRefreshGeneration) {
        return;
      }
      _libraryLoadState = LibraryLoadState.failure;
      _libraryLoadError = _safeStatusError(error);
      _recordLibraryLoadFailure(
        _libraryLoadError!,
        identityEpoch: identityEpoch,
      );
      debugPrint('[assets] desktop library index unavailable: $error');
    }
    _notifyListeners();
  }

  /// Restores only index metadata. The actual PDF/Markdown/HTML bytes remain
  /// in [RemoteAssetService]'s document cache and are never read here.
  Future<void> _ensureLibraryCacheLoaded() async {
    await _remoteAssetService.restoreCatalog();
    final snapshot = _remoteAssetService.catalog;
    if (snapshot != null) {
      _libraryResources = _catalogLibraryResources(
        snapshot.games.map((game) => game.toGameInfo(_language)),
      );
      _libraryLoadState = _libraryResources.isEmpty
          ? LibraryLoadState.empty
          : LibraryLoadState.success;
    }
  }

  List<DesktopLibraryResource> _localizeLibraryResources(
    Iterable<DesktopLibraryResource> resources,
  ) {
    final Map<String, GameInfo> gamesBySlug = <String, GameInfo>{
      for (final GameInfo game in _games) game.slug: game,
    };
    return resources
        .map(
          (DesktopLibraryResource resource) => resource.copyWith(
            gameTitle:
                gamesBySlug[resource.gameSlug]?.title ?? resource.gameTitle,
            type: _normalizeLibraryResourceType(resource.type),
          ),
        )
        .toList(growable: false);
  }

  DesktopLibraryResourceType _normalizeLibraryResourceType(
    DesktopLibraryResourceType type,
  ) {
    switch (type) {
      case DesktopLibraryResourceType.rulebook:
        return DesktopLibraryResourceType.rulebook;
      case DesktopLibraryResourceType.faq:
        return DesktopLibraryResourceType.faq;
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.playerAid:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        return DesktopLibraryResourceType.other;
    }
  }

  bool _sameLibraryIndex(
    List<DesktopLibraryResource> left,
    List<DesktopLibraryResource> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    final Map<String, DesktopLibraryResource> leftByPath =
        <String, DesktopLibraryResource>{
          for (final DesktopLibraryResource resource in left)
            resource.remotePath: resource,
        };
    final Map<String, DesktopLibraryResource> rightByPath =
        <String, DesktopLibraryResource>{
          for (final DesktopLibraryResource resource in right)
            resource.remotePath: resource,
        };
    if (leftByPath.length != rightByPath.length) {
      return false;
    }
    for (final String path in leftByPath.keys) {
      final DesktopLibraryResource? a = leftByPath[path];
      final DesktopLibraryResource? b = rightByPath[path];
      if (a == null ||
          b == null ||
          a.id != b.id ||
          a.gameSlug != b.gameSlug ||
          a.title != b.title ||
          a.language != b.language ||
          a.typeCode != b.typeCode ||
          a.formatCode != b.formatCode ||
          a.isRemote != b.isRemote ||
          a.status != b.status ||
          a.enabled != b.enabled ||
          a.sourceClass != b.sourceClass) {
        return false;
      }
    }
    return true;
  }

  Future<List<DesktopLibraryResource>> _loadRemoteLibraryIndex() async {
    if (_gameCatalogLoadState == LibraryLoadState.idle) await reloadGames();
    if (_gameCatalogFailed) throw StateError('资料目录暂不可用');
    return _catalogLibraryResources(_games);
  }

  List<DesktopLibraryResource> _catalogLibraryResources(
    Iterable<GameInfo> editions,
  ) {
    final resources = <DesktopLibraryResource>[];
    for (final edition in editions) {
      final game = edition;
      for (final resource in edition.resources) {
        if (!resource.path.startsWith('docs/') ||
            resource.isInOthersDirectory ||
            !resource.enabled ||
            !resource.isAvailable) {
          continue;
        }
        resources.add(
          DesktopLibraryResource(
            id: resource.id,
            gameSlug: game.slug,
            gameTitle: game.title,
            remotePath: resource.assetPathFor(game.slug),
            title: _libraryResourceTitle(
              resource.path,
              documentType: resource.documentType,
            ),
            language: _libraryResourceLanguage(
              resource.path,
              explicitCode: resource.language,
            ),
            type: _libraryResourceType(
              resource.path,
              documentType: resource.documentType,
            ),
            format: _libraryResourceFormat(resource.path),
            isRemote: true,
            status: resource.status,
            enabled: resource.enabled,
            sourceClass: resource.sourceClass,
          ),
        );
      }
    }
    resources.sort(_compareLibraryResources);
    return List.unmodifiable(resources);
  }

  DesktopLibraryResourceType _libraryResourceType(
    String path, {
    String? documentType,
  }) {
    final String explicit = documentType?.trim().toLowerCase() ?? '';
    switch (explicit) {
      case 'rulebook':
      case 'how_to_play':
        return DesktopLibraryResourceType.rulebook;
      case 'faq':
      case 'ruling':
      case 'errata':
        return DesktopLibraryResourceType.faq;
      case 'asset_index':
      case 'rules_reference':
      case 'supplement':
      case 'variant':
      case 'campaign_guide':
      case 'scenario_book':
        return DesktopLibraryResourceType.other;
      case 'player_aid':
      case 'player-aid':
      case 'playeraid':
      case 'aid':
      case 'quick_reference':
        return DesktopLibraryResourceType.playerAid;
    }

    final String lower = path.toLowerCase();
    if (lower.contains('faq') ||
        lower.contains('answer') ||
        lower.contains('ruling') ||
        lower.contains('errata')) {
      return DesktopLibraryResourceType.faq;
    }
    if (lower.contains('player_aid') ||
        lower.contains('player-aid') ||
        lower.contains('quick_reference')) {
      return DesktopLibraryResourceType.playerAid;
    }
    if (lower.contains('reference')) {
      return DesktopLibraryResourceType.other;
    }
    if (lower.contains('rulebook') ||
        lower.contains('how_to_play') ||
        lower.contains('learn_to_play') ||
        lower.endsWith('rules_official_page.html') ||
        lower.endsWith('rules_official_page.htm')) {
      return DesktopLibraryResourceType.rulebook;
    }
    return DesktopLibraryResourceType.other;
  }

  DesktopLibraryResourceFormat _libraryResourceFormat(String path) {
    final String lower = path.toLowerCase();
    final int dot = lower.lastIndexOf('.');
    final String extension = dot < 0 ? '' : lower.substring(dot + 1);
    switch (extension) {
      case 'md':
      case 'markdown':
        return DesktopLibraryResourceFormat.markdown;
      case 'pdf':
        return DesktopLibraryResourceFormat.pdf;
      case 'html':
      case 'htm':
        return DesktopLibraryResourceFormat.html;
      case 'txt':
        return DesktopLibraryResourceFormat.text;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
        return DesktopLibraryResourceFormat.image;
      default:
        return DesktopLibraryResourceFormat.other;
    }
  }

  String _libraryResourceLanguage(String path, {String? explicitCode}) {
    final String explicit = explicitCode?.trim().toLowerCase() ?? '';
    if (explicit == 'cn' ||
        explicit == 'zh' ||
        explicit == 'zh-cn' ||
        explicit == 'zh-hans' ||
        explicit == 'z_hans') {
      return '中文';
    }
    if (explicit == 'en' || explicit == 'en-us' || explicit == 'en-gb') {
      return '英文';
    }
    if (explicit == 'multi' || explicit == 'mixed') {
      return '多语言';
    }
    if (explicit == 'none' || explicit == 'unknown') {
      return '未标注';
    }

    final String lower = path.toLowerCase();
    if (RegExp(r'(^|[_\-.])(zh|cn|z[_-]?hans)([_\-.]|$)').hasMatch(lower) ||
        lower.contains('/zh/')) {
      return '中文';
    }
    if (RegExp(r'(^|[_\-.])en([_\-.]|$)').hasMatch(lower) ||
        lower.contains('/en/')) {
      return '英文';
    }
    return '未标注';
  }

  String _libraryResourceTitle(String path, {String? documentType}) {
    final String normalized = path.replaceAll('\\', '/');
    final String fileName = normalized.split('/').last;
    final int dot = fileName.lastIndexOf('.');
    final String stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    final DesktopLibraryResourceType type = _libraryResourceType(
      path,
      documentType: documentType,
    );
    switch (type) {
      case DesktopLibraryResourceType.rulebook:
        return '规则书';
      case DesktopLibraryResourceType.faq:
        return 'FAQ';
      case DesktopLibraryResourceType.assetIndex:
        return '资料索引';
      case DesktopLibraryResourceType.reference:
        return '规则参考';
      case DesktopLibraryResourceType.playerAid:
        return '玩家辅助';
      case DesktopLibraryResourceType.supplement:
        return '补充资料';
      case DesktopLibraryResourceType.other:
        return stem.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    }
  }

  int _compareLibraryResources(
    DesktopLibraryResource left,
    DesktopLibraryResource right,
  ) {
    final int game = left.gameTitle.compareTo(right.gameTitle);
    if (game != 0) return game;
    final int type = left.type.index.compareTo(right.type.index);
    if (type != 0) return type;
    return left.remotePath.compareTo(right.remotePath);
  }

  Future<ResolvedDocument?> resolveLibraryResource(
    DesktopLibraryResource resource,
  ) async {
    if (!resource.canOpen) {
      return null;
    }
    if (!resource.isRemote) {
      final GameInfo? game = _games
          .where((GameInfo item) => item.slug == resource.gameSlug)
          .cast<GameInfo?>()
          .firstWhere((GameInfo? item) => item != null, orElse: () => null);
      if (game != null &&
          resource.type == DesktopLibraryResourceType.rulebook) {
        return resolveRulebookDocument(game);
      }
      if (game != null && resource.type == DesktopLibraryResourceType.faq) {
        return resolveFaqDocument(game);
      }
      return ResolvedDocument(
        remotePath: resource.remotePath,
        renderType: _documentRenderTypeForFormat(resource.format),
        label: resource.title,
      );
    }

    final String? localPath = await cacheDocument(resource.remotePath);
    if (localPath == null) {
      return null;
    }
    return ResolvedDocument(
      remotePath: resource.remotePath,
      renderType: _documentRenderTypeForFormat(resource.format),
      label: resource.title,
    );
  }

  DocumentRenderType _documentRenderTypeForFormat(
    DesktopLibraryResourceFormat format,
  ) {
    switch (format) {
      case DesktopLibraryResourceFormat.pdf:
        return DocumentRenderType.pdf;
      case DesktopLibraryResourceFormat.html:
        return DocumentRenderType.html;
      case DesktopLibraryResourceFormat.text:
        return DocumentRenderType.text;
      case DesktopLibraryResourceFormat.image:
        return DocumentRenderType.image;
      case DesktopLibraryResourceFormat.markdown:
        return DocumentRenderType.markdown;
      case DesktopLibraryResourceFormat.other:
        return DocumentRenderType.text;
    }
  }

  Future<String?> downloadLibraryResource({
    required DesktopLibraryResource resource,
    required String directoryPath,
  }) async {
    if (kIsWeb || directoryPath.trim().isEmpty) {
      return null;
    }
    final CachedAsset? cached = await _remoteAssetService.ensureCached(
      sources: _assetSourceConfigs,
      remotePath: resource.remotePath,
      forceRefresh: true,
      allowCachedFallback: false,
    );
    if (cached == null || !cached.exists) {
      return null;
    }
    final File source = File(cached.localPath);
    if (!await source.exists()) {
      return null;
    }

    final Directory directory = Directory(directoryPath.trim());
    await directory.create(recursive: true);
    final String fileName = _downloadFileName(resource);
    if (fileName.isEmpty) {
      return null;
    }
    final File destination = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    if (source.absolute.path.toLowerCase() ==
        destination.absolute.path.toLowerCase()) {
      return destination.path;
    }
    await source.copy(destination.path);
    return destination.path;
  }

  String _safeDownloadFileName(String fileName) {
    final String sanitized = fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceFirst(RegExp(r'[ .]+$'), '')
        .trim();
    return sanitized.isEmpty ? 'library-resource' : sanitized;
  }

  /// Builds the user-facing download name from the same localized metadata
  /// shown in the desktop library card instead of exposing the WebDAV stem.
  ///
  /// The resource list may have been loaded before the user switched language,
  /// so the current [GameInfo] is resolved by slug at download time. This
  /// keeps the file name in sync with the language currently displayed by the
  /// app without requiring another remote index request.
  String _downloadFileName(DesktopLibraryResource resource) {
    final GameInfo? game = _games
        .where((GameInfo item) => item.slug == resource.gameSlug)
        .cast<GameInfo?>()
        .firstWhere((GameInfo? item) => item != null, orElse: () => null);
    final String gameTitle =
        (game?.title.trim().isNotEmpty == true
                ? game!.title
                : resource.gameTitle)
            .trim();
    final String resourceTitle = _localizedLibraryResourceTitle(resource);
    final String extension = _fileExtension(resource.fileName);
    final String stem = gameTitle.isEmpty
        ? resourceTitle
        : '$gameTitle · $resourceTitle';
    return _safeDownloadFileName('$stem$extension');
  }

  String _localizedLibraryResourceTitle(DesktopLibraryResource resource) {
    final bool isChinese = _language == AppLanguage.zhHans;
    switch (resource.type) {
      case DesktopLibraryResourceType.rulebook:
        return isChinese ? '规则书' : 'Rulebook';
      case DesktopLibraryResourceType.faq:
        return 'FAQ';
      case DesktopLibraryResourceType.assetIndex:
        return isChinese ? '资料索引' : 'Asset index';
      case DesktopLibraryResourceType.reference:
        return isChinese ? '规则参考' : 'Rules reference';
      case DesktopLibraryResourceType.playerAid:
        return isChinese ? '玩家辅助' : 'Player aid';
      case DesktopLibraryResourceType.supplement:
        return isChinese ? '补充资料' : 'Supplement';
      case DesktopLibraryResourceType.other:
        final String fallback = resource.title.trim();
        return fallback.isEmpty ? (isChinese ? '资料' : 'Resource') : fallback;
    }
  }

  String _fileExtension(String fileName) {
    final String normalized = fileName.trim();
    final int dot = normalized.lastIndexOf('.');
    if (dot <= 0 || dot == normalized.length - 1) {
      return '';
    }
    return normalized.substring(dot);
  }
}
