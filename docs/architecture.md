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
| `lib/ui/desktop/` | 桌面及宽屏 Web 的外壳、页面 | 桌面布局与交互 |
| `lib/ui/mobile/` | Android 及窄屏 Web 的外壳、页面 | 手机布局与交互 |
| `lib/ui/shared/` | 共用的文档、AI 展示、清单选游、轮播与横向滚动组件 | 共用 UI |

每个 `features/` 目录只在确有对应代码时设 `models/` 或 `services/`，不为对称性建立空目录。平台外壳负责布局与导航，业务状态和持久化只保留一套。新增界面时先确定它属于桌面、手机还是共用；新增数据处理时按功能放置，不因调用它的页面位于桌面或手机而复制一份。

`AppController` 和部分桌面界面使用 Dart `part` 文件。`part` 只是把一个 library 的代码分到多个文件，仍共享私有状态；不要把文件移动误认为已经拆开职责。大型 AI 流程或页面如需继续拆分，应单独调整状态边界并验证行为，而不是仅按行数分文件。

测试目前保留 `test/` 下原有的运行入口，已有 `desktop/`、`mobile/` 和 `responses_workflow/` 的 `part` 测试分组。测试用例按原功能继续维护；移动测试入口前应同时检查项目脚本对其路径的引用。
