# 桌游导师

这是一个参考 Ludomentor 风格制作的 Flutter 安卓项目，用于把桌游目录、规则资料和 AI 助手整合到同一个应用里。

当前版本已经不再是早期的单桌游原型，而是一个以 `catalog + game.json + manifest.json + 远端资源缓存` 为核心的数据驱动应用。现在目录中已接入 `21` 款桌游，并支持按资源源优先级从远端拉取图片、文档和桌游元数据。

## 当前功能

- 默认简体中文，同时支持英文界面切换
- 多桌游目录首页，卡片与详情页基于 `assets/catalog.json` 和各游戏 `game.json` 生成
- 每个桌游都有独立 AI 助手入口，首页还有一个通用 AI 入口
- AI 对话按上下文分开保存
  - 每个桌游各自保留一套历史对话
  - 通用 AI 入口单独保留一套历史对话
- 支持文字输入、语音转文字、文字转语音朗读
- AI 支持两种回答模式
  - `仅知识库`：只根据当前桌游知识库回答
  - `智能补充`：知识库不足时，结合当前桌游信息继续回答
- 规则书、FAQ、Markdown 摘要等文档资源按需下载
  - 第一次打开时下载到本地缓存
  - 后续再次打开优先直接读取缓存
- 首页图片会在进入后后台预加载，并复用本地缓存
- 支持检测远端桌游资料更新，并提示用户是否同步到本地
- 支持 AI 接口配置测试、资源源优先级配置和资源访问测试

## 资源与数据结构

项目当前的数据组织方式是：

- `assets/catalog.json`
  - 控制桌游目录顺序、启用状态
- `assets/games/<slug>/game.json`
  - 控制单款桌游的标题、简介、图片和本地展示文案
- `assets/games/<slug>/manifest.json`
  - 登记资源路径、来源分类、版本、状态、`aiEnabled` 和优先级
- 远端资源库
  - 提供游戏目录、每款桌游的 game/manifest 文件、图片和规则资料
- 本地缓存
  - 用于保存首次下载后的图片和文档，减少后续重复请求

## 当前实现重点

- 首屏启动优先保证尽快进入首页，不让远端请求阻塞启动
- 桌游的 `game.json` 和 `manifest.json` 启动时优先使用缓存或包内资源
- `manifest.resources[]` 中允许 AI 使用的本地 Markdown 会随 APK 提供离线兜底；官方 PDF、HTML 和其他原件仍按需下载缓存
- AI 回答优先利用当前桌游知识库，必要时再做智能补充

## 相关文档

- 环境安装与 APK 打包步骤见 [BUILD_APK.md](/C:/Study/MyCode/MyProject/board-game-agent/BUILD_APK.md)
- 启动流程、资源更新与运行逻辑概览见 [DEVELOPER_FLOW_OVERVIEW.md](/C:/Study/MyCode/MyProject/board-game-agent/DEVELOPER_FLOW_OVERVIEW.md)
- 桌游资源整理规范见 [assets/ASSET_SPEC.md](/C:/Study/MyCode/MyProject/board-game-agent/assets/ASSET_SPEC.md)

## 说明

- 如果首次打开某个规则书或 FAQ，应用可能会先下载远端文件，再进入阅读页
- AI 和资源访问能力依赖当前配置的接口地址、资源源可达性以及本地缓存状态
