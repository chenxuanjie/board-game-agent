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
  String get featuredGameCount => isChinese ? '2 个桌游' : '2 board games';
  String get openSettings => isChinese ? '语言与语音' : 'Language and voice';
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
  String get aiStatusDefaultReady =>
      isChinese ? '默认可用' : 'Ready by default';
  String get assetTestDone =>
      isChinese ? '资源访问测试完成' : 'Asset access test completed';
  String get dialogClose => isChinese ? '关闭' : 'Close';
  String get voiceReplyTitle => isChinese ? 'AI 回答朗读' : 'AI voice reply';
  String get voiceReplyHint => isChinese
      ? '打开后，AI 回复会自动朗读。'
      : 'When enabled, assistant replies are spoken aloud.';
  String get voiceReplySwitchLabel => isChinese ? '语音朗读' : 'Voice output';
  String get enterAssistant => isChinese ? '进入 AI 助手' : 'Open AI Assistant';
  String get assistantMode => isChinese ? '模拟模式' : 'Mock mode';
  String get assistantModeHint => isChinese
      ? '当前助手已接入真实 AI，可直接继续追问规则、流程和策略相关问题。'
      : 'The assistant is connected to a live AI backend and can answer rules, flow, and strategy questions.';
  String get askAnything => isChinese ? '现在就问它' : 'Ask anything now';
  String get helperSectionTitle =>
      isChinese ? '这个版本已经能做什么' : 'What this build already does';
  String get futureSectionTitle =>
      isChinese ? '下一步接真实 AI 时' : 'When you wire in a real AI later';
  String get homeSearchHint => isChinese ? '搜索桌游...' : 'Search games...';
  String get favouritesOnly => isChinese ? '只看收藏' : 'Show favourites only';
  String get globalAiTitle => isChinese ? '通用 AI 助手' : 'Global AI Assistant';
  String get globalAiSubtitle => isChinese
      ? '后续可结合全部桌游知识库统一答疑'
      : 'A unified AI entry for answers across every game knowledge base';
  String get gameLibraryTitle => isChinese ? '桌游列表' : 'Game Library';
  String get allKnowledgeGreeting => isChinese
      ? '这里是通用 AI 助手入口。它会结合不同桌游上下文，为你统一回答问题。'
      : 'This is the global AI helper. It can answer questions across different board game contexts.';
  String assistantGreetingFor(String gameTitle) => isChinese
      ? '欢迎来到《$gameTitle》AI 助手。你可以直接提问规则、流程、术语或策略相关问题，也可以点击麦克风尝试语音输入。'
      : 'Welcome to the $gameTitle assistant. Ask about rules, flow, terminology, or strategy, and use the microphone if speech input is available.';
  String get messageHint => isChinese
      ? '问规则、流程、建筑、殖民者...'
      : 'Ask about rules, rounds, buildings, or colonists...';
  String get listening => '...';
  String get tapToStop => isChinese ? '点击停止录音' : 'Tap to stop recording';
  String get micUnavailable => isChinese
      ? '当前设备未就绪，语音识别不可用。'
      : 'Speech recognition is unavailable on this device right now.';
  String get clearChat => isChinese ? '清空对话' : 'Clear chat';
  String get quickPromptsTitle => isChinese ? '快速提问' : 'Quick prompts';
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
  String editionLabelFor(String gameId) {
    if (!isChinese) {
      if (gameId == 'puerto-rico') {
        return 'Deluxe Edition';
      }
      if (gameId == 'arkham-horror-lcg') {
        return 'Card Game';
      }
      return '';
    }

    if (gameId == 'puerto-rico') {
      return '豪华版';
    }
    if (gameId == 'arkham-horror-lcg') {
      return '卡牌版';
    }
    return '';
  }

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

  String colorSchemeName(ColorSchemeOption scheme) {
    switch (scheme) {
      case ColorSchemeOption.classic:
        return isChinese ? '默认深色' : 'Classic Dark';
      case ColorSchemeOption.gradientBluePink:
        return isChinese ? '高级渐变' : 'Advanced Gradient';
    }
  }
}
