part of '../app_controller.dart';

extension AppAiConfigurationController on AppController {
  Future<void> saveAiApiConfig(AiApiConfig next) async {
    final write = (_aiConfigSaveQueue ?? Future<void>.value()).then(
      (_) => _saveAiApiConfig(next),
    );
    _aiConfigSaveQueue = write.catchError((Object _) {});
    await write;
  }

  Future<void> _saveAiApiConfig(AiApiConfig next) async {
    final AiApiConfig previous = _aiApiConfig;
    // Publish config/clear Run state only after the durable write succeeds.
    await _preferencesService.saveAiApiConfig(next);
    ++_aiServiceStatusGeneration;
    _aiServiceStatusRefreshFuture = null;
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
    if (_aiModelSignature(previous) != _aiModelSignature(next)) {
      invalidateAiModels();
    }
    if (_isSaveableCustomPreset(next)) {
      final presets = _upsertCustomPreset(_customAiPresets, next);
      try {
        await _preferencesService.saveAiCustomPresets(presets);
        _customAiPresets = presets;
      } catch (error) {
        // The active config is already committed; preset history is secondary.
        debugPrint('[ai] preset history write failed: $error');
      }
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
  /// model selection and active-run isolation behavior.
  Future<void> setAiModel(String model) async {
    final String normalized = model.trim();
    if (normalized.isEmpty || normalized == _aiApiConfig.model.trim()) {
      return;
    }
    if (!AiModelPolicy.allowsModel(normalized)) {
      throw ArgumentError.value(
        model,
        'model',
        'Model is outside the GPT-5.6+ catalog',
      );
    }
    final List<AiReasoningEffort> supported = AiModelPolicy.reasoningEfforts(
      normalized,
    )!;
    await saveAiApiConfig(
      _aiApiConfig.copyWith(
        model: normalized,
        reasoningEffort: supported.contains(_aiApiConfig.reasoningEffort)
            ? _aiApiConfig.reasoningEffort
            : AiReasoningEffort.automatic,
      ),
    );
  }

  /// Selects the reasoning effort sent to providers that support it.
  ///
  /// Automatic deliberately omits the optional request field, preserving
  /// compatibility with OpenAI-compatible providers that do not implement it.
  Future<void> setAiReasoningEffort(AiReasoningEffort effort) async {
    if (_aiApiConfig.reasoningEffort == effort) return;
    final List<AiReasoningEffort>? supported = AiModelPolicy.reasoningEfforts(
      _aiApiConfig.model,
    );
    if (effort != AiReasoningEffort.automatic &&
        (supported == null || !supported.contains(effort))) {
      throw ArgumentError.value(
        effort,
        'effort',
        'Unsupported reasoning effort',
      );
    }
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

  Future<List<AiModel>> refreshAiModels({AiApiConfig? config}) {
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
          final List<AiModel> eligible = models
              .where((AiModel model) => AiModelPolicy.allowsModel(model.id))
              .toList(growable: false);
          _availableAiModels = eligible;
          _aiModelLoadState = eligible.isEmpty
              ? AiModelLoadState.empty
              : AiModelLoadState.success;
          _aiModelLoadError = null;
          // /models is discovery only. An unavailable or filtered model is
          // retained in preferences and blocked by the request policy.
          _notifyListeners();
          return eligible;
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
      await refreshAiModels();
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
