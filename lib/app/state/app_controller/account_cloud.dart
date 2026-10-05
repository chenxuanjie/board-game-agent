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
  ) async {
    if (identityUserId != scope ||
        !accountCloudIdle ||
        _accountCloudWork != null) {
      throw StateError('账号数据暂忙，请稍后同步');
    }
    final done = Completer<void>();
    _accountCloudWork = done.future;
    _switchingIdentityScope = true;
    _notifyListeners();
    try {
      await Future.wait<void>([
        _conversationSaveQueue,
        _favoriteMutationQueue,
        _recentGamesMutationQueue,
        _selectedConversationSaveQueue,
        _preferencesService.drainPersonalWrites(),
      ]).timeout(const Duration(seconds: 15));
      if (_conversationDirty) await _persistConversations(throwOnError: true);
      void check() {
        if (_controllerDisposed ||
            identityUserId != scope ||
            _identityScopeRequests > 0) {
          throw StateError('账号已切换');
        }
      }

      check();
      final current = await _readCloudEntities(scope);
      return await work(current, (entities) async {
        check();
        await _projectCloudEntities(scope, entities, current);
        check();
      });
    } finally {
      done.complete();
      _accountCloudWork = null;
      _switchingIdentityScope = _identityScopeRequests > 0;
      _notifyListeners();
    }
  }

  Future<AccountEntities> _readCloudEntities(String scope) async {
    final result = <String, Map<String, Object?>>{};
    for (final favorite in await _preferencesService.loadFavoriteGames()) {
      result['favorite|${favorite.gameSlug}'] = favorite.toMap();
    }
    for (final recent in await _preferencesService.loadRecentGames()) {
      result['recent|${recent.gameSlug}'] = recent.toMap();
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
    // Validate the complete projection before writing any business store.
    for (final entry in entities.entries) {
      final split = entry.key.indexOf('|');
      final type = entry.key.substring(0, split),
          id = entry.key.substring(split + 1);
      final payload = Map<String, dynamic>.from(entry.value);
      switch (type) {
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
    favorites.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    recent.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    await _preferencesService.saveFavoriteGames(favorites);
    await _preferencesService.saveRecentGames(recent);
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
