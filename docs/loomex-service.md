# Loomex 账号模型服务

2026-10-27：完成本轮源码接线并按用户要求提交。按用户明确要求，**未运行测试、静态分析、上游连通性探测或编译构建**；未上传或部署。不能把本记录视为实际模型调用已验收。

配套后台提交：`3af2857`（`feature/board-game-business`，账号鉴权的 Loomex 模型转发）。客户端源码以本文件所属提交为准。

## 用户行为

- 登录后，在尚未配置其他可用服务时默认使用 Loomex。已有自定义 API/Key 和用户选择保留；设置页仍提供 OpenAI、DeepSeek 和自定义服务入口。
- 默认上游 `https://www.loomex.lol/v1`，模型 `gpt-6-sol`，推理强度 `low`，标准服务等级 `default`。客户端显示上游地址，但实际请求通过账号服务转发。
- Loomex 选项不显示 Key 输入，不将共享 Key 写入客户端配置或导出；游客继续使用自己的 API/Key，使用统一 Loomex 需要登录。
- 模型列表显示部署允许的模型，不把列表返回称为上游推理验证成功。默认模型可直接选中；设置页原有“保存并检测”仍可由用户手动运行。

## 调用链路

复用 `app_ai_client` 与锁定的 `openai_dart 8.0.0`（MIT，源码见 [pub.dev](https://pub.dev/packages/openai_dart/versions/8.0.0)）。继续使用现有 Responses 规则工作流、工具、引用、流式文本、错误处理和停止按钮；不另写一套模型协议解析器。升级 SDK 时核对 Chat Completions、Responses 和 compact 路径与事件语义。

`AccountAiHttpClient` 将内部保留地址的请求替换为当前应用服务下的 `/v1/apps/board_game_agent/ai/loomex/v1/`；Web 使用同源 `/api/` 前缀。内部地址不会进行 DNS 请求。SDK 的非秘密占位值只为适配现有端点契约，发往后台前会被当前账号的短期访问令牌替换。

后台仅允许 `GET models`、`POST chat/completions`、`POST responses` 和 `POST responses/compact`，验证桌游应用账号与会话后，才使用服务端 Key 转发。目标由管理员配置，客户端不能指定另一个上游；不转发 Cookie、认证头、上游重定向或原始错误正文。Responses 强制 `store=false`，不开放按 ID 读取、共享 conversation、`previous_response_id` 或后台任务。请求幂等标识按应用和账号派生。

退出/切换账号会取消活动请求并关闭传输；迟到数据仍校验原账号和工作区。Responses 上下文指纹包含运行时账号命名空间，账号标识不进入配置导出。自定义服务沿用原有原生代理策略和 Web BYOK 网关；这次没有解决此前暂缓的 Web 网关部署。

## 配套部署

需要后续更新客户端及纯 API 镜像，**本次不需要数据库迁移或升级 PowerSync/PostgreSQL 镜像**。API 服务配置：

```yaml
environment:
  APP_DATA_BOARD_LOOMEX_BASE_URL: https://www.loomex.lol/v1
  APP_DATA_BOARD_LOOMEX_MODELS: gpt-6-sol
  APP_DATA_BOARD_LOOMEX_API_KEY: <仅写入私有部署配置>
```

已将用户提供的凭据保存在后台仓库 Git 忽略的 `.local/loomex.private.json`，并合并到既有 `.local/api-only-input.yaml` 的 API 环境变量；未改交付目录或 NAS。Key 不在镜像源码/应用包中，缺少 Key 时后台返回 `loomex_not_configured`。更换 Key 后需要重建容器使环境变量生效，不需要把 Key 编译进镜像。

后台复用已有 `httpx 0.28.1`（BSD-3-Clause）和 Starlette 流式响应，参考 [HTTPX 异步流转发](https://www.python-httpx.org/async/#streaming-responses)。没有新增第三方依赖。并发最多 8 个活动上游请求，等待容量 2 秒；连接 8 秒、响应读取空闲 60 秒、首响应最多 45 秒、响应流最多 180 秒/16 MiB。连接关闭及取消均释放连接与容量；该资源边界不是给用户分配调用额度。

后续验收应覆盖：登录默认项、自定义服务切换、普通聊天、规则与引用、流式停止、401/限流/超时、退出和切换账号，以及 Android/Windows/Web 的实际传输。评论和点赞自动刷新问题已按本次任务切换暂缓，不能由本次模型接入视为已修复。
