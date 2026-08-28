import '../models/app_language.dart';
import '../models/ai_api_config.dart';
import '../models/color_scheme_option.dart';
import '../models/remote_library_update.dart';

class AppCopy {
  AppCopy(this.language);

  final AppLanguage language;

  bool get isChinese => language == AppLanguage.zhHans;

  String get appTitle => isChinese ? '桌游导师' : 'Board Game Agent';
  String get appSubtitle => isChinese
      ? '像 Ludomentor 一样的桌游入口与统一 AI 助手'
      : 'A Ludomentor-style board game library with a unified AI helper';
  String get featuredLabel => isChinese ? '当前已装入' : 'Loaded now';
  String featuredGameCount(int count) =>
      isChinese ? '$count 个桌游' : '$count board games';
  String get openSettings => isChinese ? '语言与设置' : 'Language and settings';
  String get languageTitle => isChinese ? '语言设置' : 'Language';
  String get colorSchemeTitle => isChinese ? '主题风格' : 'Theme style';
  String get colorSchemeHint => isChinese
      ? '选择一套完整的页面、组件与状态视觉风格'
      : 'Choose a complete visual style for pages, components, and states';
  String get aiApiTitle => isChinese ? 'AI 接口配置' : 'AI API Config';
  String get aiApiProviderNameLabel => isChinese ? '供应商名称' : 'Provider name';
  String get aiApiProviderNameRequired =>
      isChinese ? '请输入供应商名称' : 'Enter a provider name';
  String get aiApiProviderNameReserved => isChinese
      ? '该名称已被内置预设占用，请换一个供应商名称'
      : 'That name is reserved by a built-in preset. Choose another name.';
  String get aiApiUrlLabel => isChinese ? '接口地址' : 'Base URL';
  String get aiApiKeyLabel => isChinese ? '接口密钥' : 'API Key';
  String get aiApiPresetLabel => isChinese ? '常用服务预设' : 'Provider preset';
  String get aiApiModelLabel => isChinese ? '模型名称' : 'Model';
  String get aiApiModelSelectHint =>
      isChinese ? '请选择接口返回的模型' : 'Select a model returned by the endpoint';
  String get aiApiReasoningEffortLabel =>
      isChinese ? '推理强度' : 'Reasoning effort';
  String get aiApiReasoningEffortHint => isChinese
      ? '仅对支持 reasoning_effort 的模型生效；自动模式不会发送额外参数。'
      : 'Only supported by models that implement reasoning_effort; automatic sends no extra field.';
  String get aiApiResponseSpeedLabel => isChinese ? '推理速度' : 'Response speed';
  String get aiApiResponseSpeedHint => isChinese
      ? '这是服务商的速度策略提示，实际速度仍取决于模型、网络和接口实现。'
      : 'A provider speed-tier hint; actual speed still depends on the model, network, and endpoint.';
  String aiApiReasoningEffortName(AiReasoningEffort value) {
    switch (value) {
      case AiReasoningEffort.automatic:
        return isChinese ? '自动' : 'Automatic';
      case AiReasoningEffort.low:
        return isChinese ? '低' : 'Low';
      case AiReasoningEffort.medium:
        return isChinese ? '中' : 'Medium';
      case AiReasoningEffort.high:
        return isChinese ? '高' : 'High';
    }
  }

  String aiApiResponseSpeedName(AiResponseSpeed value) {
    switch (value) {
      case AiResponseSpeed.automatic:
        return isChinese ? '自动' : 'Automatic';
      case AiResponseSpeed.fast:
        return isChinese ? '快速（Fast）' : 'Fast';
      case AiResponseSpeed.standard:
        return isChinese ? '标准（Default）' : 'Standard (Default)';
    }
  }

  String get aiApiGenerationCompatibilityHint => isChinese
      ? '自定义接口不支持这些可选参数时，请保持“自动”，否则可能返回 400。'
      : 'If a custom endpoint does not support these optional fields, keep Automatic or it may return 400.';
  String get aiApiModelRequired =>
      isChinese ? '请先获取并选择一个模型' : 'Fetch and select a model first';
  String get aiApiModelsNotLoaded => isChinese
      ? '点击刷新，从 /models 获取可用模型'
      : 'Refresh to load models from /models';
  String get aiApiModelsLoading => isChinese ? '正在加载模型列表…' : 'Loading models…';
  String aiApiModelsLoaded(int count) =>
      isChinese ? '已加载 $count 个模型' : '$count models loaded';
  String get aiApiModelsEmpty =>
      isChinese ? '接口返回了空模型列表' : 'The endpoint returned no models';
  String get aiApiModelsFailed =>
      isChinese ? '模型列表加载失败' : 'Could not load models';
  String get aiApiModelsRefresh => isChinese ? '刷新模型列表' : 'Refresh model list';
  String get aiApiModelsRetry => isChinese ? '重试获取模型' : 'Retry model discovery';
  String get aiApiWebCorsHint => isChinese
      ? 'Web 浏览器可能拦截跨域请求。若使用本地预览代理，请将地址改为 http://127.0.0.1:8081/v1。'
      : 'Browsers may block cross-origin requests. For the local preview proxy, use http://127.0.0.1:8081/v1.';
  String get aiApiSave => isChinese ? '保存配置' : 'Save Config';
  String get aiApiReset => isChinese ? '恢复默认' : 'Reset Default';
  String get aiApiTest => isChinese ? '测试 AI 接口' : 'Test AI API';
  String get aiApiSaved => isChinese ? 'AI 接口配置已保存' : 'AI API config saved';
  String aiApiPresetSaved(String name) =>
      isChinese ? '已保存供应商预设：$name' : 'Saved provider preset: $name';
  String get aiApiTestSuccess => isChinese ? '连接成功' : 'Connection successful';

  String aiProviderPresetName(AiProviderPreset preset) {
    switch (preset) {
      case AiProviderPreset.openAi:
        return 'OpenAI';
      case AiProviderPreset.deepSeek:
        return 'DeepSeek';
      case AiProviderPreset.custom:
        return isChinese ? '自定义 OpenAI 兼容接口' : 'Custom OpenAI-compatible';
    }
  }

  String get aiReplyFailed => isChinese
      ? '这次回答失败了，请稍后再试。'
      : 'The assistant could not answer this time. Please try again.';
  String get retry => isChinese ? '重试' : 'Retry';
  String get stopGenerating => isChinese ? '停止生成' : 'Stop generating';
  String get answerSourceRulebook => isChinese ? '规则库' : 'Rulebook';
  String get answerSourceGeneral => isChinese ? '智能补充' : 'AI supplement';
  String get answerSourceInsufficient => isChinese ? '信息不足' : 'Insufficient';
  String get evidenceTitle => isChinese ? '参考来源' : 'Sources';
  String get streaming => isChinese ? '正在回答…' : 'Answering…';
  String get assetTest => isChinese ? '测试资源访问' : 'Test Asset Access';
  String get assetPriorityTitle =>
      isChinese ? '资源访问优先级' : 'Asset Source Priority';
  String get assetPriorityHint => isChinese
      ? '拖动排序，越靠上越优先使用'
      : 'Drag to reorder. Higher items are preferred first.';
  String get aiStatusTitle => isChinese ? 'AI接口' : 'AI API';
  String get assetStatusTitle => isChinese ? '资源访问' : 'Assets';
  String get aiStatusDialogTitle => isChinese ? 'AI 接口状态' : 'AI API Status';
  String get assetStatusDialogTitle =>
      isChinese ? '资源访问状态' : 'Asset Access Status';
  String get statusReadyShort => isChinese ? '正常' : 'Ready';
  String get statusFailedShort => isChinese ? '失败' : 'Failed';
  String get statusPendingShort => isChinese ? '待测' : 'Pending';
  String get statusLimitedShort => isChinese ? '受限' : 'Limited';
  String get statusLoading => isChinese ? '加载中' : 'Loading';
  String get aiStatusDefaultReady => isChinese ? '默认可用' : 'Ready by default';
  String get activityTitle => isChinese ? '消息' : 'Notifications';
  String get activityEmpty => isChinese ? '暂无消息' : 'No notifications';
  String get activityViewAll => isChinese ? '查看全部' : 'View all';
  String get activityRefreshServices =>
      isChinese ? '刷新服务状态' : 'Refresh service status';
  String get activityServiceRefreshTitle =>
      isChinese ? '服务状态已刷新' : 'Service status refreshed';
  String activityServiceRefreshMessage(String ai, String assets) =>
      isChinese ? 'AI：$ai · 资料：$assets' : 'AI: $ai · Assets: $assets';
  String get activityServiceRefreshFailedTitle =>
      isChinese ? '服务状态刷新失败' : 'Service refresh failed';
  String get activityAiCompletedTitle =>
      isChinese ? 'AI 已完成回答' : 'AI answer completed';
  String activityAiCompletedMessage(String gameTitle) => isChinese
      ? '已完成《$gameTitle》的新回答。'
      : 'A new answer for $gameTitle is ready.';
  String get activityAiFailedTitle =>
      isChinese ? 'AI 回答失败' : 'AI answer failed';
  String get activityLibraryUpdateTitle =>
      isChinese ? '发现资料更新' : 'Library update found';
  String activityLibraryUpdateMessage(int count) => isChinese
      ? '有 $count 项资料等待更新。'
      : '$count library items are ready to update.';
  String get activityJustNow => isChinese ? '刚刚' : 'Just now';
  String activityMinutesAgo(int count) =>
      isChinese ? '$count 分钟前' : '$count min ago';
  String activityHoursAgo(int count) =>
      isChinese ? '$count 小时前' : '$count hr ago';
  String activityDaysAgo(int count) =>
      isChinese ? '$count 天前' : '$count days ago';
  String get assetTestDone =>
      isChinese ? '资源访问测试完成' : 'Asset access test completed';
  String get dialogClose => isChinese ? '关闭' : 'Close';
  String get libraryUpdateTitle =>
      isChinese ? '检测到新的桌游信息内容' : 'New board game content detected';
  String get libraryUpdateMessage => isChinese
      ? '检测到远端资料与本地缓存存在实际差异。是否现在下载并更新？'
      : 'Remote content differs from the local cache. Download and update it now?';
  String libraryUpdateChangeSummary(int count) =>
      isChinese ? '共 $count 项资源发生变化' : '$count resources changed';
  String libraryUpdateResourceLabel(RemoteLibraryResourceType type) {
    return switch (type) {
      RemoteLibraryResourceType.catalog => isChinese ? '目录' : 'Catalog',
      RemoteLibraryResourceType.gameManifest =>
        isChinese ? '桌游配置' : 'Game metadata',
      RemoteLibraryResourceType.image => isChinese ? '图片' : 'Images',
      RemoteLibraryResourceType.rulebook => isChinese ? '规则书' : 'Rulebooks',
      RemoteLibraryResourceType.faq => isChinese ? 'FAQ' : 'FAQs',
      RemoteLibraryResourceType.other => isChinese ? '其他资料' : 'Other',
    };
  }

  String libraryUpdateGameListLabel(int count) =>
      isChinese ? '涉及 $count 个桌游：' : 'Affected games ($count):';
  String get updateNow => isChinese ? '确定' : 'Update';
  String get updateLater => isChinese ? '取消' : 'Cancel';
  String get updatingNow => isChinese ? '正在更新资源…' : 'Updating content...';
  String get voiceReplyTitle => isChinese ? 'AI 回答朗读' : 'AI voice reply';
  String get voiceReplyHint => isChinese
      ? '打开后，AI 回复会自动朗读。'
      : 'When enabled, assistant replies are spoken aloud.';
  String get voiceReplyUnavailable => isChinese
      ? 'Windows 桌面版暂时关闭语音朗读，以避免系统语音组件导致闪退。'
      : 'Voice output is temporarily disabled on Windows to prevent native speech crashes.';
  String get voiceReplySwitchLabel => isChinese ? '语音朗读' : 'Voice output';
  String get assistantModeTitle => isChinese ? '助手交互方式' : 'Assistant mode';
  String get assistantTextModeLabel =>
      isChinese ? '文字 / 语音转文字' : 'Text / Dictation';
  String get assistantTextModeHint => isChinese
      ? '键盘输入，或先用麦克风转成文字后确认发送。'
      : 'Type, or dictate into the composer before sending.';
  String get assistantRealtimeModeLabel =>
      isChinese ? '直接语音对话' : 'Realtime voice';
  String get assistantRealtimeModeHint => isChinese
      ? '实时语音 Agent 尚未配置，暂时不可用。'
      : 'The realtime voice Agent is not configured yet.';
  String get assistantRealtimeUnavailable => isChinese
      ? '直接语音对话暂不可用：还没有配置实时语音服务。请先使用文字 / 语音转文字模式。'
      : 'Realtime voice is unavailable because no voice service is configured. Use text or dictation for now.';
  String get assistantModeChanged =>
      isChinese ? '助手交互方式已切换' : 'Assistant mode changed';
  String get enterAssistant => isChinese ? '进入 AI 助手' : 'Open AI Assistant';
  String get assistantMode => isChinese ? '桌游助手' : 'Board Game Assistant';
  String get assistantModeHint => isChinese
      ? '你可以先只按本桌游知识库回答；如果打开智能补充，知识不够时会再结合当前桌游详情直接作答。'
      : 'You can keep answers limited to the local game knowledge base, or allow a direct fallback that uses the current game profile when knowledge is insufficient.';
  String get knowledgeOnlyLabel => isChinese ? '仅知识库' : 'Knowledge Only';
  String get smartSupplementLabel => isChinese ? '智能补充' : 'Smart Supplement';
  String get smartSupplementSwitchLabel =>
      isChinese ? '知识不足时智能补充' : 'Supplement when knowledge is insufficient';
  String get smartSupplementSwitchHintOn => isChinese
      ? '先按当前桌游知识库回答；若知识库没有足够信息，再结合这款桌游的详情直接回答。'
      : 'Answer from the current game knowledge base first, then fall back to a direct answer that uses the current game profile when needed.';
  String get smartSupplementSwitchHintOff => isChinese
      ? '只依据当前桌游知识库回答；知识库没有写到的内容会直接回答不知道。'
      : 'Answer only from the current game knowledge base, and say you do not know when the knowledge base does not cover the question.';
  String get askAnything => isChinese ? '现在就问它' : 'Ask anything now';
  String get helperSectionTitle =>
      isChinese ? '这个版本已经能做什么' : 'What this build already does';
  String get futureSectionTitle =>
      isChinese ? '下一步接真实 AI 时' : 'When you wire in a real AI later';
  String get homeSearchHint => isChinese ? '搜索桌游...' : 'Search games...';
  String get favouritesOnly => isChinese ? '只看收藏' : 'Show favourites only';
  String get globalAiTitle => isChinese ? '通用 AI 助手' : 'Global AI Assistant';
  String get globalAiSubtitle => isChinese
      ? '独立 AI 入口，可切换知识库优先与智能补充'
      : 'A standalone AI entry with knowledge-first and fallback modes';
  String get gameLibraryTitle => isChinese ? '桌游列表' : 'Game Library';
  String get allKnowledgeGreeting => isChinese
      ? '这里是独立 AI 入口。你可以切换为仅知识库回答，或允许在知识不足时做智能补充。'
      : 'This is the standalone AI entry. You can keep answers knowledge-only or allow a smart fallback when the knowledge base is insufficient.';
  String get homeAssetsLoadingTitle =>
      isChinese ? '正在加载资源...' : 'Loading assets...';
  String homeAssetsLoadingProgress(int loaded, int total) =>
      isChinese ? '已加载 $loaded / $total' : 'Loaded $loaded / $total';
  String assistantGreetingFor(String gameTitle, String intro) {
    final String normalizedIntro = intro.trim().isEmpty
        ? (isChinese
              ? '《$gameTitle》是一款值得边玩边问的桌游。'
              : '$gameTitle is a board game worth exploring as you play.')
        : intro.trim();
    return normalizedIntro;
  }

  String get messageHint => isChinese
      ? '问规则、流程、术语、策略...'
      : 'Ask about rules, flow, terms, or strategy...';
  String get listening => '...';
  String get tapToStop => isChinese ? '点击停止录音' : 'Tap to stop recording';
  String get micUnavailable => isChinese
      ? '当前设备未就绪，语音识别不可用。'
      : 'Speech recognition is unavailable on this device right now.';
  String get micPermissionHint => isChinese
      ? '请在系统设置中允许“桌游导师”使用麦克风。'
      : 'Allow Board Game Agent to use the microphone in system settings.';
  String get clearChat => isChinese ? '清空对话' : 'Clear chat';
  String get quickPromptsTitle => isChinese ? '快速提问' : 'Quick prompts';
  String get quickPromptRule =>
      isChinese ? '这个规则怎么处理？' : 'How does this rule work?';
  String get quickPromptFlow =>
      isChinese ? '下一步应该做什么？' : 'What should happen next?';
  String get quickPromptTerm =>
      isChinese ? '这个术语是什么意思？' : 'What does this term mean?';
  String get assistantContextTitle =>
      isChinese ? '问法与上下文' : 'Context and answer style';
  String get assistantContextHint => isChinese
      ? '不离开聊天页，也能调整本次对话的回答方式。'
      : 'Tune this conversation without leaving the chat.';
  String get assistantKnowledgeHint => isChinese
      ? '优先依据当前桌游的规则书与 FAQ。'
      : 'Prioritize the current game rulebook and FAQ.';
  String get assistantRecordingTitle => isChinese ? '正在听你说' : 'Listening';
  String get assistantRecordingHint => isChinese
      ? '说完后点击停止，识别结果会回到输入框。'
      : 'Tap stop when you are done; the transcript returns to the composer.';
  String get assistantGeneratingTitle =>
      isChinese ? '正在整理规则…' : 'Preparing an answer…';
  String get overviewTitle => isChinese ? '桌游简介' : 'Overview';
  String get flowTitle => isChinese ? '一局流程' : 'Round flow';
  String get skillTitle => isChinese ? 'AI 能帮你什么' : 'What the AI can help with';
  String get speechReady => isChinese ? '语音已准备好' : 'Speech ready';
  String get speechUnavailableShort =>
      isChinese ? '语音不可用' : 'Speech unavailable';
  String get voiceReplyOff => isChinese ? '朗读已关闭' : 'Voice reply off';
  String get speakAgain => isChinese ? '再朗读一次' : 'Speak again';
  String get mockBadge => isChinese ? '回声 AI' : 'Echo AI';
  String get send => isChinese ? '发送' : 'Send';
  String get detailPageTitle => isChinese ? '桌游详情' : 'Game Details';
  String get rulesBook => isChinese ? '规则书' : 'Rulebook';
  String get faq => isChinese ? 'FAQ' : 'FAQ';
  String get desktopHome => isChinese ? '首页' : 'Home';
  String get desktopGames => isChinese ? '我的游戏' : 'My Games';
  String get desktopGameDetail => isChinese ? '桌游详情' : 'Game Details';
  String get desktopLibrary => isChinese ? '资料库' : 'Library';
  String get desktopSettings => isChinese ? '设置' : 'Settings';
  String get desktopWorkspace => isChinese ? '工作区' : 'Workspace';
  String get desktopSystem => isChinese ? '系统' : 'System';
  String get desktopSearchTitle => isChinese ? '搜索桌游' : 'Search games';
  String get desktopSearchAction => isChinese ? '搜索' : 'Search';
  String get desktopSearchHint =>
      isChinese ? '输入名称、别名或关键词' : 'Name, alias, or keyword';
  String get desktopNoGames => isChinese ? '暂无可用游戏' : 'No games available';
  String get desktopNoSearchResults =>
      isChinese ? '没有找到匹配的桌游' : 'No matching games';
  String get desktopSessionTitle => isChinese ? '会话' : 'Sessions';
  String get desktopContextTitle => isChinese ? '上下文' : 'Context';
  String get desktopAnswerModeTitle => isChinese ? '回答模式' : 'Answer mode';
  String get desktopAllResources => isChinese ? '全部资料' : 'All resources';
  String get desktopOfficialFirst => isChinese ? '官方资料优先' : 'Official sources';
  String get desktopSmartSupplement =>
      isChinese ? '允许智能补充' : 'Smart supplement';
  String get desktopLibraryTitle => isChinese ? '规则资料' : 'Library';
  String get desktopImport => isChinese ? '导入' : 'Import';
  String get desktopCreate => isChinese ? '新建' : 'New';
  String get desktopRefreshLibrary => isChinese ? '刷新资料库' : 'Refresh library';
  String get desktopLibraryOther => isChinese ? '其他' : 'Other';
  String get desktopAll => isChinese ? '全部' : 'All';
  String get desktopRulebook => isChinese ? '规则书' : 'Rulebook';
  String get desktopFaq => 'FAQ';
  String get desktopOpen => isChinese ? '打开' : 'Open';
  String get desktopOpenUnavailable =>
      isChinese ? '打开（暂不支持）' : 'Open (unavailable)';
  String get desktopDownload => isChinese ? '下载' : 'Download';
  String get desktopDelete => isChinese ? '删除' : 'Delete';
  String get desktopMore => isChinese ? '更多' : 'More';
  String get desktopRetry => isChinese ? '重试' : 'Retry';
  String get desktopLibraryUnavailable => isChinese
      ? '远端资料库暂时不可用，继续显示本地缓存。'
      : 'The remote library is unavailable. Showing the local cache.';
  String get desktopLibraryNoResources =>
      isChinese ? '远端资料库暂无可展示的资料' : 'No library resources available';
  String get desktopLibraryFilterNoResources =>
      isChinese ? '当前筛选没有资料' : 'No resources match this filter';
  String get desktopImportComingSoon =>
      isChinese ? '该功能正在开发中' : 'This feature is under development';
  String get desktopOpenUnavailableMessage => isChinese
      ? '该资源暂不支持在线阅读，请先下载'
      : 'This resource cannot be opened online yet. Download it first.';
  String get desktopDownloadFailed => isChinese
      ? '下载失败，请检查资料库连接后重试'
      : 'Download failed. Check the library connection and retry.';
  String desktopDownloadedTo(String path) =>
      isChinese ? '已下载到 $path' : 'Downloaded to $path';
  String desktopDownloadError(Object error) =>
      isChinese ? '下载失败：$error' : 'Download failed: $error';
  String get desktopDeleteUnavailable => isChinese
      ? '暂时无法删除远端资源，相关功能正在开发中'
      : 'Remote deletion is not available yet.';
  String get desktopLibraryEmptyTitle =>
      isChinese ? '资料库暂为空' : 'Library is empty';
  String get desktopLibraryEmptyMessage => isChinese
      ? '游戏资料加载完成后，规则书、FAQ 和其他资料会显示在这里。'
      : 'Rulebooks, FAQs, and other resources appear here after game data loads.';
  String get desktopContinuePlaying => isChinese ? '继续游玩' : 'Continue playing';
  String get desktopStart => isChinese ? '开始' : 'Start';
  String get desktopLastGame => isChinese ? '上次对局' : 'Last game';
  String get desktopContinue => isChinese ? '继续' : 'Continue';
  String get desktopQuickActions => isChinese ? '快捷操作' : 'Quick actions';
  String get desktopAskAi => isChinese ? '询问 AI' : 'Ask AI';
  String get desktopRecentGames => isChinese ? '最近游戏' : 'Recent games';
  String get desktopAssistantUnavailable =>
      isChinese ? 'AI 助手暂不可用' : 'AI assistant unavailable';
  String get desktopAssistantUnavailableMessage => isChinese
      ? '请先加载至少一个游戏资料，AI 助手才能建立对应的规则上下文。'
      : 'Load at least one game before opening a rules-aware assistant.';
  String get desktopNoSession => isChinese ? '还没有会话' : 'No sessions yet';
  String get desktopNoSessionHint => isChinese
      ? '进入桌游详情页点击“询问 AI”，或直接打开通用助手。'
      : 'Open a game and ask AI, or start the global assistant.';
  String get desktopOpenGlobalAssistant =>
      isChinese ? '打开通用助手' : 'Open global assistant';
  String get desktopOfficialLoaded =>
      isChinese ? '官方资料已加载' : 'Official sources loaded';
  String desktopConversationSummary(bool global, int count) => global
      ? (isChinese ? '跨桌游问答 · $count 条消息' : 'Cross-game · $count messages')
      : (isChinese ? '规则问答 · $count 条消息' : 'Rules · $count messages');
  String get desktopClearConversation => isChinese ? '清空对话' : 'Clear chat';
  String get desktopVoiceInput => isChinese ? '语音输入' : 'Voice input';
  String get desktopSend => isChinese ? '发送' : 'Send';
  String get desktopStopGenerating => isChinese ? '停止生成' : 'Stop generating';
  String get desktopPreferences => isChinese ? '偏好' : 'Preferences';
  String get desktopAppearance => isChinese ? '外观' : 'Appearance';
  String get desktopAiService => isChinese ? 'AI 服务' : 'AI service';
  String get desktopBehavior => isChinese ? '行为' : 'Behavior';
  String get desktopProvider => isChinese ? '供应商' : 'Provider';
  String get desktopModel => isChinese ? '模型' : 'Model';
  String get desktopDetails => isChinese ? '详细设置' : 'Details';
  String get desktopAboutApp => isChinese ? '关于桌游导师' : 'About Board Game Agent';
  String get desktopLibraryIndex => isChinese ? '资料索引' : 'Resource index';
  String get desktopLibraryReference => isChinese ? '规则参考' : 'Rules reference';
  String get desktopLibraryPlayerAid => isChinese ? '玩家辅助' : 'Player aid';
  String get desktopLibrarySupplement => isChinese ? '补充资料' : 'Supplement';
  String get desktopLibraryEmpty =>
      isChinese ? '远端资料库暂无可展示的资料' : 'No library resources available';
  String get desktopLibraryFilterEmpty =>
      isChinese ? '当前筛选没有资料' : 'No resources match this filter';
  String get desktopResourceOpenUnavailable => isChinese
      ? '该资源暂不支持在线阅读，请先下载'
      : 'This resource cannot be opened online yet. Download it first.';
  String get desktopDownloadDirectory =>
      isChinese ? '选择下载目录' : 'Choose download folder';
  String get askAiAssistant => isChinese ? '询问AI助手' : 'Ask AI Assistant';
  String get imageGalleryHint =>
      isChinese ? '左右滑动查看图片' : 'Swipe to browse images';
  String get imagePageLabel => isChinese ? '图片' : 'Image';
  String get imageCoverLabel => isChinese ? '封面图' : 'Cover';
  String get imageSceneLabel => isChinese ? '场景图' : 'Scene';
  String get supportPlayersLabel => isChinese ? '支持人数' : 'Supported Players';
  String get recommendedPlayersLabel =>
      isChinese ? '推荐人数' : 'Recommended Players';
  String get ratingLabel => isChinese ? '评分' : 'Rating';
  String get originalNameLabel => isChinese ? '原名' : 'Original Name';
  String get releaseInfoLabel => isChinese ? '分类' : 'Category';
  String get learningDifficultyLabel =>
      isChinese ? '上手难度' : 'Learning Difficulty';
  String get perPlayerTimeLabel => isChinese ? '人均时长' : 'Per-player Time';
  String get setupTimeLabel => isChinese ? '设置时长' : 'Setup Time';
  String get languageRequirementLabel =>
      isChinese ? '语言要求' : 'Language Requirement';
  String get homeStatPlayers => isChinese ? '人数' : 'Players';
  String get homeStatTime => isChinese ? '时长' : 'Play time';
  String get homeStatWeight => isChinese ? '复杂度' : 'Weight';
  String get switchLanguage => isChinese ? '切换英文' : 'Switch to Chinese';
  String get checkForUpdatesTitle =>
      isChinese ? '启动时检查更新' : 'Check for updates on startup';
  String get appUpdateTitle => isChinese ? '应用更新' : 'App updates';
  String get checkForUpdatesHint => isChinese
      ? '打开后，启动应用时会检查 Android APK 是否有新版本。'
      : 'Check for a newer Android APK when the app starts.';

  String colorSchemeName(ColorSchemeOption scheme) {
    switch (scheme) {
      case ColorSchemeOption.classic:
        return isChinese ? '默认主题' : 'Default Theme';
      case ColorSchemeOption.sunsetCoast:
        return isChinese ? '晚霞海岸' : 'Sunset Coast';
    }
  }
}
