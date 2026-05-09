import '../models/app_language.dart';
import '../models/game_info.dart';

class GameCatalog {
  static List<GameInfo> allGames(AppLanguage language) {
    return <GameInfo>[
      puertoRico(language),
      arkhamHorrorLcg(language),
      startups(language),
      cabo(language),
      carcassonne3(language),
    ];
  }

  static GameInfo puertoRico(AppLanguage language) {
    if (language == AppLanguage.zhHans) {
      return GameInfo(
        id: 'puerto-rico',
        slug: 'puerto_rico',
        title: '波多黎各',
        subtitle: 'Puerto Rico',
        coverAssetPath: 'assets/games/puerto_rico/images/cover.jpg',
        bannerAssetPath: 'assets/games/puerto_rico/images/background.jpg',
        cardAccent: 0xFFB7834D,
        score: '8.3',
        scoreCountLabel: '4406人打分',
        releaseYear: '2020',
        categoryLine: '竞争 / 德式',
        learningDifficulty: '6/10 级',
        perPlayerTime: '35 分钟/人',
        setupTime: '10-20 分钟',
        languageRequirement: '适中',
        supportedPlayers: <int>[2, 3, 4, 5],
        recommendedPlayer: 4,
        rankBadges: <String>['集石排行 #104', '热门排行 #74', '桌游排行 #91', '德式游戏排行 #35'],
        rulebookAssetPath: 'assets/games/puerto_rico/docs/rulebook_zh.md',
        faqAssetPath: 'assets/games/puerto_rico/docs/faq_zh.md',
        heroTagline: '殖民、种植、生产、装船，在有限角色选择中滚起经济雪球。',
        summary: '《波多黎各》是一款经典中重策桌游。玩家通过选择角色、发展建筑、经营种植园和装运货物来积累胜利点。',
        mentorPitch: '这个 AI 页面适合边玩边问，例如“市长阶段怎么结算”“采石场什么时候生效”“港口和码头能不能一起用”。',
        playTime: '90-150 分钟',
        playerCount: '3-5 人',
        complexity: '中重',
        roundFlow: <String>[
          '本轮起始玩家选择一个角色，顺时针每人依次执行该角色行动。',
          '选择者会得到特权，其他玩家执行同一角色时没有这个额外奖励。',
          '常见轮次围绕种植、建筑、生产、商人、船长和市长展开。',
          '当殖民者、胜利点指示物或建筑空位等终局条件触发时，游戏结束并结算。',
        ],
        assistantSkills: <String>[
          '快速解释回合结构和角色优先级',
          '回答建筑、采石场、货船装载等规则问题',
          '帮新手理解一回合该关注什么',
          '以后接入真实 API 后，可进一步做策略建议和局面分析',
        ],
        quickPrompts: <String>[
          '市长阶段是怎么结算的？',
          '码头和港口有什么区别？',
          '船长阶段如何计算得分？',
          '我这回合先建造还是先生产更好？',
        ],
      );
    }

    return GameInfo(
      id: 'puerto-rico',
      slug: 'puerto_rico',
      title: 'Puerto Rico',
      subtitle: 'Puerto Rico',
      coverAssetPath: 'assets/games/puerto_rico/images/cover.jpg',
      bannerAssetPath: 'assets/games/puerto_rico/images/background.jpg',
      cardAccent: 0xFFB7834D,
      score: '8.3',
      scoreCountLabel: '4,406 ratings',
      releaseYear: '2020',
      categoryLine: 'Competitive / Euro',
      learningDifficulty: '6/10',
      perPlayerTime: '35 min/player',
      setupTime: '10-20 min',
      languageRequirement: 'Moderate',
      supportedPlayers: <int>[2, 3, 4, 5],
      recommendedPlayer: 4,
      rankBadges: <String>[
        'Geek #104',
        'Hot #74',
        'Board Game #91',
        'Euro #35',
      ],
      rulebookAssetPath: 'assets/games/puerto_rico/docs/rulebook_zh.md',
      faqAssetPath: 'assets/games/puerto_rico/docs/faq_zh.md',
      heroTagline:
          'Choose roles, grow plantations, build engines, and ship goods before the table catches up.',
      summary:
          'Puerto Rico is a classic medium-heavy board game where players time role selection, buildings, plantations, and shipping to turn production into victory points.',
      mentorPitch:
          'This assistant is designed for live table questions such as “How does Mayor resolve?”, “When does the quarry discount apply?”, or “Can I use Harbor and Wharf together?”.',
      playTime: '90-150 min',
      playerCount: '3-5 players',
      complexity: 'Medium-heavy',
      roundFlow: <String>[
        'The current governor chooses a role, then everyone around the table resolves that same role.',
        'The chooser gets the privilege, while the others only get the base effect.',
        'Typical rounds revolve around Settler, Builder, Craftsman, Trader, Captain, and Mayor.',
        'The game ends once a major end condition is triggered, then all remaining points are counted.',
      ],
      assistantSkills: <String>[
        'Explain turn flow and role timing in plain language',
        'Answer rules about buildings, quarries, shipping, and scoring',
        'Help new players focus on what matters in the current round',
        'Support deeper strategy once a real AI API is connected',
      ],
      quickPrompts: <String>[
        'How does the Mayor phase resolve?',
        'What is the difference between Harbor and Wharf?',
        'How does scoring work in the Captain phase?',
        'Should I build first or produce first this round?',
      ],
    );
  }

  static GameInfo arkhamHorrorLcg(AppLanguage language) {
    if (language == AppLanguage.zhHans) {
      return GameInfo(
        id: 'arkham-horror-lcg',
        slug: 'arkham_horror_lcg',
        title: '诡镇奇谈',
        subtitle: 'Arkham Horror: The Card Game',
        coverAssetPath: 'assets/games/arkham_horror_lcg/images/cover.webp',
        bannerAssetPath:
            'assets/games/arkham_horror_lcg/images/background.webp',
        cardAccent: 0xFF7F5A8F,
        score: '8.1',
        scoreCountLabel: '4.7万人打分',
        releaseYear: '2016',
        categoryLine: '合作 / 叙事卡牌',
        learningDifficulty: '7/10 级',
        perPlayerTime: '30-45 分钟/人',
        setupTime: '10-15 分钟',
        languageRequirement: '较高',
        supportedPlayers: <int>[1, 2, 3, 4],
        recommendedPlayer: 2,
        rankBadges: <String>['BGG总榜 #32', '自定义卡牌 #2', '主题游戏 #13'],
        rulebookAssetPath: 'assets/games/arkham_horror_lcg/docs/rulebook_zh.md',
        faqAssetPath:
            'assets/games/arkham_horror_lcg/docs/faq_official_v25_en.pdf',
        heroTagline: '调查、构筑、判定、战役推进，在克苏鲁迷雾里和队友一起破局。',
        summary: '《诡镇奇谈：卡牌版》是一款剧情战役驱动的合作卡牌桌游。玩家扮演调查员，在场景推进、敌人压力与有限资源之间寻找生路。',
        mentorPitch: '这个 AI 页面适合边打边问，例如“攻击机会是什么时候触发”“线索与推进如何结算”“闪避后敌人怎么放置”。',
        playTime: '60-120 分钟',
        playerCount: '1-4 人',
        complexity: '中重',
        roundFlow: <String>[
          '每轮通常依次经历神话阶段、调查阶段和敌人阶段。',
          '调查员阶段里，玩家轮流使用 3 个行动来移动、调查、战斗、闪避或打牌。',
          '神话阶段会抽遭遇卡并提高场景压力，敌人阶段则会让已交战敌人反击。',
          '每个剧本都会通过线索推进主线，并根据结局影响后续战役。',
        ],
        assistantSkills: <String>[
          '解释行动时机、攻击机会、敌人交战等核心规则',
          '帮助新玩家理解调查、资源、技能判定和战役推进',
          '快速回答不同卡牌之间的互动问题',
          '后续接真实 API 后，可结合多剧本知识库统一答疑',
        ],
        quickPrompts: <String>[
          '什么情况下会触发攻击机会？',
          '闪避成功后敌人放在哪里？',
          '调查和发现线索有什么区别？',
          '同一个敌人什么时候会再次交战？',
        ],
      );
    }

    return GameInfo(
      id: 'arkham-horror-lcg',
      slug: 'arkham_horror_lcg',
      title: 'Arkham Horror',
      subtitle: 'Arkham Horror: The Card Game',
      coverAssetPath: 'assets/games/arkham_horror_lcg/images/cover.webp',
      bannerAssetPath: 'assets/games/arkham_horror_lcg/images/background.webp',
      cardAccent: 0xFF7F5A8F,
      score: '8.1',
      scoreCountLabel: '47K ratings',
      releaseYear: '2016',
      categoryLine: 'Co-op / Narrative Card Game',
      learningDifficulty: '7/10',
      perPlayerTime: '30-45 min/player',
      setupTime: '10-15 min',
      languageRequirement: 'Higher',
      supportedPlayers: <int>[1, 2, 3, 4],
      recommendedPlayer: 2,
      rankBadges: <String>[
        'BGG Overall #32',
        'Customizable #2',
        'Thematic #13',
      ],
      rulebookAssetPath: 'assets/games/arkham_horror_lcg/docs/rulebook_en.md',
      faqAssetPath:
          'assets/games/arkham_horror_lcg/docs/faq_official_v25_en.pdf',
      heroTagline:
          'Investigate, build decks, pass tests, and survive a campaign where the mythos keeps pushing back.',
      summary:
          'Arkham Horror: The Card Game is a campaign-driven cooperative card game where investigators balance clues, enemies, horror, and limited actions to survive each scenario.',
      mentorPitch:
          'This AI page is useful mid-game for questions like “When does an attack of opportunity happen?”, “How do clues advance the act?”, or “Where does an exhausted enemy go after evade?”.',
      playTime: '60-120 min',
      playerCount: '1-4 players',
      complexity: 'Medium-heavy',
      roundFlow: <String>[
        'Each round usually flows through mythos, investigator, and enemy phases.',
        'During the investigator phase, players spend three actions on movement, investigate, fight, evade, and card play.',
        'The mythos phase raises pressure with encounter cards, while the enemy phase makes engaged enemies strike back.',
        'Each scenario advances through clues and story outcomes that carry into the wider campaign.',
      ],
      assistantSkills: <String>[
        'Explain timing windows, attacks of opportunity, and enemy engagement',
        'Help newer players understand investigation, resources, tests, and campaign flow',
        'Answer interaction questions between different card effects',
        'Support unified knowledge-base answers once a real AI API is connected',
      ],
      quickPrompts: <String>[
        'When does an attack of opportunity trigger?',
        'Where does an enemy go after a successful evade?',
        'What is the difference between investigating and discovering clues?',
        'When does an enemy engage again?',
      ],
    );
  }

  static GameInfo startups(AppLanguage language) {
    if (language == AppLanguage.zhHans) {
      return GameInfo(
        id: 'startups',
        slug: 'startups',
        title: '初创公司',
        subtitle: 'Startups',
        coverAssetPath: 'assets/games/startups/images/cover.jpg',
        bannerAssetPath: 'assets/games/startups/images/background.jpg',
        cardAccent: 0xFF31A266,
        score: '7.2',
        scoreCountLabel: '轻中策派对卡牌',
        releaseYear: '2017',
        categoryLine: '竞争 / 卡牌 / Oink',
        learningDifficulty: '3/10 级',
        perPlayerTime: '20 分钟',
        setupTime: '3-5 分钟',
        languageRequirement: '低',
        supportedPlayers: <int>[3, 4, 5, 6, 7],
        recommendedPlayer: 5,
        rankBadges: <String>['Oink 代表作', '3-7 人', '20 分钟'],
        rulebookAssetPath: 'assets/games/startups/docs/rulebook_zh.md',
        faqAssetPath: 'assets/games/startups/docs/faq_zh.md',
        heroTagline: '押注六家创业公司，在大股东与反垄断筹码之间读人、抢位、赚得最多。',
        summary: '《初创公司》是一款节奏很快的竞争卡牌游戏。玩家通过投资不同公司、观察对手手牌和时机，争夺“最大股东”位置来赢取分数。',
        mentorPitch: '这个页面适合边玩边问，例如“平手怎么算”“手里的隐藏牌算不算持股”“反垄断筹码什么时候用最好”。',
        playTime: '20 分钟',
        playerCount: '3-7 人',
        complexity: '轻中',
        roundFlow: <String>[
          '每位玩家轮流从手牌中打出一张公司卡，逐步形成各公司的公开持股情况。',
          '部分公司会随着投资增加而变得更值钱，但只有最大股东才能拿走该公司的收益。',
          '玩家可以利用反垄断筹码干扰某家公司结算，从而打乱领先者节奏。',
          '所有回合结束后，根据各公司收益和筹码结算总分，最高者获胜。',
        ],
        assistantSkills: <String>[
          '解释平手、反垄断筹码、大股东判定等基础规则',
          '帮助新玩家理解节奏很快的读人与抢位逻辑',
          '总结六家公司之间的收益变化思路',
          '后续可结合更多 FAQ 做局中快速答疑',
        ],
        quickPrompts: <String>[
          '平手时谁算最大股东？',
          '手中的隐藏牌算持股吗？',
          '反垄断筹码什么时候生效？',
          '这游戏新手最容易犯什么错？',
        ],
      );
    }

    return GameInfo(
      id: 'startups',
      slug: 'startups',
      title: 'Startups',
      subtitle: 'Startups',
      coverAssetPath: 'assets/games/startups/images/cover.jpg',
      bannerAssetPath: 'assets/games/startups/images/background.jpg',
      cardAccent: 0xFF31A266,
      score: '7.2',
      scoreCountLabel: 'Fast investor card game',
      releaseYear: '2017',
      categoryLine: 'Competitive / Card Game / Oink',
      learningDifficulty: '3/10',
      perPlayerTime: '20 min',
      setupTime: '3-5 min',
      languageRequirement: 'Low',
      supportedPlayers: <int>[3, 4, 5, 6, 7],
      recommendedPlayer: 5,
      rankBadges: <String>['Oink Signature', '3-7 Players', '20 Minutes'],
      rulebookAssetPath: 'assets/games/startups/docs/rulebook_en.md',
      faqAssetPath: 'assets/games/startups/docs/faq_zh.md',
      heroTagline:
          'Invest in six companies, read your rivals, and use anti-monopoly chips to profit as the biggest shareholder.',
      summary:
          'Startups is a fast competitive card game where players invest in different companies, read each other’s plans, and fight for majority ownership to score the most money.',
      mentorPitch:
          'This page is ideal for mid-game questions such as “How are ties resolved?”, “Do hidden cards count as shares?”, or “When should I use the anti-monopoly chip?”.',
      playTime: '20 min',
      playerCount: '3-7 players',
      complexity: 'Light-medium',
      roundFlow: <String>[
        'Players take turns playing one company card from hand to build each company’s public investment stack.',
        'Some companies become more valuable as they grow, but only the biggest shareholder earns from that company.',
        'Anti-monopoly chips can disrupt a company payout and punish obvious leaders.',
        'After all turns are complete, company payouts and chips are scored, and the highest total wins.',
      ],
      assistantSkills: <String>[
        'Explain majority ownership, ties, and anti-monopoly timing',
        'Help new players understand the read-your-rivals tempo',
        'Summarize how the six companies differ in value pressure',
        'Support quick rules clarifications with saved FAQ notes',
      ],
      quickPrompts: <String>[
        'Who wins a tie for biggest shareholder?',
        'Do hidden cards count as shares?',
        'When does the anti-monopoly chip matter?',
        'What mistake do new players make most often?',
      ],
    );
  }

  static GameInfo cabo(AppLanguage language) {
    if (language == AppLanguage.zhHans) {
      return GameInfo(
        id: 'cabo',
        slug: 'cabo',
        title: 'Cabo',
        subtitle: 'Cabo',
        coverAssetPath: 'assets/games/cabo/images/cover.jpg',
        bannerAssetPath: 'assets/games/cabo/images/background.jpg',
        cardAccent: 0xFFCC6A2F,
        score: '7.0',
        scoreCountLabel: '记忆 / 推理 / 小盒卡牌',
        releaseYear: '2010',
        categoryLine: '竞争 / 记忆 / 卡牌',
        learningDifficulty: '3/10 级',
        perPlayerTime: '15-30 分钟',
        setupTime: '2 分钟',
        languageRequirement: '低',
        supportedPlayers: <int>[2, 3, 4, 5],
        recommendedPlayer: 4,
        rankBadges: <String>['2-5 人', '轻策略', '便携小盒'],
        rulebookAssetPath: 'assets/games/cabo/docs/rulebook_zh.md',
        faqAssetPath: 'assets/games/cabo/docs/faq_zh.md',
        knowledgeAssetPaths: <String>[
          'assets/games/cabo/docs/rulebook_zh.md',
          'assets/games/cabo/docs/rules_reference_zh.md',
          'assets/games/cabo/docs/faq_zh.md',
          'assets/games/cabo/docs/asset_index_zh.md',
        ],
        heroTagline: '记住自己的低分牌，偷看、交换、诈唬，在喊出 Cabo 的那一刻赌一把。',
        summary: '《Cabo》是一款节奏很快的记忆与推理卡牌游戏。玩家只知道自己部分手牌，通过抽牌、替换、偷看和交换来努力把总点数压到最低。',
        mentorPitch: '这个页面适合边玩边问，例如“从弃牌堆拿到行动牌能不能发动”“喊 Cabo 之后别人还有没有回合”“配对失败会怎样”。',
        playTime: '15-30 分钟',
        playerCount: '2-5 人',
        complexity: '轻',
        roundFlow: <String>[
          '每轮开始时，每位玩家有 4 张盖牌，只能先查看其中 2 张。',
          '轮到你时，要么抽牌后决定如何处理，要么从弃牌堆顶拿牌替换，要么直接宣告 Cabo。',
          '行动牌能让你偷看自己、偷看别人，或在不看牌的情况下交换牌位。',
          '一旦有人宣告 Cabo，其余玩家各再行动 1 次，然后所有人亮牌并结算分数。',
        ],
        assistantSkills: <String>[
          '解释 Cabo 宣告、平手、额外 5 分惩罚等轮末结算',
          '澄清 Peek / Spy / Swap 的使用时机',
          '解释配对消牌、抽牌堆重洗和特殊计分',
          '优先引用本地整理的官方规则、FAQ 与资料索引',
        ],
        quickPrompts: <String>[
          '从弃牌堆拿到 Swap 能发动吗？',
          '喊 Cabo 后其他玩家还会行动吗？',
          '配对失败后要怎么处理？',
          '平手时谁会记 0 分？',
        ],
      );
    }

    return GameInfo(
      id: 'cabo',
      slug: 'cabo',
      title: 'Cabo',
      subtitle: 'Cabo',
      coverAssetPath: 'assets/games/cabo/images/cover.jpg',
      bannerAssetPath: 'assets/games/cabo/images/background.jpg',
      cardAccent: 0xFFCC6A2F,
      score: '7.0',
      scoreCountLabel: 'Memory bluff card game',
      releaseYear: '2010',
      categoryLine: 'Competitive / Memory / Card Game',
      learningDifficulty: '3/10',
      perPlayerTime: '15-30 min',
      setupTime: '2 min',
      languageRequirement: 'Low',
      supportedPlayers: <int>[2, 3, 4, 5],
      recommendedPlayer: 4,
      rankBadges: <String>['2-5 Players', 'Portable Box', 'Light Strategy'],
      rulebookAssetPath: 'assets/games/cabo/docs/rulebook_en.md',
      faqAssetPath: 'assets/games/cabo/docs/faq_en.md',
      knowledgeAssetPaths: <String>[
        'assets/games/cabo/docs/rulebook_en.md',
        'assets/games/cabo/docs/rules_reference_en.md',
        'assets/games/cabo/docs/faq_en.md',
        'assets/games/cabo/docs/asset_index_en.md',
      ],
      heroTagline:
          'Remember your low cards, bluff with incomplete information, and call Cabo at exactly the right moment.',
      summary:
          'Cabo is a fast card game of memory, deduction, and risk timing. Players only know part of their hand and use peeks, swaps, and replacements to finish each round with the lowest total.',
      mentorPitch:
          'This page is ideal for live questions such as “Can I use an action card from the discard pile?”, “Do other players still get turns after Cabo is called?”, or “What happens after a failed match attempt?”.',
      playTime: '15-30 min',
      playerCount: '2-5 players',
      complexity: 'Light',
      roundFlow: <String>[
        'Each round begins with 4 face-down cards per player, and each player only checks 2 of their own cards.',
        'On your turn, you either draw and resolve a card, take the top discard to replace a card, or call Cabo.',
        'Action cards let you peek at your own cards, spy on others, or swap unseen cards.',
        'Once Cabo is called, every other player gets one final turn before reveal and scoring.',
      ],
      assistantSkills: <String>[
        'Explain Cabo timing, ties, and the failed-call penalty',
        'Clarify when Peek, Spy, and Swap may be used',
        'Walk through matching, redraw, and special scoring rules',
        'Prioritize the local rulebook, FAQ, and official-source notes',
      ],
      quickPrompts: <String>[
        'Can I use Swap from the discard pile?',
        'Do other players still act after Cabo is called?',
        'What happens if my match attempt is wrong?',
        'Who gets 0 points on a tie?',
      ],
    );
  }

  static GameInfo carcassonne3(AppLanguage language) {
    if (language == AppLanguage.zhHans) {
      return GameInfo(
        id: 'carcassonne-3',
        slug: 'carcassonne_3',
        title: '卡卡颂 3.0',
        subtitle: 'Carcassonne',
        coverAssetPath: 'assets/games/carcassonne_3/images/cover.jpg',
        bannerAssetPath: 'assets/games/carcassonne_3/images/background.jpg',
        cardAccent: 0xFF8B6A32,
        score: '8.0',
        scoreCountLabel: '拼板经典 / Hans im Glück 3.0',
        releaseYear: '2023',
        categoryLine: '竞争 / 拼板 / 区控',
        learningDifficulty: '4/10 级',
        perPlayerTime: '30-45 分钟',
        setupTime: '3-5 分钟',
        languageRequirement: '低',
        supportedPlayers: <int>[2, 3, 4, 5],
        recommendedPlayer: 4,
        rankBadges: <String>['经典拼板', '地块放置', '新版 3.0'],
        rulebookAssetPath: 'assets/games/carcassonne_3/docs/rulebook_zh.md',
        faqAssetPath: 'assets/games/carcassonne_3/docs/faq_zh.md',
        knowledgeAssetPaths: <String>[
          'assets/games/carcassonne_3/docs/rulebook_zh.md',
          'assets/games/carcassonne_3/docs/rules_reference_zh.md',
          'assets/games/carcassonne_3/docs/supplement_zh.md',
          'assets/games/carcassonne_3/docs/faq_zh.md',
          'assets/games/carcassonne_3/docs/asset_index_zh.md',
        ],
        heroTagline: '铺路、筑城、占修道院，再用时机和多数判定把每一块地都变成分数。',
        summary: '《卡卡颂 3.0》是经典地块拼放桌游的新版本基础套装。玩家通过放置地块和追随者，争夺道路、城市、修道院与终局田地的得分。',
        mentorPitch: '这个页面适合边玩边问，例如“这块地能不能放人”“什么时候立刻得分”“终局未完成城市怎么算”“农夫和修道院长怎么结算”。',
        playTime: '30-45 分钟',
        playerCount: '2-5 人',
        complexity: '轻中',
        roundFlow: <String>[
          '回合开始先抽 1 块地，并以边缘地形匹配的方式放到地图上。',
          '放好后，你可以选择是否在刚放下的地块上放 1 个追随者。',
          '若这次放置让道路、城市或修道院完成，则立即结算得分并收回对应追随者。',
          '当常规地块耗尽后进行终局结算，未完成区域与田地按终局规则得分。',
        ],
        assistantSkills: <String>[
          '解释占位限制、连通规则与多数判定',
          '区分局中得分和终局得分',
          '回答农夫、河流、修道院长等官方补充规则',
          '优先引用本地整理的官方规则书、补充规则与资料索引',
        ],
        quickPrompts: <String>[
          '这条路已经连通了，还能再放追随者吗？',
          '终局未完成城市怎么算分？',
          '农夫什么时候计分？',
          '修道院长什么时候可以收回？',
        ],
      );
    }

    return GameInfo(
      id: 'carcassonne-3',
      slug: 'carcassonne_3',
      title: 'Carcassonne 3.0',
      subtitle: 'Carcassonne',
      coverAssetPath: 'assets/games/carcassonne_3/images/cover.jpg',
      bannerAssetPath: 'assets/games/carcassonne_3/images/background.jpg',
      cardAccent: 0xFF8B6A32,
      score: '8.0',
      scoreCountLabel: 'Classic tile-laying evergreen',
      releaseYear: '2023',
      categoryLine: 'Competitive / Tile Laying / Area Control',
      learningDifficulty: '4/10',
      perPlayerTime: '30-45 min',
      setupTime: '3-5 min',
      languageRequirement: 'Low',
      supportedPlayers: <int>[2, 3, 4, 5],
      recommendedPlayer: 4,
      rankBadges: <String>['Classic', 'Tile Laying', 'Version 3.0'],
      rulebookAssetPath: 'assets/games/carcassonne_3/docs/rulebook_en.md',
      faqAssetPath: 'assets/games/carcassonne_3/docs/faq_en.md',
      knowledgeAssetPaths: <String>[
        'assets/games/carcassonne_3/docs/rulebook_en.md',
        'assets/games/carcassonne_3/docs/rules_reference_en.md',
        'assets/games/carcassonne_3/docs/supplement_en.md',
        'assets/games/carcassonne_3/docs/faq_en.md',
        'assets/games/carcassonne_3/docs/asset_index_en.md',
      ],
      heroTagline:
          'Grow roads, close cities, and time your meeples so each tile adds points instead of helping your rivals.',
      summary:
          'Carcassonne 3.0 is the modern base version of the classic tile-laying game. Players place land tiles, commit followers to features, and fight for scoring tempo across roads, cities, monasteries, and later fields.',
      mentorPitch:
          'This page works well for questions like “Can I place here if the road is already connected?”, “How do incomplete cities score at the end?”, or “How do farmers and abbots work in the supplement?”.',
      playTime: '30-45 min',
      playerCount: '2-5 players',
      complexity: 'Light-medium',
      roundFlow: <String>[
        'Start each turn by drawing and legally placing 1 landscape tile.',
        'Then optionally place 1 follower on the tile you just placed.',
        'Any roads, cities, or monasteries completed by that placement score immediately.',
        'Once the land tiles run out, score all incomplete features and any active field scoring.',
      ],
      assistantSkills: <String>[
        'Explain occupancy limits, connection timing, and majority scoring',
        'Distinguish in-game scoring from final scoring',
        'Answer official supplement rules for farmers, the river, and the abbot',
        'Prioritize the local official-rule summaries and asset index',
      ],
      quickPrompts: <String>[
        'Can I place on this road if it is already connected?',
        'How do incomplete cities score at the end?',
        'When do farmers score?',
        'When may I remove my abbot?',
      ],
    );
  }
}
