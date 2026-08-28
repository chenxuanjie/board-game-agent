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

## AI 架构参考、规范与借鉴范围

本项目没有直接复制某个开源 AI 应用，也没有把下列产品作为运行时依赖。参考对象分为三类：

1. **协议标准**：必须遵循的 API 事件、请求字段和输出约束；
2. **架构/流程借鉴**：用于设计运行阶段、工具调用、引用、重试和上下文边界；
3. **交互借鉴**：用于参考成熟产品如何展示来源、状态和对话。

### 各参考方案分别借鉴什么

| 参考对象 | 主要借鉴内容 | 当前项目中的处理 | 是否直接引入/遵循 |
| --- | --- | --- | --- |
| [OpenAI Responses API 官方规范](https://developers.openai.com/api/docs/guides/streaming-responses) | 流式事件、完成边界、工具调用、引用、服务端 Compaction、Structured Outputs | 由共享包 `app_ai_client` 负责协议映射；应用层使用事件、最终完成和结构化输出，不把中间增量直接当成最终答案 | 直接遵循协议；不复制官方实现 |
| [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/streaming/) | Run/Turn/Item 生命周期、工具循环、Session、Guardrail、Usage、取消与恢复 | 仅迁移其运行状态和生命周期思想，映射为本项目的路由、阶段、流式状态和可恢复错误；Flutter 项目没有直接引入 Python/TypeScript SDK | 否，架构借鉴 |
| [LibreChat](https://github.com/danny-avila/LibreChat) | 多供应商适配、Responses 会话、引用转换、重试、对话持久化和产品级错误处理 | 用于检查多供应商与长对话的产品级边界；实现保持为本项目自己的 Dart/Flutter 代码 | 否，产品流程借鉴 |
| [Open WebUI](https://github.com/open-webui/open-webui) | RAG/知识库边界、来源展示、工具与知识的显式注入、搜索工作流 | 用于设计官方资料、社区资料、联网搜索和模型兜底的分层，以及引用在界面中的可见性 | 否，知识工作流借鉴 |
| [Vercel AI SDK](https://github.com/vercel/ai) | 文本块、工具块、状态块分离，以及前端流式 UI 数据模型 | 用于约束 `BoardGameAiStreamEvent`、状态提示和最终答案提交；项目不引入其 TypeScript 包 | 否，UI 数据模型借鉴 |
| [LobeHub](https://github.com/lobehub/lobe-chat) | Agent、工作区、项目上下文和长期记忆的隔离方式 | 用于后续规划通用助手、桌游助手和规则研究助手的上下文边界 | 否，未来架构借鉴 |

### 当前代码与参考规范的对应关系

| 程序部分 | 当前实现 | 参考来源 |
| --- | --- | --- |
| Responses 传输层 | `shared_packages/app_ai_client` 中的 `OpenAiDartResponsesAiClient` | OpenAI Responses API 官方请求/流式规范 |
| 问题路由 | `lib/services/board_game_question_router.dart` | 应用层本地规则；不是 OpenAI 自动提供的能力 |
| 模糊问题分类 | `lib/services/board_game_question_classifier.dart` | Responses Structured Outputs；分类结果只用于选路，不展示给用户 |
| AI 流程编排 | `lib/services/responses_rules_workflow.dart` | Agents SDK 的生命周期思想、LibreChat 的产品级流程 |
| 规则资料检索 | `lib/services/rule_knowledge_retriever.dart`、`lib/services/remote_asset_service.dart` | Open WebUI 的知识库/RAG 分层思想 |
| 流式状态与最终答案 | `lib/services/ai_service.dart`、`lib/state/app_controller.dart` | Responses 流式事件边界、Agents SDK 运行状态、Vercel AI SDK 的 UI 数据分离 |
| 引用与来源 | `RuleCitation`、官方/社区/Web 阶段解析逻辑 | OpenAI Web Search 引用要求、LibreChat/Open WebUI 的来源展示方式 |
| 上下文与 Compaction | `lib/services/responses_compaction_store.dart`、`ResponsesRulesWorkflow` | Responses API 的服务端上下文管理；本地保存负责跨重启恢复 |

### 当前 AI 问答流程

`智能补充`模式采用 local-first 路由，顺序如下：

```text
用户问题
  ↓
本地明确规则判断
  ├─ 明确普通问题 → 普通对话
  ├─ 明确桌游问题 → 官方资料 → 联网搜索 → 谨慎兜底
  └─ 无法判断 → 一次结构化分类请求 → 按结果进入上述路径
```

`仅知识库`模式不会因为路由器或分类器而转入普通对话；资料不足时明确返回不知道。分类请求失败时采用安全回退：通用 AI 入口回退普通对话，桌游专属页面回退桌游知识流程。

### 直接遵循与仅借鉴的边界

- **直接遵循**：Responses API 的请求/响应字段、流式事件语义、Structured Outputs 和 Compaction 字段由共享客户端统一映射。
- **应用层自有设计**：桌游问题路由、官方/社区/联网阶段顺序、知识库来源校验、失败回退和 Flutter 页面状态。
- **仅作参考**：Agents SDK、LibreChat、Open WebUI、Vercel AI SDK、LobeHub 的产品结构和工作方式；它们没有被当作 Dart 依赖直接打包。
- **许可证边界**：借鉴开源项目时只参考公开的架构与交互，不复制其受许可证约束的实现；如未来直接复用代码，必须在引入前单独核对许可证和归属声明。

这意味着 `ResponsesRulesWorkflow` 当前是项目自己的过渡编排层，而不是某个官方框架类。后续继续扩展工具调用、重试、取消、评测和多 Agent 能力时，应优先把路由、阶段执行、流式归并、上下文存储拆成独立组件，避免所有能力继续堆叠在同一个类中。

## 相关文档

- 环境安装与 APK 打包步骤见 [BUILD_APK.md](/C:/Study/MyCode/MyProject/board-game-agent/BUILD_APK.md)
- 启动流程、资源更新与运行逻辑概览见 [DEVELOPER_FLOW_OVERVIEW.md](/C:/Study/MyCode/MyProject/board-game-agent/DEVELOPER_FLOW_OVERVIEW.md)
- 桌游资源整理规范见 [assets/ASSET_SPEC.md](/C:/Study/MyCode/MyProject/board-game-agent/assets/ASSET_SPEC.md)

## 说明

- 如果首次打开某个规则书或 FAQ，应用可能会先下载远端文件，再进入阅读页
- AI 和资源访问能力依赖当前配置的接口地址、资源源可达性以及本地缓存状态
