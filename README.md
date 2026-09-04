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
- `openai_dart` 是社区维护的 Dart 包，本项目通过它完成 HTTP/SSE 和 Responses 协议适配；它不是 OpenAI 官方 Flutter/Dart SDK，也不提供本项目的 UI、重试、会话和桌游领域逻辑。OpenAI 的事件语义以官方文档为准。
- 当前依赖、仓库和本机可检查的包索引中没有找到名为 `hostpand` 的可用包，因此没有假设它提供会话、重连或 Agent 能力；如果名称有误，需要先确认准确项目地址和许可证。
- `openai_dart` 底层虽有 Conversation 和 `previous_response_id` 的模型/资源，但本项目的 `ResponsesRequest` 目前没有把它们暴露到业务层；当前请求明确使用 `store=false`，因此本轮只恢复本地检查点和加密 Compaction，不把本地 Run 误称为服务端 Session。接入服务端会话前还需要能力协商、隐私开关和自定义供应商降级测试。
- **许可证边界**：借鉴开源项目时只参考公开的架构与交互，不复制其受许可证约束的实现；如未来直接复用代码，必须在引入前单独核对许可证和归属声明。

这意味着 `ResponsesRulesWorkflow` 当前是项目自己的过渡编排层，而不是某个官方框架类。后续继续扩展工具调用、重试、取消、评测和多 Agent 能力时，应优先把路由、阶段执行、流式归并、上下文存储拆成独立组件，避免所有能力继续堆叠在同一个类中。

## Phase 3–7 落地状态

Phase 0–2 已建立运行事件、公共 Responses 事件适配和独立阶段编排；后续阶段当前实现如下：

| 阶段 | 当前落地内容 | 关键边界 |
| --- | --- | --- |
| Phase 3：上下文范围 | 通用入口默认不读取当前桌游文件；桌游入口按当前桌游加载资料；通用入口可显式开启“使用当前桌游资料”；问题路由先走本地规则，模糊问题才调用一次结构化分类 | 路由器是应用层策略，不是模型自动行为；`knowledgeOnly` 不会偷偷退回普通聊天 |
| Phase 4：结构化答案与引用 | 官方/社区阶段使用 JSON Schema；`sourceIds` 必须全部来自本阶段声明的真实目录；Web 阶段只接受 Responses annotations 的 HTTP(S) 引用；没有有效引用不会标记为联网回答 | 混入伪造来源、缺失来源或无效 JSON 时，阶段只会进入 `insufficient`，不会提交气泡 |
| Phase 5：Session 与 Compaction | Session/Compaction 按知识范围、桌游、供应商、模型、认证指纹和生成设置隔离；`store=false` 显式发送；最新 compaction item 替换旧本地窗口并加密持久化；自定义接口不支持 Compaction 时自动降级 | 切换模型/供应商/知识范围会清理同一上下文作用域的旧压缩状态，避免串上下文 |
| Phase 6：可靠性与遥测 | 每次 Run 保存 `runId`、上下文、阶段、模型、responseId、请求数、输入/输出/推理 tokens、时间、终止事件、错误和引用计数；默认主程序使用本地有界 `SharedPreferences` 账本 | 遥测写入失败不会覆盖正常答案；账本不保存 API key、提示词或文件内容 |
| Phase 7：发布与验收 | 工作流和共享客户端覆盖完成边界、尾部 output item、取消/失败、引用校验、Compaction 恢复和能力降级测试；发布前分别执行 Web、Windows、Android 构建检查 | 单元测试/模拟客户端不等于真实线上接口验证；真实 OpenAI 或自定义服务商需在目标环境提供可用凭据后再做 smoke test |

### 当前固定验收集

`test/responses_rules_workflow_test.dart`、`test/ai_run_orchestrator_test.dart`、`test/ai_run_telemetry_test.dart` 和共享包的 `test/responses_client_test.dart` 覆盖以下行为：普通问题不加载桌游文件、官方/社区/Web 顺序、Web 中间文本不进入气泡、真实引用校验、尾部失败不覆盖已收集诊断、等待 `response.completed`、最近 12 条输入、Compaction 跨实例恢复和替换旧窗口、模型/知识范围隔离、自定义 Responses 能力降级、遥测有界持久化，以及事件状态一致性。

当前没有把 LibreChat、Open WebUI、Vercel AI SDK 或 Agents SDK 当作 Flutter 运行时依赖；它们只提供架构和交互参考。Responses API 的字段与事件语义由 `shared_packages/app_ai_client` 统一映射，应用层只提交经过阶段校验的最终答案。

### 本轮可靠性补强

- 终态事件现在携带完整的 `AiRunResult`。失败时，控制器会从已经完成或已确认部分结果的阶段生成“已确认进度”，并同时保留可安全显示的部分答案、可读失败原因、尝试次数和重试入口；进度会逐阶段展示真实资料标题、章节、页码、引用内容和来源，缺失字段不会编造。
- `AiConversation` 会保存最近一次 Run 的本地检查点。应用重启后可恢复阶段时间线、引用元数据、响应 ID、错误分类和耗时；每个 token 的 `delta`、提示词、工具参数、文件原文和 API 密钥不会写入检查点。
- 检查点事件有数量上限，并过滤高频文本增量；它是本地 UI/诊断恢复，不等同于 OpenAI 的服务端 Conversation，也不会伪造服务端会话关系。
- `openai_dart` 是 `app_ai_client` 使用的传输/协议依赖，提供请求、SSE 事件和响应解析；它不负责本项目的桌游问题路由、阶段编排、失败文案、滚动跟随、会话文件或跨平台 UI。这些属于应用产品层，因此仍需要在本项目中实现。
- 当前测试新增了检查点往返和终态 `AiRunResult` 传播验证；真实 OpenAI、自定义服务商、断网、Windows/Web/Android smoke test 仍需在目标环境提供可用配置后执行，不能由离线单元测试代替。

## 相关文档

- 环境安装与 APK 打包步骤见 [BUILD_APK.md](/C:/Study/MyCode/MyProject/board-game-agent/BUILD_APK.md)
- 启动流程、资源更新与运行逻辑概览见 [DEVELOPER_FLOW_OVERVIEW.md](/C:/Study/MyCode/MyProject/board-game-agent/DEVELOPER_FLOW_OVERVIEW.md)
- 桌游资源整理规范见 [assets/ASSET_SPEC.md](/C:/Study/MyCode/MyProject/board-game-agent/assets/ASSET_SPEC.md)

## 说明

- 如果首次打开某个规则书或 FAQ，应用可能会先下载远端文件，再进入阅读页
- AI 和资源访问能力依赖当前配置的接口地址、资源源可达性以及本地缓存状态
