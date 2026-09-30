# AI 模型目录：阶段一

目录版本：`2026-09-29`，实现见 `lib/features/assistant/models/ai_model_policy.dart`。

## 当前产品规则

- `/models` 只提供候选 ID。本地目录逐型号记录 `gpt-5.6`、`gpt-5.6-sol/terra/luna`、`gpt-6-astra/sol/luna` 的官方 API 推理强度及来源链接。未在官方模型页列出的日期快照不自动继承能力。
- 不显示旧 GPT、embedding、图像、专用模型、未审核的新家族以及无法识别的中转站别名。未知不等于不支持；只是当前无法证实符合“GPT-5.6 及以上文本模型”的使用规则。
- GPT-5.6 各型号与 GPT-6 Sol/Luna 的 API 值为 none、low、medium、high、xhigh、max；GPT-6 Astra 不提供 none。API 文档没有 `ultra` 这个值。界面额外提供“自动”，表示不发送推理强度字段。
- 模型列表过滤与请求前检查使用同一个解析器。旧配置中不符合规则的模型保留在存储中，但不能发起 AI 请求。切换模型时若旧推理强度不适用，回到自动。
- 目录仅判断模型 ID 的已知能力。中转站是否把该 ID 映射到相同的真实模型，客户端无法验证。

## 来源与复用

- [OpenAI GPT-5.6 指南](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.6)：模型家族及推理强度。
- [OpenAI 部署指南](https://developers.openai.com/api/docs/guides/deployment-checklist)：GPT-6 各型号的推理强度差异。
- 逐型号核对：[GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol)、[Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra)、[Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)；[GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra)、[Sol](https://developers.openai.com/api/docs/models/gpt-6-sol)、[Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)。
- [OpenAI 模型列表接口](https://developers.openai.com/api/reference/cli/resources/models/methods/retrieve)：模型列表不提供完整能力声明。
- 请求映射继续使用工程已有的 `openai_dart 8.0.0`，许可证 MIT。此阶段没有增加依赖，也没有复制其他项目源码。版本升级时应核对 SDK 的推理强度序列化和官方模型目录，再更新 `catalogVersion` 与测试。

## 边界与后续阶段

此阶段不验证中转站的上游映射、模型是否对当前密钥可用，也不验证选定的协议与参数组合；这些属于阶段二。服务等级、Responses/Chat Completions 路由、采样参数与推理模型的兼容性仍沿用现有实现。自定义别名的显式映射以及“保存、发现、验证”状态拆分属于后续阶段。

回滚时还原本阶段代码和目录即可；本阶段未迁移持久化结构，旧配置仍可由旧版本读取。已保存的 `none/xhigh/max` 在旧版本中会按其现有解析逻辑回退为自动。
