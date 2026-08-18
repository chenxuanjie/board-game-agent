import '../models/app_language.dart';
import '../models/color_scheme_option.dart';

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
  String get colorSchemeTitle => isChinese ? '配色方案' : 'Color Scheme';
  String get colorSchemeHint => isChinese ? '切换不同视觉风格' : 'Switch visual styles';
  String get aiApiTitle => isChinese ? 'AI 接口配置' : 'AI API Config';
  String get aiApiNameLabel => isChinese ? '配置名称' : 'Config Name';
  String get aiApiUrlLabel => isChinese ? '接口地址' : 'Base URL';
  String get aiApiKeyLabel => isChinese ? '接口密钥' : 'API Key';
  String get aiApiSave => isChinese ? '保存配置' : 'Save Config';
  String get aiApiReset => isChinese ? '恢复默认' : 'Reset Default';
  String get aiApiTest => isChinese ? '测试 AI 接口' : 'Test AI API';
  String get aiApiSaved => isChinese ? 'AI 接口配置已保存' : 'AI API config saved';
  String get aiApiTestSuccess => isChinese ? '连接成功' : 'Connection successful';
  String get aiReplyFailed => isChinese
      ? '这次回答失败了，请稍后再试。'
      : 'The assistant could not answer this time. Please try again.';
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
  String get voiceReplySwitchLabel => isChinese ? '语音朗读' : 'Voice output';
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
        return isChinese ? '默认深色' : 'Classic Dark';
      case ColorSchemeOption.gradientBluePink:
        return isChinese ? '高级渐变' : 'Advanced Gradient';
    }
  }
}
