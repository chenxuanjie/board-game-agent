import '../models/app_language.dart';
import '../models/ai_api_config.dart';
import '../models/color_scheme_option.dart';

class AppCopy {
  AppCopy(this.language);

  final AppLanguage language;

  bool get isChinese => language == AppLanguage.zhHans;

  String get appTitle => isChinese ? '桌游导师' : 'Board Game Agent';
  String get startupDataUnavailable => isChinese
      ? '暂时无法加载桌游资料，请稍后重试。'
      : 'Board-game data is temporarily unavailable. Please try again later.';
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
      ? '点击“测试并保存配置”，从 /models 获取可用模型'
      : 'Click “Test and save config” to load models from /models';
  String get aiApiModelsLoading => isChinese ? '正在加载模型列表…' : 'Loading models…';
  String aiApiModelsLoaded(int count) =>
      isChinese ? '已加载 $count 个模型' : '$count models loaded';
  String get aiApiModelsEmpty =>
      isChinese ? '接口返回了空模型列表' : 'The endpoint returned no models';
  String get aiApiModelsFailed =>
      isChinese ? '模型列表加载失败' : 'Could not load models';
  String aiApiModelsSaved(int count) =>
      isChinese ? '配置已保存，已获取 $count 个模型' : 'Config saved; $count models loaded';
  String get aiApiSavedWithoutModelDiscovery => isChinese
      ? '配置已保存，接口地址和密钥完整后可获取模型'
      : 'Config saved; add a base URL and API key to load models';
  String aiApiSavedWithModelFailure(String detail) => isChinese
      ? '配置已保存，但模型获取失败：$detail'
      : 'Config saved, but model discovery failed: $detail';
  String get aiApiWebCorsHint => isChinese
      ? 'Web 浏览器可能拦截跨域请求。若使用本地预览代理，请将地址改为 http://127.0.0.1:8081/v1。'
      : 'Browsers may block cross-origin requests. For the local preview proxy, use http://127.0.0.1:8081/v1.';
  String get aiApiSave => isChinese ? '测试并保存配置' : 'Test and save config';
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
        return isChinese ? '自定义服务商(仅openai)' : 'Custom provider (OpenAI only)';
    }
  }

  String get aiReplyFailed => isChinese
      ? '这次回答失败了，请稍后再试。'
      : 'The assistant could not answer this time. Please try again.';
  String get aiReplyIncomplete => isChinese
      ? '回答未完成，可点击重试。'
      : 'The answer was not completed. You can retry.';
  String get copyAnswer => isChinese ? '复制回答' : 'Copy answer';
  String get answerCopied => isChinese ? '回答已复制' : 'Answer copied';
  String get retry => isChinese ? '重试' : 'Retry';
  String get stopGenerating => isChinese ? '停止生成' : 'Stop generating';
  String get answerSourceRulebook => isChinese ? '规则库' : 'Rulebook';
  String get answerSourceOfficial => isChinese ? '官方资料' : 'Official source';
  String get answerSourceCommunity => isChinese ? '社区资料' : 'Community source';
  String get answerSourceWeb => isChinese ? '联网资料' : 'Web source';
  String get answerSourceModelKnowledge =>
      isChinese ? '模型知识（无直接依据）' : 'Model knowledge';
  String get answerSourceGeneral => isChinese ? '智能补充' : 'AI supplement';
  String get answerSourceInsufficient => isChinese ? '信息不足' : 'Insufficient';
  String get evidenceTitle => isChinese ? '参考来源' : 'Sources';
  String get aiWorkflowFindingOfficial =>
      isChinese ? '正在查找官方规则…' : 'Checking official rules…';
  String get aiWorkflowFindingCommunity =>
      isChinese ? '正在查找社区资料…' : 'Checking community sources…';
  String get aiWorkflowSearchingWeb =>
      isChinese ? '正在联网搜索…' : 'Searching the web…';
  String get aiWorkflowRouting =>
      isChinese ? '正在判断问题范围…' : 'Classifying the question…';
  String get aiWorkflowPreparingAnswer =>
      isChinese ? '正在整理答案…' : 'Preparing the answer…';
  String get aiWorkflowWorking => isChinese ? '正在处理…' : 'Working…';

  String aiWorkflowStatus(String? status) => switch (status) {
    'official' => aiWorkflowFindingOfficial,
    'community' => aiWorkflowFindingCommunity,
    'web_search' => aiWorkflowSearchingWeb,
    'routing' => aiWorkflowRouting,
    'answering' => aiWorkflowPreparingAnswer,
    _ => aiWorkflowWorking,
  };
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
  String get aiStatusDefaultReady => isChinese ? '默认可用' : 'Ready by default';
  String get assetTestDone =>
      isChinese ? '资源访问测试完成' : 'Asset access test completed';
  String get dialogClose => isChinese ? '关闭' : 'Close';
  String get libraryUpdateTitle =>
      isChinese ? '检测到新的桌游信息内容' : 'New board game content detected';
  String get libraryUpdateMessage => isChinese
      ? '检测到 catalog、背景图、规则书或相关资料有更新。是否现在下载并更新到本地？'
      : 'Catalog, images, rulebooks, or related content has been updated. Download and update local data now?';
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
      ? '你可以只按本桌游知识库回答；打开智能补充后，普通问题直接回答，桌游问题才查资料。'
      : 'Keep answers limited to the local game knowledge base, or let smart supplement route general questions directly and search only for game questions.';
  String get knowledgeOnlyLabel => isChinese ? '仅知识库' : 'Knowledge Only';
  String get smartSupplementLabel => isChinese ? '智能补充' : 'Smart Supplement';
  String get smartSupplementSwitchLabel =>
      isChinese ? '知识不足时智能补充' : 'Supplement when knowledge is insufficient';
  String get smartSupplementSwitchHintOn => isChinese
      ? '先判断问题范围：普通问题直接回答；桌游问题才查资料，资料不足时再智能补充。'
      : 'Route first: answer general questions directly, search sources for game questions, and supplement only when needed.';
  String get smartSupplementSwitchHintOff => isChinese
      ? '只依据当前桌游知识库回答；知识库没有写到的内容会直接回答不知道。'
      : 'Answer only from the current game knowledge base, and say you do not know when the knowledge base does not cover the question.';
  String get useCurrentGameKnowledgeLabel =>
      isChinese ? '使用当前桌游资料' : 'Use current game sources';
  String get useCurrentGameKnowledgeHint => isChinese
      ? '通用助手中允许按当前选中的桌游查阅规则资料；关闭后仍会识别明确的桌游问题。'
      : 'Let the standalone assistant use selected game sources; explicit game questions still work when off.';
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
  String documentUnavailable(String title) {
    final String normalized = _documentName(title);
    return isChinese
        ? '暂时找不到“$normalized”，资料可能还在同步中，请稍后再试。'
        : '$normalized is temporarily unavailable. The resource may still be syncing; please try again later.';
  }

  String documentLoadFailed(String title) {
    final String normalized = _documentName(title);
    return isChinese
        ? '“$normalized”暂时无法读取，请稍后重试。'
        : '$normalized could not be loaded right now. Please try again later.';
  }

  String documentRenderFailed(String title) {
    final String normalized = _documentName(title);
    return isChinese
        ? '“$normalized”暂时无法打开，文件可能损坏或格式暂不支持。'
        : '$normalized could not be opened. The file may be damaged or unsupported.';
  }

  String _documentName(String title) {
    return title.trim().isEmpty
        ? (isChinese ? '这份资料' : 'This document')
        : title.trim();
  }

  String get back => isChinese ? '返回' : 'Back';

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
