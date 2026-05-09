# Assets 规范

这份规范用于统一桌游内容资源的目录结构、图片格式，以及规则资料的保存方式。

## 一、目录结构

每个桌游使用一个独立目录，统一放在：

```text
assets/games/<game_slug>/
```

推荐结构：

```text
assets/games/<game_slug>/
  images/
    cover.jpg
    background.jpg
  docs/
    rulebook_zh.md
    rulebook_en.md
    faq_zh.md
    faq_en.md
    rules_reference_zh.md          # 可选
    rules_reference_en.md          # 可选
    player_aid_zh.md               # 可选
    player_aid_en.md               # 可选
    campaign_guide_zh.md           # 可选
    campaign_guide_en.md           # 可选
    scenario_book_zh.md            # 可选
    scenario_book_en.md            # 可选
    supplement_zh.md               # 可选
    supplement_en.md               # 可选
    asset_index_zh.md              # 可选，记录官方来源与缺失项
    asset_index_en.md              # 可选
    rulebook_official_zh.pdf        # 可选
    rulebook_official_en.pdf        # 可选
    faq_official_zh.pdf             # 可选
    faq_official_en.pdf             # 可选
    rules_reference_official_zh.pdf # 可选
    rules_reference_official_en.pdf # 可选
    faq_errata_official_zh.pdf      # 可选
    faq_errata_official_en.pdf      # 可选
    player_aid_official_zh.pdf      # 可选
    player_aid_official_en.pdf      # 可选
    campaign_guide_official_zh.pdf  # 可选
    campaign_guide_official_en.pdf  # 可选
    scenario_book_official_zh.pdf   # 可选
    scenario_book_official_en.pdf   # 可选
    supplement_official_zh.pdf      # 可选
    supplement_official_en.pdf      # 可选
    rules_official_page.html        # 可选，官方网页规则
    faq_official_page.html          # 可选，官方网页FAQ
    player_aid_official.png         # 可选，官方图片类速查表
```

## 二、命名规范

### 1. game_slug

统一使用小写英文 + 下划线：

- `puerto_rico`
- `arkham_horror_lcg`
- `startups`

### 2. 图片文件名

统一先只使用 `jpg`：

- `cover.jpg`
- `background.jpg`

后续如果有多图扩展，建议继续统一：

- `gallery_01.jpg`
- `gallery_02.jpg`
- `gallery_03.jpg`

### 3. 文档文件名

- 中文规则书：`rulebook_zh.md`
- 英文规则书：`rulebook_en.md`
- 中文 FAQ：`faq_zh.md`
- 英文 FAQ：`faq_en.md`
- 中文规则参考：`rules_reference_zh.md`
- 英文规则参考：`rules_reference_en.md`
- 中文玩家速查：`player_aid_zh.md`
- 英文玩家速查：`player_aid_en.md`
- 中文战役指南：`campaign_guide_zh.md`
- 英文战役指南：`campaign_guide_en.md`
- 中文剧本手册：`scenario_book_zh.md`
- 英文剧本手册：`scenario_book_en.md`
- 中文补充规则：`supplement_zh.md`
- 英文补充规则：`supplement_en.md`
- 中文资料索引：`asset_index_zh.md`
- 英文资料索引：`asset_index_en.md`

若保留官方原 PDF：

- `rulebook_official_zh.pdf`
- `rulebook_official_en.pdf`
- `faq_official_zh.pdf`
- `faq_official_en.pdf`
- `rules_reference_official_zh.pdf`
- `rules_reference_official_en.pdf`
- `faq_errata_official_zh.pdf`
- `faq_errata_official_en.pdf`
- `player_aid_official_zh.pdf`
- `player_aid_official_en.pdf`
- `campaign_guide_official_zh.pdf`
- `campaign_guide_official_en.pdf`
- `scenario_book_official_zh.pdf`
- `scenario_book_official_en.pdf`
- `supplement_official_zh.pdf`
- `supplement_official_en.pdf`

若保留官方网页或图片资源：

- `rules_official_page.html`
- `faq_official_page.html`
- `player_aid_official.png`

## 三、图片规范

当前建议：

- 格式统一：`jpg`
- 封面图：竖图，尽量接近桌游盒封面
- 背景图：横图，适合卡片背景或详情页横幅
- 体积建议：
  - `cover.jpg`：尽量控制在 `300KB` 以内
  - `background.jpg`：尽量控制在 `1.5MB` 以内

如果后续准备统一替换现有 `webp`，建议逐步迁移，不要混用同一资源位的多个后缀。

## 四、Markdown 规则书规范

规则书 `.md` 建议统一采用以下结构：

```md
# 游戏名称规则书

## 游戏目标

用 2-5 句话说明这款游戏的核心目标。

## 组件概览

- 组件 1
- 组件 2
- 组件 3

## 游戏准备

- 准备步骤 1
- 准备步骤 2
- 准备步骤 3

## 回合流程

1. 步骤 1
2. 步骤 2
3. 步骤 3

## 核心规则

### 1. 小节标题

说明正文。

### 2. 小节标题

说明正文。

## 结算与胜利条件

说明游戏结束与计分方式。

## 常见易错点

- 易错点 1
- 易错点 2
- 易错点 3
```

## 五、Markdown 编写建议

- 一级标题只保留一个：`# 游戏名称规则书`
- 用 `##` 表示大章节
- 用 `###` 表示子规则
- 多使用短段落和项目列表
- 不要写“开发环境路径”“本地文件路径”“后续替换 PDF”这种对终端用户无意义的内容
- 规则文本优先写成适合手机阅读的版本，而不是原 PDF 的逐行转录

## 六、FAQ Markdown 规范

FAQ 推荐格式：

```md
# 游戏名称 FAQ

## 1. 问题标题

回答正文。

## 2. 问题标题

回答正文。
```

## 七、规则参考与速查建议

如果该游戏存在更偏“检索型”的资料，优先保留官方提供的原始格式，不强制要求一定转成 Markdown。

推荐优先检查并保留这些资料类型：

- `Rules Reference`
  - 常见形式：`pdf`、官方网页、少量情况下也可能是图片或可打印页
  - 用途：时机点、结算顺序、关键词、计分公式、优先级裁定
- `Player Aid / Quick Reference`
  - 常见形式：`pdf`、图片、可打印卡、官方网页
  - 用途：回合顺序、阶段摘要、结算速查、常见判定
- `Supplement / Variant / Solo Rules`
  - 常见形式：`pdf`、官方网页、规则附页
  - 用途：补充模块、变体、单人模式、河流/农夫/修道院长之类附加规则
- `Campaign Guide / Scenario Book`
  - 常见形式：`pdf`、官方网页、剧本手册
  - 用途：战役流程、剧本设置、章节规则、剧情推进
- `FAQ & Errata`
  - 常见形式：`pdf`、官方公告页、官方 FAQ 页面
  - 用途：常见问题、勘误、版本修订、争议裁定
- `asset_index_zh.md` / `asset_index_en.md`
  - 这是本地整理索引，建议保留为 Markdown
  - 用于记录这款游戏已找到的官方资料、对应文件名、资料类型、语言、来源、是否缺失

如果官方原件本身就是 `pdf`、`html`、`png/jpg` 等格式，就按官方原格式保留。

如果为了方便 AI 检索、手机阅读或摘要展示，额外补充这些 Markdown 版本也可以：

- `rules_reference_zh.md` / `rules_reference_en.md`
- `player_aid_zh.md` / `player_aid_en.md`
- `supplement_zh.md` / `supplement_en.md`

这些 Markdown 不是为了替代官方原件，而是作为本地可读摘要或检索辅助。

这几类资料不要求每个游戏都必须存在；如果官方有对应资料，优先保留官方原件，并在 `asset_index` 中注明来源。若额外整理了 Markdown 摘要，也应在 `asset_index` 中注明它是“本地整理版”而不是官方原件。

## 八、资料搜集建议

每次为新游戏搜集资料前，先阅读本文件一次，再按下面顺序检查：

- 官方游戏站点
- 官方发行商 / 出版社 / 代理商页面
- 官方规则 PDF、官方中文 PDF、官方网页规则
- 官方 FAQ / Errata / Supplement / Solo / Scenario / Campaign 页面或 PDF
- 官方图片类速查表、记分表、玩家辅助卡
- 若官方未公开，再补高可信来源，并在 `asset_index` 标明不是官方原件

建议对每个游戏至少检查这些类型是否存在：

- `Rulebook / Learn to Play`
- `Rules Reference`
- `FAQ & Errata`
- `Campaign Guide / Scenario Book`
- `Player Aid / Quick Reference`
- `Supplement / Variant / Solo Rules`

如果某类型没有找到，也要在 `asset_index_zh.md` 或 `asset_index_en.md` 中写明“未发现官方公开资源”，方便后续 AI 检索时知道这是“已检查但缺失”，而不是“尚未整理”。

## 九、当前建议

当前项目建议尽量统一成：

- 图片：全部改成 `jpg`
- 官方原件：优先按原格式保留，例如 `pdf`、`html`、`png/jpg`
- 本地摘要：在确有价值时，再补 `md`
- 规则书 / FAQ / 速查资料：不要为了统一而强行把官方原件转换成单一格式

这样可以最大程度减少运行时分支和资源格式混杂问题。
