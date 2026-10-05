# 工程目录

`main.dart` 创建依赖，并按平台与 Web 宽度选择桌面或紧凑界面。两个界面使用同一个 `AppController` 和同一套业务模型、服务；目录划分不代表复制后端。

| 目录 | 职责 | 修改时从哪里开始 |
| --- | --- | --- |
| `lib/app/state/` | 跨界面的应用状态与业务入口 | 状态流转、加载及持久化调用 |
| `lib/core/localization/` | 文案与语言 | 跨平台文案 |
| `lib/core/theme/` | 主题、配色 | 主题令牌与外观 |
| `lib/core/models/`、`lib/core/platform/` | 跨功能的基础类型、平台适配 | 平台差异及共用状态 |
| `lib/features/games/` | 游戏目录、收藏、最近浏览与推荐 | 游戏数据或推荐规则 |
| `lib/features/library/` | 资料、资源源、WebDAV 与缓存 | 资料获取及打开前的数据处理 |
| `lib/features/assistant/` | AI 配置、会话、Run、语音和规则问答 | AI 请求及状态模型 |
| `lib/features/settings/` | 偏好、桌面 AI 设置与更新配置 | 设置的保存与读取 |
| `lib/features/identity/` | 原生群晖直连认证、恢复、个人数据切换与账号云同步；Web 访客模式 | 公共认证包与应用业务的接线 |
| `integration_test/` | 实际 Windows 登录、安全存储、恢复与退出验证 | 仅在私有测试环境提供凭据时运行 |
| `lib/ui/desktop/` | 桌面及宽屏 Web 的外壳、页面 | 桌面布局与交互 |
| `lib/ui/mobile/` | Android 及窄屏 Web 的外壳、页面 | 手机布局与交互 |
| `lib/ui/shared/` | 共用的文档、AI 展示、清单选游、轮播与横向滚动组件 | 共用 UI |

每个 `features/` 目录只在确有对应代码时设 `models/` 或 `services/`，不为对称性建立空目录。平台外壳负责布局与导航，业务状态和持久化只保留一套。新增界面时先确定它属于桌面、手机还是共用；新增数据处理时按功能放置，不因调用它的页面位于桌面或手机而复制一份。

AI 欢迎区、输入工具区、模型/推理/服务等级弹层与展示动效位于 `lib/ui/shared/assistant/`；桌面和紧凑页面复用这些控件并保持原有控制器、会话和草稿边界，详见 [AI 助手界面](assistant-workspace-design.md)。

配置导入导出共用 `lib/ui/shared/settings_transfer_screen.dart`；格式识别在 `lib/features/settings/models/configuration_transfer.dart`，跨存储保存及中断恢复在 `lib/features/settings/services/settings_transfer_service.dart`。设置页只提供范围入口与应用后的表单刷新，不复制解析或存储路径。格式、依赖补丁和验收边界见 [设置导入与导出](settings-transfer.md)。

喜欢排行榜共用 `lib/ui/shared/game_ranking_screen.dart`，排名规则在 `lib/features/games/services/game_favorite_ranker.dart`，收藏挂接在 `lib/app/state/app_controller/rankings.dart`。统计复用现有投票同步服务，以独立命名空间读取已保存收藏，不与国庆想玩票数混用。入口保持隐藏，数据范围、缓存与验收见 [喜欢排行榜](favorite-rankings.md)。

资料源连接编辑共用 `lib/ui/shared/resource_connection_screen.dart`，手机设置与桌面资料源均可进入。地址和账号保存沿用 `SettingsTransferService` 的安全存储、资料源持久化与失败回滚，保存后用于真实资源请求和更新检查。初始连接、旧地址迁移与发布注入见 [可编辑资源连接](resource-connections.md)。

Windows 更新服务及安装交接位于 `lib/features/settings/services/windows_update_service*.dart` 与 `windows_update_installer.dart`，复用现有关于页、启动提示和共享下载校验器。Android 的原服务保持原接线。独立清单、安装目录和数据保留约束见 [Windows 应用内更新](windows-updates.md)。

`AppController` 和部分桌面界面使用 Dart `part` 文件。`part` 只是把一个 library 的代码分到多个文件，仍共享私有状态；不要把文件移动误认为已经拆开职责。大型 AI 流程或页面如需继续拆分，应单独调整状态边界并验证行为，而不是仅按行数分文件。

测试目前保留 `test/` 下原有的运行入口，已有 `desktop/`、`mobile/` 和 `responses_workflow/` 的 `part` 测试分组。测试用例按原功能继续维护；移动测试入口前应同时检查项目脚本对其路径的引用。

应用动效令牌集中在 `lib/core/theme/app_motion.dart`，主页面过渡在 `lib/ui/shared/app_page_transition.dart`，详见 [应用动效规范](app-motion.md)。页面只挂载一个当前内容，不为淡出保留旧聊天页面。

封面衔接、首屏内容入场、图片解码反馈和收藏确认图标分别在 `lib/ui/shared/game_cover_motion.dart`、`content_entrance.dart`、`image_reveal.dart`、`favorite_feedback.dart`。平台外壳只负责源位置和导航，收藏仍复用同一个 AppController 写入队列与失败回滚；不创建新业务状态或持久化格式。

账号页的服务器配置现统一管理 NAS 地址、登录/WebDAV 端口与知识库目录。AccountService 负责优先级认证、稳定身份、按用户保存的安全资源凭据和派生资源配置；NasConnectionSection 是移动/桌面共享编辑器，原 ResourceConnectionScreen 只路由到账户页。详见 [账号与资源连接](resource-connections.md)。

ResourceAccessSummary 共用单设备整体可用性及按需入口详情。AppController 的 service_status 并发检测、聚合状态与丢弃过期结果；RemoteAssetService 负责目录探测、资源读取竞速及取消，PROPFIND/XML 仍复用 webdav_storage。登录有序回退与资源并发入口访问是两个独立策略。
