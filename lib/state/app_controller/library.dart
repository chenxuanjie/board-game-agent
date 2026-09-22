part of '../app_controller.dart';

extension AppLibraryController on AppController {
  Future<void> prefetchHomeImages() async {
    final imagePaths = <String>{
      for (final game in games) ...[
        game.coverAssetPath,
        game.bannerAssetPath,
        ...game.galleryAssetPaths,
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

  /// Loads the persisted index first, then checks the authoritative WebDAV
  /// manifests in the background. A single in-flight request is shared by all
  /// callers so opening the page and pressing refresh cannot race each other.
  /// Existing cached rows stay visible while this network request runs.
  Future<void> refreshLibraryResources({bool force = false}) {
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

    final Future<void> future = _refreshLibraryResources(generation);
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

  Future<void> _refreshLibraryResources(int generation) async {
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
      final _RemoteLibraryIndexResult index = await _loadRemoteLibraryIndex();
      if (generation != _libraryRefreshGeneration) {
        return;
      }

      final List<DesktopLibraryResource> remoteResources =
          _localizeLibraryResources(index.resources);
      final List<DesktopLibraryResource> nextResources =
          _mergePartialLibraryResources(remoteResources, index.failedSlugs);
      final bool changed = !_sameLibraryIndex(_libraryResources, nextResources);
      if (changed || _libraryResources.isEmpty) {
        _libraryResources = nextResources;
        try {
          await _preferencesService.saveDesktopLibraryResources(
            _libraryResources,
          );
        } catch (error) {
          // A persistence failure must not turn a successful remote request
          // into a false network failure. The next launch can retry caching.
          debugPrint(
            '[assets] desktop library index cache write failed: $error',
          );
        }
      }
      _libraryLoadState = index.resources.isEmpty
          ? LibraryLoadState.empty
          : LibraryLoadState.success;
      _libraryLoadError = index.warning;
      if (index.failedSlugs.isNotEmpty && index.warning != null) {
        _recordLibraryLoadFailure(index.warning!);
      }
    } catch (error) {
      if (generation != _libraryRefreshGeneration) {
        return;
      }
      if (_libraryResources.isEmpty) {
        _libraryResources = _buildBundledLibraryResources();
      }
      _libraryLoadState = LibraryLoadState.failure;
      _libraryLoadError = _safeStatusError(error);
      _recordLibraryLoadFailure(_libraryLoadError!);
      debugPrint('[assets] desktop library index unavailable: $error');
    }
    _notifyListeners();
  }

  /// Restores only index metadata. The actual PDF/Markdown/HTML bytes remain
  /// in [RemoteAssetService]'s document cache and are never read here.
  Future<void> _ensureLibraryCacheLoaded() {
    if (_libraryCacheLoadAttempted) {
      return Future<void>.value();
    }
    final Future<void>? active = _libraryCacheLoadFuture;
    if (active != null) {
      return active;
    }

    final Future<void> future = () async {
      try {
        final List<DesktopLibraryResource> cached = await _preferencesService
            .loadDesktopLibraryResources();
        if (cached.isNotEmpty) {
          _libraryResources = _localizeLibraryResources(cached);
          _libraryLoadState = LibraryLoadState.success;
        }
      } catch (error) {
        debugPrint('[assets] desktop library index cache read failed: $error');
      } finally {
        _libraryCacheLoadAttempted = true;
      }
    }();
    _libraryCacheLoadFuture = future;
    return future.whenComplete(() {
      if (identical(_libraryCacheLoadFuture, future)) {
        _libraryCacheLoadFuture = null;
      }
    });
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

  void _refreshLibraryGameTitles() {
    if (_libraryResources.isEmpty) {
      return;
    }
    _libraryResources = _localizeLibraryResources(_libraryResources);
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

  List<DesktopLibraryResource> _mergePartialLibraryResources(
    List<DesktopLibraryResource> remoteResources,
    Set<String> failedSlugs,
  ) {
    if (failedSlugs.isEmpty || _libraryResources.isEmpty) {
      return remoteResources;
    }
    final Set<String> remotePaths = <String>{
      for (final DesktopLibraryResource resource in remoteResources)
        resource.remotePath,
    };
    final List<DesktopLibraryResource> merged = <DesktopLibraryResource>[
      ...remoteResources,
      for (final DesktopLibraryResource resource in _libraryResources)
        if (failedSlugs.contains(resource.gameSlug) &&
            remotePaths.add(resource.remotePath))
          resource,
    ];
    merged.sort(_compareLibraryResources);
    return List<DesktopLibraryResource>.unmodifiable(merged);
  }

  /// Reads the authoritative per-game `manifest.json` files from WebDAV.
  ///
  /// A manifest is small metadata, not a document download. The actual PDF or
  /// Markdown bytes are fetched only when the user opens or downloads one
  /// resource. The remote catalog is used only to discover games that are not
  /// present in the bundled catalog yet.
  Future<_RemoteLibraryIndexResult> _loadRemoteLibraryIndex() async {
    final List<String> slugs = await _remoteLibraryGameSlugs();
    if (slugs.isEmpty) {
      throw StateError('远端资料库没有可检查的游戏资料');
    }

    final List<DesktopLibraryResource> resources = <DesktopLibraryResource>[];
    final List<String> failedSlugs = <String>[];
    int loadedManifestCount = 0;

    await Future.wait<void>(
      slugs.map((String slug) async {
        final String path = 'assets/games/$slug/manifest.json';
        try {
          final String? source = await _remoteAssetService.fetchRemoteText(
            sources: _assetSourceConfigs,
            remotePath: path,
          );
          if (source == null || source.trim().isEmpty) {
            failedSlugs.add(slug);
            return;
          }
          final Map<String, dynamic> manifest =
              jsonDecode(source) as Map<String, dynamic>;
          resources.addAll(_parseRemoteManifestResources(slug, manifest));
          loadedManifestCount += 1;
        } catch (error) {
          failedSlugs.add(slug);
          debugPrint('[assets] manifest unavailable for $slug: $error');
        }
      }),
    );

    if (loadedManifestCount == 0) {
      // If a legacy remote library has no manifests, retain the existing
      // bounded directory walk as a compatibility fallback.
      final List<RemoteAssetFile> files = await _remoteAssetService
          .listFilesRecursively(
            sources: _assetSourceConfigs,
            remotePath: 'assets/games',
          );
      final List<DesktopLibraryResource> fallback =
          _buildRemoteLibraryResources(files);
      if (fallback.isEmpty) {
        throw StateError('远端资料库为空或格式不可识别');
      }
      return _RemoteLibraryIndexResult(
        resources: fallback,
        warning: '远端未提供标准 manifest，已使用目录清单。',
      );
    }

    final Map<String, DesktopLibraryResource> unique =
        <String, DesktopLibraryResource>{};
    for (final DesktopLibraryResource resource in resources) {
      unique[resource.remotePath] = resource;
    }
    final List<DesktopLibraryResource> normalized = unique.values.toList()
      ..sort(_compareLibraryResources);
    final String? warning = failedSlugs.isEmpty
        ? null
        : '已有 $loadedManifestCount 个游戏资料同步，${failedSlugs.length} 个资料暂不可用。';
    return _RemoteLibraryIndexResult(
      resources: List<DesktopLibraryResource>.unmodifiable(normalized),
      warning: warning,
      failedSlugs: Set<String>.unmodifiable(failedSlugs),
    );
  }

  Future<List<String>> _remoteLibraryGameSlugs() async {
    final Set<String> slugs = <String>{
      for (final GameInfo game in _games) game.slug,
    };
    try {
      final String? source = await _remoteAssetService.fetchRemoteText(
        sources: _assetSourceConfigs,
        remotePath: 'assets/catalog.json',
      );
      if (source != null && source.trim().isNotEmpty) {
        final Map<String, dynamic> catalog =
            jsonDecode(source) as Map<String, dynamic>;
        final List<dynamic> games =
            catalog['games'] as List<dynamic>? ?? const <dynamic>[];
        for (final dynamic entry in games) {
          if (entry is! Map<String, dynamic> || entry['enabled'] == false) {
            continue;
          }
          final String? slug = entry['slug'] as String?;
          if (slug != null && _isSafeGameSlug(slug)) {
            slugs.add(slug);
          }
        }
      }
    } catch (error) {
      debugPrint(
        '[assets] remote catalog unavailable for library index: $error',
      );
    }
    final List<String> sorted = slugs.toList();
    sorted.sort();
    return sorted;
  }

  bool _isSafeGameSlug(String slug) {
    return slug.isNotEmpty && RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(slug);
  }

  List<DesktopLibraryResource> _parseRemoteManifestResources(
    String slug,
    Map<String, dynamic> manifest,
  ) {
    final GameInfo? localGame = _games
        .where((GameInfo game) => game.slug == slug)
        .cast<GameInfo?>()
        .firstWhere((GameInfo? game) => game != null, orElse: () => null);
    final String gameTitle =
        localGame?.title ?? _remoteManifestTitle(manifest, slug);
    final List<dynamic> entries =
        manifest['resources'] as List<dynamic>? ?? const <dynamic>[];
    final List<DesktopLibraryResource> resources = <DesktopLibraryResource>[];

    for (final dynamic raw in entries) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final String relativePath = (raw['path'] as String? ?? '')
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '')
          .trim();
      final String status = (raw['status'] as String? ?? 'unknown').trim();
      if (relativePath.isEmpty ||
          relativePath.split('/').contains('..') ||
          relativePath.startsWith('/') ||
          !_isDisplayableManifestStatus(status) ||
          raw['enabled'] == false) {
        continue;
      }
      // The resource-management skill explicitly excludes unclassified raw
      // material from runtime reading, caching, and download operations.
      final String relativeLower = relativePath.toLowerCase();
      if (relativeLower.startsWith('docs/others/')) {
        continue;
      }
      if (!relativePath.startsWith('docs/')) {
        continue;
      }

      final String remotePath = 'assets/games/$slug/$relativePath';
      final String documentType = raw['documentType'] as String? ?? '';
      final String languageCode = raw['language'] as String? ?? '';
      final String sourceClass = raw['sourceClass'] as String? ?? 'unknown';
      resources.add(
        DesktopLibraryResource(
          id: (raw['id'] as String?)?.trim().isNotEmpty == true
              ? raw['id'] as String
              : 'remote:$remotePath',
          gameSlug: slug,
          gameTitle: gameTitle,
          remotePath: remotePath,
          title: _libraryResourceTitle(
            relativePath,
            documentType: documentType,
          ),
          language: _libraryResourceLanguage(
            relativePath,
            explicitCode: languageCode,
          ),
          type: _libraryResourceType(relativePath, documentType: documentType),
          format: _libraryResourceFormat(relativePath),
          isRemote: true,
          status: status,
          enabled: raw['enabled'] as bool? ?? true,
          sourceClass: sourceClass,
        ),
      );
    }
    return resources;
  }

  String _remoteManifestTitle(Map<String, dynamic> manifest, String slug) {
    final Map<String, dynamic>? game = manifest['game'] is Map<String, dynamic>
        ? manifest['game'] as Map<String, dynamic>
        : null;
    final Map<String, dynamic>? titles = game?['title'] is Map<String, dynamic>
        ? game!['title'] as Map<String, dynamic>
        : null;
    final String? localized =
        titles?['cn'] as String? ??
        titles?['zhHans'] as String? ??
        titles?['en'] as String?;
    return localized?.trim().isNotEmpty == true ? localized!.trim() : slug;
  }

  List<DesktopLibraryResource> _buildRemoteLibraryResources(
    List<RemoteAssetFile> files,
  ) {
    final Map<String, GameInfo> gamesBySlug = <String, GameInfo>{
      for (final GameInfo game in _games) game.slug: game,
    };
    final Map<String, DesktopLibraryResource> unique =
        <String, DesktopLibraryResource>{};

    for (final RemoteAssetFile file in files) {
      final String normalized = file.remotePath
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');
      final RegExpMatch? match = RegExp(
        r'^assets/games/([^/]+)/docs/(.+)$',
      ).firstMatch(normalized);
      if (match == null) {
        continue;
      }
      final String relative = match.group(2)!;
      final String lower = normalized.toLowerCase();
      final String relativeLower = relative.toLowerCase();
      if (lower.contains('/tmp/') ||
          relativeLower.startsWith('.') ||
          relativeLower.startsWith('others/')) {
        continue;
      }

      final String slug = match.group(1)!;
      final GameInfo? game = gamesBySlug[slug];
      final String gameTitle = game == null ? slug : game.title;
      final DesktopLibraryResource resource = DesktopLibraryResource(
        id: 'remote:$normalized',
        gameSlug: slug,
        gameTitle: gameTitle,
        remotePath: normalized,
        title: _libraryResourceTitle(relative),
        language: _libraryResourceLanguage(relative),
        type: _libraryResourceType(relative),
        format: _libraryResourceFormat(relative),
        isRemote: true,
      );
      unique[normalized] = resource;
    }

    final List<DesktopLibraryResource> resources = unique.values.toList();
    resources.sort(_compareLibraryResources);
    return List<DesktopLibraryResource>.unmodifiable(resources);
  }

  List<DesktopLibraryResource> _buildBundledLibraryResources() {
    final List<DesktopLibraryResource> resources = <DesktopLibraryResource>[];
    final Set<String> paths = <String>{};
    int fallbackIndex = 0;

    for (final GameInfo game in _games) {
      final List<String> candidates = <String>[
        game.rulebookAssetPath,
        game.faqAssetPath,
        ...game.knowledgeAssetPaths,
      ];
      for (final String path in candidates) {
        final String normalized = path.replaceAll('\\', '/').trim();
        if (normalized.isEmpty || !paths.add(normalized)) {
          continue;
        }
        final bool isRulebook = path == game.rulebookAssetPath;
        final bool isFaq = path == game.faqAssetPath;
        final String relative = normalized.contains('/docs/')
            ? normalized.split('/docs/').last
            : normalized.split('/').last;
        resources.add(
          DesktopLibraryResource(
            // Keep the first two compatibility ids stable for existing
            // desktop automation while remote entries use their full path.
            id: '$fallbackIndex',
            gameSlug: game.slug,
            gameTitle: game.title,
            remotePath: normalized,
            title: _libraryResourceTitle(
              relative,
              documentType: isRulebook
                  ? 'rulebook'
                  : isFaq
                  ? 'faq'
                  : null,
            ),
            language: _libraryResourceLanguage(relative),
            type: _libraryResourceType(
              relative,
              documentType: isRulebook
                  ? 'rulebook'
                  : isFaq
                  ? 'faq'
                  : null,
            ),
            format: _libraryResourceFormat(relative),
            isRemote: false,
          ),
        );
        fallbackIndex += 1;
      }
    }
    return List<DesktopLibraryResource>.unmodifiable(resources);
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

  bool _isDisplayableManifestStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'available':
      case 'unverified':
      case 'needs_review':
      case 'unknown':
        return true;
      case 'missing':
      case 'superseded':
      case 'blocked':
        return false;
      default:
        // Newer manifest versions may add a non-terminal status. Keep it
        // visible rather than silently hiding a resource the server can list.
        return true;
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
