part of '../app_controller.dart';

extension AppAiConfigurationController on AppController {
  Future<void> saveAiApiConfig(AiApiConfig next) async {
    final AiApiConfig previous = _aiApiConfig;
    final bool runContextChanged = _aiRunContextChanged(previous, next);
    _invalidateActiveRuns();
    _aiApiConfig = next;
    if (runContextChanged) {
      // A response id, compaction snapshot, and activity timeline belong to
      // one provider/model context. Keep the conversation messages, but do
      // not show or reuse a Run produced by an incompatible endpoint.
      _clearIncompatibleRunState();
    }
    _aiConnectivityStatus = ConnectivityStatus.unknown(
      next.baseUrl.trim().isEmpty || next.apiKey.trim().isEmpty
          ? '未配置 AI 服务'
          : '等待检查',
    );
    invalidateAiModels();
    await _preferencesService.saveAiApiConfig(next);
    if (_isSaveableCustomPreset(next)) {
      _customAiPresets = _upsertCustomPreset(_customAiPresets, next);
      await _preferencesService.saveAiCustomPresets(_customAiPresets);
    }
    if (runContextChanged) {
      _queueConversationSave();
    }
    _notifyListeners();
  }

  /// Selects the model used by subsequent assistant runs.
  ///
  /// Keeping this operation at the controller boundary ensures the desktop
  /// composer, settings and any future platform UI share the same persistence,
  /// model-cache invalidation and active-run isolation behavior.
  Future<void> setAiModel(String model) async {
    final String normalized = model.trim();
    if (normalized.isEmpty || normalized == _aiApiConfig.model.trim()) {
      return;
    }
    await saveAiApiConfig(_aiApiConfig.copyWith(model: normalized));
  }

  /// Selects the reasoning effort sent to providers that support it.
  ///
  /// Automatic deliberately omits the optional request field, preserving
  /// compatibility with OpenAI-compatible providers that do not implement it.
  Future<void> setAiReasoningEffort(AiReasoningEffort effort) async {
    if (_aiApiConfig.reasoningEffort == effort) return;
    await saveAiApiConfig(_aiApiConfig.copyWith(reasoningEffort: effort));
  }

  bool _aiRunContextChanged(AiApiConfig previous, AiApiConfig next) {
    return previous.name.trim() != next.name.trim() ||
        previous.baseUrl.trim() != next.baseUrl.trim() ||
        previous.apiKey.trim() != next.apiKey.trim() ||
        previous.model.trim() != next.model.trim() ||
        previous.apiKeyHeader.trim() != next.apiKeyHeader.trim() ||
        previous.chatPath.trim() != next.chatPath.trim() ||
        previous.reasoningEffort != next.reasoningEffort ||
        previous.responseSpeed != next.responseSpeed;
  }

  void _clearIncompatibleRunState() {
    for (final AiConversation conversation in _conversations.values) {
      conversation.lastRun = null;
    }
    for (final _ChatGenerationState generation in _generationStates.values) {
      generation
        ..runEvents.clear()
        ..runId = null
        ..contextKey = null
        ..runStartedAt = null
        ..runCompletedAt = null
        ..runStatus = null
        ..runResult = null
        ..runSequence = 0
        ..syntheticRun = false
        ..checkpointRestored = true;
    }
    _runExpandedByContext.clear();
  }

  bool _isSaveableCustomPreset(AiApiConfig config) {
    return config.providerPreset == AiProviderPreset.custom &&
        config.normalizedName.isNotEmpty &&
        !AiApiConfig.isBuiltInProviderName(config.name);
  }

  List<AiApiConfig> _upsertCustomPreset(
    Iterable<AiApiConfig> existing,
    AiApiConfig next,
  ) {
    final List<AiApiConfig> result = List<AiApiConfig>.from(existing);
    final int index = result.indexWhere(
      (AiApiConfig item) => item.normalizedName == next.normalizedName,
    );
    if (index == -1) {
      result.add(next);
    } else {
      result[index] = next;
    }
    return result;
  }

  Future<List<AiModel>> refreshAiModels({
    AiApiConfig? config,
    bool persistSelection = false,
  }) {
    final AiApiConfig target = config ?? _aiApiConfig;
    final String signature = _aiModelSignature(target);
    final Future<List<AiModel>>? active = _aiModelRefreshFuture;
    if (active != null && _aiModelRefreshSignature == signature) {
      return active;
    }

    final int generation = ++_aiModelRefreshGeneration;
    _aiModelRefreshSignature = signature;
    _aiModelLoadState = AiModelLoadState.loading;
    _aiModelLoadError = null;
    _notifyListeners();

    final Future<List<AiModel>> future = _aiService
        .listModels(target)
        .then((List<AiModel> models) async {
          if (generation != _aiModelRefreshGeneration) {
            return models;
          }
          _availableAiModels = List<AiModel>.from(models);
          _aiModelLoadState = models.isEmpty
              ? AiModelLoadState.empty
              : AiModelLoadState.success;
          _aiModelLoadError = null;
          if (persistSelection && identical(config, null)) {
            final String selected = _aiApiConfig.model.trim();
            final bool stillAvailable = models.any(
              (AiModel model) => model.id == selected,
            );
            if (selected.isNotEmpty && !stillAvailable) {
              _aiApiConfig = _aiApiConfig.copyWith(model: '');
              await _preferencesService.saveAiApiConfig(_aiApiConfig);
            }
          }
          _notifyListeners();
          return models;
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (generation != _aiModelRefreshGeneration) {
            return Future<List<AiModel>>.error(error, stackTrace);
          }
          final bool empty =
              error is AiProtocolException &&
              error.message.toLowerCase().contains('empty model list');
          _aiModelLoadState = empty
              ? AiModelLoadState.empty
              : AiModelLoadState.failure;
          _aiModelLoadError = _safeStatusError(error);
          _availableAiModels = <AiModel>[];
          _notifyListeners();
          return Future<List<AiModel>>.error(error, stackTrace);
        });
    _aiModelRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_aiModelRefreshFuture, future)) {
            _aiModelRefreshFuture = null;
            _aiModelRefreshSignature = null;
          }
        })
        .catchError((Object _) => <AiModel>[]);
    return future;
  }

  Future<void> _refreshAiModelsOnInitialize() async {
    try {
      await refreshAiModels(persistSelection: true);
    } catch (_) {
      // The settings screen exposes the retryable failure state.
    }
  }

  void invalidateAiModels() {
    ++_aiModelRefreshGeneration;
    _aiModelRefreshFuture = null;
    _aiModelRefreshSignature = null;
    _availableAiModels = <AiModel>[];
    _aiModelLoadState = AiModelLoadState.idle;
    _aiModelLoadError = null;
    _notifyListeners();
  }

  String _aiModelSignature(AiApiConfig config) {
    return '${config.baseUrl.trim()}\n${config.apiKey.trim()}';
  }

  Future<void> saveAssetSourceConfigs(List<AssetSourceConfig> next) async {
    _assetSourceConfigs = List<AssetSourceConfig>.from(next);
    await _preferencesService.saveAssetSourceConfigs(_assetSourceConfigs);
    for (final source in _assetSourceConfigs) {
      _assetSourceStatuses.putIfAbsent(
        source.id,
        () => ConnectivityStatus.unknown('未检测'),
      );
    }
    _notifyListeners();
  }

  Future<String> testAiApiConfig(AiApiConfig config) async {
    final result = await _aiService.checkConnection(config);
    if (result.success) {
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.success,
        message: copy.aiApiTestSuccess,
        checkedAt: DateTime.now(),
      );
      debugPrint('[ai] ${_aiConnectivityStatus.message}');
      _notifyListeners();
      return copy.aiApiTestSuccess;
    }

    final String message = '连接失败: ${_safeStatusError(result.message)}';
    _aiConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.failure,
      message: message,
      checkedAt: DateTime.now(),
    );
    debugPrint('[ai] $message');
    _notifyListeners();
    return message;
  }
}
