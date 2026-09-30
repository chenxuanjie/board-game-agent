part of '../app_controller.dart';

extension AppServiceStatusController on AppController {
  Future<void> refreshAssetAccessStatus() {
    final Future<void>? active = _assetStatusRefreshFuture;
    if (active != null) {
      return active;
    }
    final Future<void> future = _refreshAssetAccessStatus();
    _assetStatusRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_assetStatusRefreshFuture, future)) {
            _assetStatusRefreshFuture = null;
          }
        })
        .catchError((Object _) {});
    return future;
  }

  Future<void> _refreshAssetAccessStatus() async {
    final DateTime startedAt = DateTime.now();
    if (_games.isEmpty) {
      _assetSourceStatuses.clear();
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.unknown,
        message: '暂无游戏资料',
        checkedAt: startedAt,
      );
      _notifyListeners();
      return;
    }

    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.loading,
      message: '正在检查规则资料',
      checkedAt: startedAt,
    );
    for (final source in _assetSourceConfigs) {
      _assetSourceStatuses[source.id] = ConnectivityStatus(
        state: ConnectivityState.loading,
        message: '正在检查',
        checkedAt: startedAt,
      );
    }
    _notifyListeners();

    final Map<String, ConnectivityStatus> nextStatuses =
        <String, ConnectivityStatus>{};
    for (final source in _assetSourceConfigs) {
      try {
        final CachedAsset? asset = await _remoteAssetService.ensureCached(
          sources: <AssetSourceConfig>[source],
          remotePath: 'assets/games/${featuredGame.slug}/images/cover.jpg',
          forceRefresh: true,
          allowCachedFallback: false,
        );
        final ConnectivityStatus status = asset != null
            ? ConnectivityStatus(
                state: ConnectivityState.success,
                message: '图片拉取成功',
                checkedAt: DateTime.now(),
              )
            : ConnectivityStatus(
                state: ConnectivityState.failure,
                message: '图片拉取失败',
                checkedAt: DateTime.now(),
              );
        debugPrint('[assets] ${source.id} => ${status.message}');
        nextStatuses[source.id] = status;
      } catch (error) {
        final failureStatus = ConnectivityStatus(
          state: ConnectivityState.failure,
          message: '超时或失败',
          checkedAt: DateTime.now(),
        );
        debugPrint('[assets] ${source.id} => ${failureStatus.message}: $error');
        nextStatuses[source.id] = failureStatus;
      }
    }
    _assetSourceStatuses
      ..clear()
      ..addAll(nextStatuses);
    final int successCount = nextStatuses.values
        .where(
          (ConnectivityStatus status) =>
              status.state == ConnectivityState.success,
        )
        .length;
    final int failureCount = nextStatuses.values
        .where(
          (ConnectivityStatus status) =>
              status.state == ConnectivityState.failure,
        )
        .length;
    final ConnectivityState aggregateState;
    final String aggregateMessage;
    if (nextStatuses.isEmpty) {
      aggregateState = ConnectivityState.unknown;
      aggregateMessage = '未配置资料来源';
    } else if (successCount == 0) {
      aggregateState = ConnectivityState.failure;
      aggregateMessage = '规则资料访问失败';
    } else if (failureCount > 0) {
      aggregateState = ConnectivityState.warning;
      aggregateMessage = '部分资料来源可用';
    } else {
      aggregateState = ConnectivityState.success;
      aggregateMessage = '规则资料访问正常';
    }
    _assetConnectivityStatus = ConnectivityStatus(
      state: aggregateState,
      message: aggregateMessage,
      checkedAt: DateTime.now(),
    );
    _notifyListeners();
  }

  /// Refreshes every user-visible service status from its real endpoint.
  ///
  /// Model discovery validates the AI endpoint even before a model is chosen.
  /// When a model is selected, a small completion request is also issued so
  /// the status reflects the actual chat path rather than only `/models`.
  Future<void> refreshServiceStatuses() {
    final Future<void>? active = _serviceStatusRefreshFuture;
    if (active != null) {
      return active;
    }
    final Future<void> future = _refreshServiceStatuses();
    _serviceStatusRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_serviceStatusRefreshFuture, future)) {
            _serviceStatusRefreshFuture = null;
          }
        })
        .catchError((Object _) {});
    return future;
  }

  Future<void> _refreshServiceStatuses() async {
    final DateTime startedAt = DateTime.now();
    _aiConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.loading,
      message: '正在检查 AI 服务',
      checkedAt: startedAt,
    );
    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.loading,
      message: '正在检查规则资料',
      checkedAt: startedAt,
    );
    for (final source in _assetSourceConfigs) {
      _assetSourceStatuses[source.id] = ConnectivityStatus(
        state: ConnectivityState.loading,
        message: '正在检查',
        checkedAt: startedAt,
      );
    }
    _notifyListeners();

    try {
      await Future.wait<void>(<Future<void>>[
        refreshAiServiceStatus(),
        refreshAssetAccessStatus(),
      ]);
      _recordActivity(
        kind: AppActivityKind.serviceRefresh,
        title: copy.activityServiceRefreshTitle,
        message: copy.activityServiceRefreshMessage(
          _aiConnectivityStatus.message,
          _assetConnectivityStatus.message,
        ),
      );
    } catch (error) {
      _recordActivity(
        kind: AppActivityKind.serviceRefresh,
        title: copy.activityServiceRefreshFailedTitle,
        message: _safeStatusError(error),
      );
      rethrow;
    }
  }

  /// Refreshes the AI endpoint without also probing resource sources.
  ///
  /// This is the shared settings boundary for `/models` discovery and the
  /// optional chat-path health check. Platform-specific settings UIs should
  /// call this method instead of rebuilding the provider protocol themselves.
  Future<void> refreshAiServiceStatus({
    void Function(AiServiceCheckStage stage)? onStage,
  }) {
    final Future<void>? active = _aiServiceStatusRefreshFuture;
    if (active != null) {
      return active;
    }
    final int generation = ++_aiServiceStatusGeneration;
    _aiConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.loading,
      message: copy.localized(
        '正在获取模型列表（/models）',
        'Fetching model list (/models)',
      ),
      checkedAt: DateTime.now(),
    );
    onStage?.call(AiServiceCheckStage.models);
    _notifyListeners();
    final Future<void> future = _refreshAiServiceStatus(
      generation: generation,
      onStage: onStage,
    );
    _aiServiceStatusRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_aiServiceStatusRefreshFuture, future)) {
            _aiServiceStatusRefreshFuture = null;
          }
        })
        .catchError((Object _) {});
    return future;
  }

  Future<void> _refreshAiServiceStatus({
    required int generation,
    void Function(AiServiceCheckStage stage)? onStage,
  }) async {
    final AiApiConfig config = _aiApiConfig;
    if (config.baseUrl.trim().isEmpty || config.apiKey.trim().isEmpty) {
      _availableAiModels = <AiModel>[];
      _aiModelLoadState = AiModelLoadState.idle;
      _aiModelLoadError = null;
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '未配置 AI 服务',
        checkedAt: DateTime.now(),
      );
      _notifyListeners();
      return;
    }

    try {
      final List<AiModel> models = await refreshAiModels();
      if (generation != _aiServiceStatusGeneration) return;
      if (models.isEmpty) {
        _aiConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.failure,
          message: copy.aiApiModelsEmpty,
          checkedAt: DateTime.now(),
        );
      } else if (!hasSelectedAiModel) {
        _aiConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.warning,
          message: copy.localized(
            '接口可用，请选择模型',
            'Endpoint available; select a model',
          ),
          checkedAt: DateTime.now(),
        );
      } else if (!selectedAiModelResolution.isUsable) {
        _aiConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.failure,
          message:
              selectedAiModelResolution.issue == AiModelIssue.unsupportedEffort
              ? copy.aiApiReasoningUnsupported
              : copy.aiApiModelNotAllowed,
          checkedAt: DateTime.now(),
        );
      } else {
        _aiConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.loading,
          message: copy.localized(
            '正在探测 Chat Completions（不含推理强度和 Fast）',
            'Probing Chat Completions (without effort or Fast)',
          ),
          checkedAt: DateTime.now(),
        );
        onStage?.call(AiServiceCheckStage.chatProbe);
        _notifyListeners();
        final AiHealthResult health = await _aiService.checkConnection(config);
        if (generation != _aiServiceStatusGeneration) return;
        _aiConnectivityStatus = ConnectivityStatus(
          state: health.success
              ? ConnectivityState.success
              : ConnectivityState.failure,
          message: health.success
              ? copy.localized(
                  'Chat Completions 可连接；推理强度与 Fast 未验证',
                  'Chat Completions connected; effort and Fast unverified',
                )
              : copy.localized(
                  'Chat Completions 探测失败: ${_safeStatusError(health.message)}',
                  'Chat Completions probe failed: ${_safeStatusError(health.message)}',
                ),
          checkedAt: DateTime.now(),
        );
      }
    } catch (error) {
      if (generation != _aiServiceStatusGeneration) return;
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: copy.localized(
          'AI 服务失败: ${_safeStatusError(error)}',
          'AI service failed: ${_safeStatusError(error)}',
        ),
        checkedAt: DateTime.now(),
      );
    }
    if (generation == _aiServiceStatusGeneration) _notifyListeners();
  }

  String _safeStatusError(Object error) {
    return AiErrorPresentation.from(error, language: _language).message;
  }

  String _streamFailureReason(
    BoardGameAiStreamEvent event, {
    String? fallback,
  }) {
    final String value = (event.errorMessage ?? fallback ?? '').trim();
    if (value.isEmpty) {
      return _language == AppLanguage.zhHans
          ? '服务暂时不可用'
          : 'The service is temporarily unavailable';
    }
    if (value.startsWith('模型不可用') ||
        value.startsWith('服务商暂时不可用') ||
        value.startsWith('网络请求超时') ||
        value.startsWith('网络连接不可用') ||
        value.startsWith('鉴权失败') ||
        value.startsWith('服务返回格式无法解析')) {
      return value;
    }
    return AiErrorPresentation.from(value, language: _language).message;
  }

  int _runAttemptCount(_ChatGenerationState generation) {
    int attempts = 1;
    for (final AiRunEvent event in generation.runEvents) {
      final int reported = event.attempt ?? 0;
      if (reported > attempts) attempts = reported;
    }
    return attempts;
  }

  String _failureNotice(
    String base, {
    required String reason,
    required int attempts,
    List<String> progressLines = const <String>[],
    bool partialOutputRetained = false,
  }) {
    final String attemptText = _language == AppLanguage.zhHans
        ? '尝试 $attempts 次'
        : 'Attempted $attempts time${attempts == 1 ? '' : 's'}';
    final String reasonText = _language == AppLanguage.zhHans
        ? '失败原因：$reason'
        : 'Reason: $reason';
    final List<String> lines = <String>['$base\n$reasonText · $attemptText'];
    if (partialOutputRetained) {
      lines.add(
        _language == AppLanguage.zhHans
            ? '已保留已生成的部分答案，可点击重试继续。'
            : 'The generated partial answer was kept. Retry to continue.',
      );
    }
    if (progressLines.isNotEmpty) {
      lines.add(
        '${_language == AppLanguage.zhHans ? '已确认进度：' : 'Confirmed progress:'}\n'
        '${progressLines.join('\n')}',
      );
    }
    return lines.join('\n');
  }

  /// Builds user-readable progress from validated stage results only.
  ///
  /// Raw JSON, tool arguments and partial structured output are intentionally
  /// excluded. This preserves useful work after a failed run without making
  /// an unvalidated intermediate response look like an answer. The summary
  /// line is followed by every validated source and citation detail so a
  /// failed run does not hide work that was already confirmed.
  List<String> _confirmedProgressLines(
    _ChatGenerationState generation, {
    AiRunResult? runResult,
  }) {
    final List<AiStageResult> stageResults = <AiStageResult>[];
    if (runResult != null) {
      stageResults.addAll(runResult.stages);
    }
    if (stageResults.isEmpty) {
      for (final AiRunEvent event in generation.runEvents) {
        final AiStageResult? result = event.stageResult;
        if (event.type != AiRunEventType.stageCompleted || result == null) {
          continue;
        }
        stageResults.add(result);
      }
    }

    final Map<String, AiStageResult> latestByStage = <String, AiStageResult>{
      for (final AiStageResult result in stageResults) result.stageId: result,
    };
    final List<String> lines = <String>[];
    void addLine(String value) {
      final String normalized = value.trimRight();
      if (normalized.isNotEmpty && !lines.contains(normalized)) {
        lines.add(normalized);
      }
    }

    for (final AiStageResult result in latestByStage.values) {
      final String label = _progressStageLabel(result.stageId);
      final int inspected = result.inspectedSources.length;
      final int citations = result.citations.length;
      switch (result.status) {
        case AiStageStatus.answered:
          addLine(
            citations > 0
                ? _language == AppLanguage.zhHans
                      ? '$label：已确认 $citations 条依据'
                      : '$label: $citations verified references'
                : _language == AppLanguage.zhHans
                ? '$label：已得到阶段结果'
                : '$label: stage result confirmed',
          );
        case AiStageStatus.insufficient:
          addLine(
            _language == AppLanguage.zhHans
                ? '$label：已检查 $inspected 份资料，未找到可直接引用的内容'
                : '$label: checked $inspected source(s), no directly citable result',
          );
        case AiStageStatus.unavailable:
          addLine(
            _language == AppLanguage.zhHans
                ? '$label：资料暂时不可用'
                : '$label: sources were temporarily unavailable',
          );
        case AiStageStatus.skipped:
          addLine(
            _language == AppLanguage.zhHans
                ? '$label：按当前知识范围跳过'
                : '$label: skipped by the active knowledge scope',
          );
        case AiStageStatus.failed:
        case AiStageStatus.incomplete:
        case AiStageStatus.cancelled:
          if (inspected == 0 && citations == 0) continue;
          addLine(
            citations > 0
                ? _language == AppLanguage.zhHans
                      ? '$label：阶段未完成，但已确认 $citations 条依据'
                      : '$label: incomplete, but $citations references were verified'
                : _language == AppLanguage.zhHans
                ? '$label：阶段未完成，但已保留 $inspected 份已检查资料'
                : '$label: incomplete, but $inspected inspected source(s) were kept',
          );
      }

      // Keep the compact stage summary, then expose every confirmed item.
      // These are already validated RuleCitation values, never raw provider
      // payloads or unparsed structured output.
      final bool canDescribeInspectedSources =
          result.status != AiStageStatus.unavailable &&
          result.status != AiStageStatus.skipped;
      if (canDescribeInspectedSources && result.inspectedSources.isNotEmpty) {
        addLine(
          _language == AppLanguage.zhHans
              ? '$label：已检查 ${result.inspectedSources.length} 份资料'
              : '$label: checked ${result.inspectedSources.length} source(s)',
        );
        for (final RuleCitation citation in result.inspectedSources) {
          for (final String detail in _confirmedCitationLines(
            citation,
            confirmed: false,
          )) {
            addLine('  $detail');
          }
        }
      }
      if (result.citations.isNotEmpty) {
        for (int index = 0; index < result.citations.length; index++) {
          final RuleCitation citation = result.citations[index];
          final List<String> citationLines = _confirmedCitationLines(
            citation,
            confirmed: true,
            index: index + 1,
          );
          for (final String detail in citationLines) {
            addLine('  $detail');
          }
        }
      }
    }
    return List<String>.unmodifiable(lines);
  }

  /// Formats only fields that were supplied by a validated [RuleCitation].
  ///
  /// A source can be inspected without becoming a citation, so both kinds of
  /// detail are retained. Missing title/page/section/quote fields are omitted
  /// rather than replaced with guessed values.
  List<String> _confirmedCitationLines(
    RuleCitation citation, {
    required bool confirmed,
    int? index,
  }) {
    final List<String> lines = <String>[];
    final String title = citation.title?.trim() ?? '';
    final String path = citation.path?.trim() ?? '';
    final String? label = title.isNotEmpty
        ? title
        : path.isNotEmpty
        ? path.substring(path.lastIndexOf(RegExp(r'[\\/]')) + 1)
        : null;
    final String prefix = confirmed
        ? _language == AppLanguage.zhHans
              ? '已确认依据${index == null ? '' : ' $index'}'
              : 'Verified basis${index == null ? '' : ' $index'}'
        : _language == AppLanguage.zhHans
        ? '已检查资料'
        : 'Inspected source';
    if (label != null && label.isNotEmpty) {
      lines.add('$prefix：$label');
    } else {
      // A source ID is an internal join key, not a user-facing citation.
      // Keep the confirmed item visible without leaking that identifier.
      lines.add(prefix);
    }
    final String section = citation.section?.trim() ?? '';
    if (section.isNotEmpty) {
      lines.add(
        _language == AppLanguage.zhHans ? '章节：$section' : 'Section: $section',
      );
    }
    if (citation.page != null) {
      lines.add(
        _language == AppLanguage.zhHans
            ? '页码：第 ${citation.page} 页'
            : 'Page: ${citation.page}',
      );
    }
    final String quote = citation.quote?.trim() ?? '';
    if (quote.isNotEmpty) {
      lines.add(
        _language == AppLanguage.zhHans ? '引用：$quote' : 'Quote: $quote',
      );
    }
    final Uri? uri = Uri.tryParse(citation.url?.trim() ?? '');
    if (uri != null && uri.host.isNotEmpty) {
      lines.add(
        _language == AppLanguage.zhHans
            ? '来源：${uri.host}'
            : 'Domain: ${uri.host}',
      );
    }
    return lines;
  }

  String _progressStageLabel(String stageId) => switch (stageId) {
    'official' => _language == AppLanguage.zhHans ? '官方资料' : 'Official sources',
    'community' =>
      _language == AppLanguage.zhHans ? '社区资料' : 'Community sources',
    'web' => _language == AppLanguage.zhHans ? '联网搜索' : 'Web search',
    'general' ||
    'fallback' ||
    'answering' => _language == AppLanguage.zhHans ? '回答整理' : 'Answer drafting',
    _ => _language == AppLanguage.zhHans ? '阶段 $stageId' : 'Stage $stageId',
  };
}
