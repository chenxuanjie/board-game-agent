import '../models/app_language.dart';
import '../models/game_info.dart';

class GameCatalog {
  static List<GameInfo> allGames(AppLanguage language) {
    return <GameInfo>[
      puertoRico(language),
      arkhamHorrorLcg(language),
      startups(language),
    ];
  }

  static GameInfo puertoRico(AppLanguage language) {
    if (language == AppLanguage.zhHans) {
      return GameInfo(
        id: 'puerto-rico',
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
}
