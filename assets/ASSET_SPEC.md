# Assets 规范

这份规范统一桌游资源的目录、文件名、来源标记和 AI 使用登记方式。每款桌游都必须使用独立的 `assets/games/<game_slug>/` 目录。

## 一、标准目录架构

即使暂时没有资料，也保留对应的空目录，作为每款桌游的统一模板：

```text
assets/games/<game_slug>/
├── game.json
│   # 应用展示信息、图片入口、规则书和 FAQ 主入口
├── manifest.json
│   # 所有资源清单、来源、状态、AI 开关和优先级
├── images/
│   # 应用使用的封面、背景和展示图片
│   ├── cover.jpg
│   ├── background.jpg
│   └── gallery/
└── docs/
    ├── official/
    │   # 官方资料
    │   ├── rules/
    │   │   # 规则书、入门规则、规则参考、变体规则、扩展规则
    │   ├── answers/
    │   │   # 官方 FAQ、勘误、官方规则问答
    │   └── other/
    │       # 官方玩家辅助、记分表、网页快照、宣传资料、图片
    ├── community/
    │   # 社区资料
    │   ├── rules/
    │   │   # 社区规则整理和玩法说明
    │   ├── answers/
    │   │   # 社区 FAQ、论坛问答、规则裁定
    │   └── other/
    │       # 社区玩家辅助、图片、变体附件
    ├── local/
    │   # 本地整理资料
    │   ├── knowledge/
    │   │   # 为 AI 或应用阅读整理的 Markdown
    │   ├── index/
    │   │   # asset_index_cn.md / asset_index_en.md 等资料索引
    │   └── notes/
    │       # 内部整理、审核和迁移记录
    └── others/
        # 暂时无法归类但需要保留的资料
        ├── raw/
        │   # 尚未清洗的原始下载文件
        └── archive/
            # 历史版本和暂时停用的文件
```

目录归类原则：

- 资料来源决定一级目录：官方放 `official`，社区放 `community`，本地整理放 `local`。
- 资料类型决定二级目录：规则放 `rules`，问答、FAQ、勘误放 `answers`，其他辅助资料放 `other`。
- `local/knowledge` 只放本地整理的 Markdown，不放原始 PDF、HTML、PNG 或 JPG。
- 无法判断来源或用途、但需要暂时保留的文件放 `others/raw`；历史或停用文件放 `others/archive`。
- 不要复制同一个文件到多个目录；在 `manifest.json` 中登记源文件和派生关系。

## 二、文件命名规范

### 1. 游戏目录

使用小写英文和下划线：

- `cabo`
- `puerto_rico`
- `castles_of_burgundy_2019`

### 2. 语言后缀

文件名统一使用：

- `en`：英文；
- `cn`：中文；
- `multi`：多语言混合；
- 无语言属性的图片或资料不强行添加语言后缀。

`zhHans` 只作为应用内部 locale 键，不用于文件名。

### 3. 文档名称

根据资料类型使用稳定名称：

- `rulebook_en.pdf` / `rulebook_cn.pdf`
- `how_to_play_en.html` / `how_to_play_cn.html`
- `rules_reference_en.pdf` / `rules_reference_cn.pdf`
- `faq_en.pdf` / `faq_cn.pdf`
- `errata_en.pdf` / `errata_cn.pdf`
- `player_aid_en.pdf` / `player_aid_cn.pdf`
- `variant_en.pdf` / `variant_cn.pdf`
- `rulebook_en.md` / `rulebook_cn.md`
- `faq_en.md` / `faq_cn.md`
- `ruling_<topic>_en.md` / `ruling_<topic>_cn.md`
- `rules_reference_en.md` / `rules_reference_cn.md`

来源由目录和 `manifest.json.sourceClass` 表示，文件名不要重复写 `official` 或 `community`。例如使用 `docs/official/rules/rulebook_en.pdf`，不使用 `official_rulebook_en.pdf`。

### 4. 图片名称

- 应用主图固定为 `images/cover.jpg` 和 `images/background.jpg`。
- 画廊图片放入 `images/gallery/`，使用 `gallery_01.jpg`、`gallery_02.jpg` 等名称。
- 其他资料图片使用描述性名称，例如 `score_sheet.png`、`expert_variant.png`。
- 图片本身没有语言信息时，不添加 `_en` 或 `_cn`。

### 5. 索引名称

固定使用：

- `docs/local/index/asset_index_cn.md`
- `docs/local/index/asset_index_en.md`

## 三、manifest.json 规则

`manifest.json` 是该游戏所有资源的登记表，不再维护单独的顶层 `knowledge` 路径数组。

每个 `resources[]` 项必须包含：

```text
id, path, documentType, sourceClass, origin, language, edition,
status, enabled, aiEnabled, priority, derivedFrom, sourceUrl,
reviewStatus, notes
```

关键约束：

- `path` 必须存在且是相对该桌游目录的非空路径，统一使用 `/`，不能使用绝对路径或 `..`。
- 预期路径明确但文件缺失时，保留记录并使用 `status: "missing"`、`enabled: false`、`aiEnabled: false`。
- `enabled` 表示资源记录是否参与应用资源管理，不表示是否提供给 AI。
- `aiEnabled` 是是否允许把资源作为 AI 输入的唯一显式开关。
- AI 有效候选还必须满足 `status: "available"`、文件真实存在，并且当前检索器支持该格式。
- 当前检索器只直接读取 Markdown；PDF、HTML、PNG / JPG 需要后续解析支持，不能仅凭 `aiEnabled` 就声称已进入 AI。
- `priority` 数值越小越优先；当前程序会在选择语言匹配的资源时按该字段排序。
- `sourceClass` 推荐使用 `official`、`official_extracted`、`official_translated`、`community`、`local_translated`、`local_derived`、`unknown`。
- 提取方式、翻译方向、源文件和目标文件关系暂时记录在 `notes`；不创建复杂的嵌套 `derivation` 对象。

## 四、图片规范

- `cover.jpg` 使用桌游盒或封面主图，`background.jpg` 使用适合详情页的横向图片。
- 优先下载官方可获得的清晰原图，不使用聊天预览图、缩略图或明显裁剪图。
- 如果原图不超过 100MB，原则上保留原图或只做必要的格式统一；超过 100MB 才进行压缩。
- 若做过替换或压缩，在 `asset_index` 或 `manifest.notes` 中记录来源和处理方式。

## 五、Markdown 规则

本地 Markdown 面向手机阅读和 AI 检索，不要求逐行复制原始 PDF。建议结构：

```md
# 游戏名称规则书

## 游戏目标

## 组件概览

## 游戏准备

## 回合流程

## 核心规则

## 结算与胜利条件

## 常见易错点
```

规则书、FAQ 和规则参考应保持内容边界清晰：

- 规则书说明完整游戏流程；
- FAQ 只放问题、裁定、勘误和常见规则疑问；
- 规则参考集中放关键词、时机、结算顺序和速查内容；
- 目录迁移、文件来源和审核过程写入 `asset_index` 或 `notes`，不要混入规则正文。

## 六、资料整理流程

1. 先检查远端 WebDAV 是否已有该游戏目录和文件。
2. 按官方、社区、本地整理和暂存资料分别归类。
3. 保留官方 PDF、HTML、PNG / JPG 原件，并为 AI 需要时额外整理 Markdown。
4. 建立完整目录模板、`game.json`、`manifest.json` 和中英文资料索引。
5. 将每个实际存在的资源登记到 `manifest.resources[]`，并明确 `aiEnabled`。
6. 检查 JSON、路径、文件大小、语言、来源和旧目录残留。

新建或已经迁移的 `game.json` 不应包含 `documents.knowledge`；旧游戏在程序迁移期间可以暂时保留它作为兼容入口。新资源的 AI 使用登记以 `manifest.resources[].aiEnabled` 为准。

## 七、当前程序读取说明

Flutter 程序会为每款启用的桌游同时读取 `game.json` 和同目录的 `manifest.json`。
`game.json` 负责展示信息；`manifest.resources[]` 负责资源路径、来源、状态、语言、优先级和 `aiEnabled`。
当前 AI 直接读取状态为 `available`、允许 AI 使用且语言匹配的 Markdown；PDF、HTML 和图片仍可登记并按需打开或下载，但不自动进入文本知识上下文。

旧版 `game.json.documents` 仅保留代码兼容读取能力，不再作为新资源的登记来源。
