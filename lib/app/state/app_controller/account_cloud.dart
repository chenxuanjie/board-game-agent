part of '../app_controller.dart';

extension AppAccountCloudController on AppController {
  /// A short local barrier prevents user mutations from interleaving with a
  /// journal commit and its projection. Network calls run outside this barrier.
  Future<T> accountCloudTransaction<T>(
    String scope,
    Future<T> Function(
      AccountEntities current,
      Future<void> Function(AccountEntities) project,
    )
    work,
  ) => _accountDataTransaction(scope, work, reactionsOnly: false);

  /// Reactions touch only their own durable stores. An active AI response does
  /// not delay publication or get replaced by a public projection.
  Future<T> accountCloudReactionTransaction<T>(
    String scope,
    Future<T> Function(
      AccountEntities current,
      Future<void> Function(AccountEntities) project,
    )
    work,
  ) => _accountDataTransaction(scope, work, reactionsOnly: true);

  Future<T> _accountDataTransaction<T>(
    String scope,
    Future<T> Function(
      AccountEntities current,
      Future<void> Function(AccountEntities) project,
    )
    work, {
    required bool reactionsOnly,
  }) async {
    do {
      await waitForAccountCloudData(scope, reactionsOnly: reactionsOnly);
    } while (_accountCloudWork != null ||
        _switchingIdentityScope ||
        _accountReactionCommit);
    final done = Completer<void>();
    _accountCloudWork = done.future;
    if (reactionsOnly) {
      _accountReactionCommit = true;
    } else {
      _switchingIdentityScope = true;
    }
    _notifyListeners();
    try {
      await Future.wait<void>([
        if (!reactionsOnly) _conversationSaveQueue,
        _favoriteMutationQueue,
        if (!reactionsOnly) _recentGamesMutationQueue,
        if (!reactionsOnly) _searchHistoryMutationQueue,
        if (!reactionsOnly) _dailyRecommendationSaveQueue,
        if (!reactionsOnly) _selectedConversationSaveQueue,
        _preferencesService.drainPersonalWrites(),
      ]).timeout(const Duration(seconds: 15));
      if (!reactionsOnly && _conversationDirty) {
        await _persistConversations(throwOnError: true);
      }
      void check() {
        if (_controllerDisposed ||
            identityUserId != scope ||
            _identityScopeRequests > 0) {
          throw StateError('账号已切换');
        }
      }

      check();
      final current = reactionsOnly
          ? await _readCloudReactions()
          : await _readCloudEntities(scope);
      return await work(current, (entities) async {
        check();
        if (reactionsOnly) {
          await _projectCloudReactions(entities);
        } else {
          await _projectCloudEntities(scope, entities, current);
        }
        check();
      });
    } finally {
      done.complete();
      _accountCloudWork = null;
      _accountReactionCommit = false;
      if (!reactionsOnly) _switchingIdentityScope = _identityScopeRequests > 0;
      _notifyListeners();
    }
  }

  Future<void> waitForAccountCloudData(
    String scope, {
    bool reactionsOnly = false,
  }) async {
    // The two network lanes share only this short local commit barrier.
    // Waiting for another commit is normal scheduling, not a sync failure.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    bool idle() => reactionsOnly
        ? !_controllerDisposed &&
              !_switchingIdentityScope &&
              !_accountReactionCommit &&
              !_gameVotes.saving &&
              !(_nationalDayList?.saving ?? false)
        : accountCloudIdle;
    while (!idle() || _accountCloudWork != null) {
      if (_controllerDisposed ||
          identityUserId != scope ||
          _identityScopeRequests > 0) {
        throw StateError('账号已切换');
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) throw TimeoutException('本机数据仍在保存');
      final ready = Completer<void>();
      void changed() {
        if (!ready.isCompleted) ready.complete();
      }

      addListener(changed);
      try {
        await ready.future.timeout(remaining);
      } finally {
        removeListener(changed);
      }
    }
    if (identityUserId != scope || _controllerDisposed) {
      throw StateError('账号已切换');
    }
  }

  Future<AccountEntities> _readCloudReactions() async {
    final result = <String, Map<String, Object?>>{};
    for (final favorite in await _preferencesService.loadFavoriteGames()) {
      result['favorite|${favorite.gameSlug}'] = favorite.toMap();
    }
    final ballot = await _preferencesService.loadGameVoteCache();
    if (ballot != null) {
      for (final slug in GameVoteCache.decode(ballot).ballot.games) {
        result['vote|$slug'] = {
          'slug': slug,
          'campaign': GameVoteBallot.campaign,
        };
      }
    }
    return result;
  }

  Future<void> _projectCloudReactions(AccountEntities entities) async {
    final favorites = <FavoriteGameRecord>[], votes = <String>[];
    for (final entry in entities.entries) {
      if (entry.key.startsWith('favorite|')) {
        final record = FavoriteGameRecord.tryFromMap(entry.value);
        if (record == null || entry.key != 'favorite|${record.gameSlug}') {
          throw const FormatException('云端收藏格式错误');
        }
        favorites.add(record);
      } else if (entry.key.startsWith('vote|')) {
        final slug = entry.key.substring(5);
        if (!GameVoteBallot.slugPattern.hasMatch(slug) ||
            entry.value['slug'] != slug ||
            entry.value['campaign'] != GameVoteBallot.campaign) {
          throw const FormatException('云端投票格式错误');
        }
        votes.add(slug);
      }
    }
    if (favorites.length > 2048 || votes.length > 256) {
      throw const FormatException('云端收藏或投票数量超过上限');
    }
    await _gameVotes.load();
    final raw = await _preferencesService.loadGameVoteCache();
    if (raw == null) throw const FormatException('本机投票缓存未初始化');
    final cache = GameVoteCache.decode(raw);
    favorites.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _preferencesService.saveFavoriteGames(favorites);
    await _preferencesService.saveGameVoteCache(
      GameVoteCache(
        ballot: GameVoteBallot(deviceId: cache.ballot.deviceId, games: votes),
        remoteCounts: cache.remoteCounts,
        lastScope: cache.lastScope,
      ).encode(),
    );
    await _gameVotes.reload();
    _favoriteRecordsLoaded = false;
    await _ensureFavoriteRecords();
  }

  Future<AccountEntities> _readCloudEntities(String scope) async {
    final result = <String, Map<String, Object?>>{};
    for (final favorite in await _preferencesService.loadFavoriteGames()) {
      result['favorite|${favorite.gameSlug}'] = favorite.toMap();
    }
    for (final recent in await _preferencesService.loadRecentGames()) {
      result['recent|${recent.gameSlug}'] = recent.toMap();
    }
    final ballot = await _preferencesService.loadGameVoteCache();
    if (ballot != null) {
      for (final slug in GameVoteCache.decode(ballot).ballot.games) {
        result['vote|$slug'] = {
          'slug': slug,
          'campaign': GameVoteBallot.campaign,
        };
      }
    }
    final list = await _preferencesService.loadNationalDayGameSlugs();
    if (list != null) {
      result['seasonalList|${GameVoteBallot.campaign}'] = {'slugs': list};
    }
    for (final record in await _preferencesService.loadSearchHistory()) {
      result['search|${sha256Json(record.normalizedQuery)}'] = record.toMap();
    }
    for (final record in await _preferencesService.loadDailyRecommendations()) {
      result['recommendation|${record.date}'] = record.toMap();
    }
    for (final entry
        in (await _preferencesService.accountCloudPreferences()).entries) {
      result['preference|${entry.key}'] = {'value': entry.value};
    }
    final prefs = await SharedPreferences.getInstance();
    final nickname = prefs.getString('identity.profile.$scope.nickname');
    if (nickname != null) result['nickname|profile'] = {'value': nickname};
    final raw = await _conversationStore.load();
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final conversations = data['conversations'];
      if (conversations is! Map) throw const FormatException('对话存储损坏');
      for (final entry in conversations.entries) {
        final payload = Map<String, Object?>.from(entry.value as Map)
          ..remove('lastRun');
        if (payload['id'] != entry.key) {
          throw const FormatException('对话 ID 不匹配');
        }
        AiConversation.fromMap(Map<String, dynamic>.from(payload));
        result['conversation|${entry.key}'] = payload;
      }
    }
    return result;
  }

  Future<void> _projectCloudEntities(
    String scope,
    AccountEntities entities,
    AccountEntities before,
  ) async {
    final favorites = <FavoriteGameRecord>[], recent = <RecentGameRecord>[];
    final preferences = <String, Object>{},
        conversations = <String, Map<String, dynamic>>{};
    String? nickname;
    final votes = <String>[];
    List<String>? seasonalList;
    final searches = <SearchHistoryRecord>[];
    final recommendations = <DailyRecommendationRecord>[];
    // Validate the complete projection before writing any business store.
    for (final entry in entities.entries) {
      final split = entry.key.indexOf('|');
      final type = entry.key.substring(0, split),
          id = entry.key.substring(split + 1);
      final payload = Map<String, dynamic>.from(entry.value);
      switch (type) {
        case 'vote':
          if (!GameVoteBallot.slugPattern.hasMatch(id) ||
              payload['slug'] != id ||
              payload['campaign'] != GameVoteBallot.campaign) {
            throw const FormatException('云端投票格式错误');
          }
          votes.add(id);
        case 'seasonalList':
          final slugs = payload['slugs'];
          if (id != GameVoteBallot.campaign ||
              slugs is! List ||
              slugs.length > 256 ||
              slugs.any(
                (value) =>
                    value is! String ||
                    !GameVoteBallot.slugPattern.hasMatch(value),
              )) {
            throw const FormatException('云端清单格式错误');
          }
          seasonalList = slugs.cast<String>();
        case 'search':
          final record = SearchHistoryRecord.tryFromMap(payload);
          if (record == null ||
              record.query.length > 512 ||
              sha256Json(record.normalizedQuery) != id) {
            throw const FormatException('云端搜索记录格式错误');
          }
          searches.add(record);
        case 'recommendation':
          final record = DailyRecommendationRecord.tryFromMap(payload);
          if (record == null ||
              record.date != id ||
              record.gameIds.length != (payload['gameIds'] as List).length ||
              record.gameIds.length > 20) {
            throw const FormatException('云端推荐记录格式错误');
          }
          recommendations.add(record);
        case 'favorite':
          final record = FavoriteGameRecord.tryFromMap(payload);
          if (record == null || record.gameSlug != id) {
            throw const FormatException('云端收藏格式错误');
          }
          favorites.add(record);
        case 'recent':
          final record = RecentGameRecord.tryFromMap(payload);
          if (record == null || record.gameSlug != id) {
            throw const FormatException('云端浏览记录格式错误');
          }
          recent.add(record);
        case 'preference':
          if (!PreferencesService.accountCloudPreferenceKeys.contains(id) ||
              (id == 'voice_reply_enabled' ||
                      id == 'global_use_current_game_knowledge'
                  ? payload['value'] is! bool
                  : payload['value'] is! String)) {
            throw const FormatException('云端偏好格式错误');
          }
          preferences[id] = payload['value'] as Object;
        case 'nickname':
          if (id != 'profile' ||
              payload['value'] is! String ||
              (payload['value'] as String).length > 80) {
            throw const FormatException('云端昵称格式错误');
          }
          nickname = payload['value'] as String;
        case 'conversation':
          if (payload['id'] != id ||
              payload['messages'] is! List ||
              payload.containsKey('lastRun')) {
            throw const FormatException('云端对话格式错误');
          }
          final parsed = AiConversation.fromMap(payload);
          if (parsed.messages.length != (payload['messages'] as List).length) {
            throw const FormatException('云端对话消息格式错误');
          }
          if (canonicalJson(before[entry.key]) == canonicalJson(entry.value)) {
            final checkpoint = _conversations[id]?.lastRun;
            if (checkpoint != null) payload['lastRun'] = checkpoint.toMap();
          }
          if (parsed.id != id) throw const FormatException('云端对话 ID 错误');
          conversations[id] = payload;
        default:
          throw const FormatException('未知云端数据类型');
      }
    }
    if (votes.length > 256 || favorites.length > 2048) {
      throw const FormatException('云端收藏或投票数量超过上限');
    }
    favorites.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    recent.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    await _preferencesService.saveFavoriteGames(favorites);
    await _preferencesService.saveRecentGames(recent);
    searches.sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    recommendations.sort((a, b) => b.date.compareTo(a.date));
    await _preferencesService.saveSearchHistory(searches);
    await _preferencesService.saveDailyRecommendations(
      recommendations.take(30).toList(),
    );
    if (seasonalList != null) {
      await _preferencesService.saveNationalDayGameSlugs(seasonalList);
    }
    await _gameVotes.load();
    final rawBallot = await _preferencesService.loadGameVoteCache();
    if (rawBallot == null) throw const FormatException('本机投票缓存未初始化');
    final cache = GameVoteCache.decode(rawBallot);
    await _preferencesService.saveGameVoteCache(
      GameVoteCache(
        ballot: GameVoteBallot(deviceId: cache.ballot.deviceId, games: votes),
        remoteCounts: cache.remoteCounts,
        lastScope: cache.lastScope,
      ).encode(),
    );
    await _gameVotes.reload();
    if (_nationalDayList != null) await _nationalDayList!.reload();
    await _preferencesService.applyAccountCloudPreferences(preferences);
    await _conversationStore.save(
      jsonEncode({
        'version': AppConversationController._conversationStoreVersion,
        'savedAt': DateTime.now().toIso8601String(),
        'selectedConversationId': _selectedConversationId,
        'conversations': conversations,
      }),
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = nickname == null
        ? await prefs.remove('identity.profile.$scope.nickname')
        : await prefs.setString('identity.profile.$scope.nickname', nickname);
    if (!saved) throw StateError('云端昵称保存失败');
    _favoriteRecordsLoaded = false;
    for (final id in _generationStates.keys.toList()) {
      if (canonicalJson(before['conversation|$id']) !=
          canonicalJson(entities['conversation|$id'])) {
        _generationStates.remove(id);
      }
    }
    _conversations.clear();
    await _reloadIdentityPersonalState();
  }
}
