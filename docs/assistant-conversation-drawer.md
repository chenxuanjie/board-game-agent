# AI 会话浮层抽屉

## 交互与尺寸

- 手机、窄屏 Web 与桌面都从当前会话标题打开同一个共享组件。
- 暖白表面、22 dp 圆角、12 dp 外边距；最大宽度 320 dp，窄屏留下至少 34 dp 背景操作区。
- 根据真实更新时间分为今天、昨天和更早；标题换行，选中项使用主题主色容器。
- 240 ms 滑入和淡入；系统关闭动画时直接切换。点击遮罩、返回键、Esc 和关闭按钮可收起；选择会话或创建成功后收起。
- 新建时禁用重复提交与会话切换，显示加载；保存失败保留旧选中项与重试入口。清空当前记录收进更多菜单。
- 草稿和滚动位置在当前页面生命周期内按会话保存；页面退出后草稿不持久化。

## 状态与兼容

- 新话题使用独立 `conversation:<id>`，scope/gameId 决定资料上下文。同一桌游可创建多个会话。
- 保留 v4 的 `global` 和 `game:<gameId>` 记录、格式及原生文件位置，不重写旧 ID；空会话用当前语言显示新对话，已提问的会话使用首条问题作为标题。
- 请求、Run 状态、重试与清空通过选中的会话 ID 定位；切换会使旧生成失效并发出取消，迟到事件不得写入当前会话。
- Responses 会话、压缩快照按独立话题 ID 隔离；清空时删除该话题的压缩上下文，并阻止旧请求的迟到快照恢复已清空的上下文。原固定会话的缓存键兼容保留。
- 新建会话先写入成功，再切换选中项。原生写入采用临时完整快照再重命名；Web 使用浏览器本地 preferences，写入失败向调用方返回错误。
- 紧凑主题与桌面主题都使用已打包的 Noto Sans SC；去掉原来的在线字体依赖。

## 可追溯参考

此改动属于 UI 交互和会话持久化。参考 Open WebUI v0.11.4 的真实会话行、稳定会话 ID 和历史入口行为：

- [v0.11.4 发布记录](https://github.com/open-webui/open-webui/releases/tag/v0.11.4)
- [ChatItem.svelte](https://github.com/open-webui/open-webui/blob/v0.11.4/src/lib/components/layout/Sidebar/ChatItem.svelte)
- [History & Search 文档](https://docs.openwebui.com/features/chat-conversations/chat-features/history-search/)

其 Svelte/Web 组件不能直接运行于 Flutter Windows/Android，本次复用 Flutter 的路由、焦点、动画与 Material 组件，并接入现有 AppController；没有复制第三方代码、引入服务或新增许可证负担。此处不实现 Open WebUI 的所有历史管理功能。

## 验收与回滚

`test/conversation_drawer_test.dart` 覆盖独立会话/旧记录恢复、迟到事件隔离、通用/桌游范围切换、草稿恢复、保存失败重试、Esc/遮罩关闭、320 dp 窄屏、720/1280 dp 英文及 125% 字体缩放，并支持实际组件 PNG 输出。

Windows 通过本地构建验证。Web 的存储分支通过 SharedPreferences mock 测试，Android/窄屏布局通过 widget 测试；本轮未构建 Web/APK，也未进行 Android 真机或浏览器运行验收。

回滚时恢复本次共享抽屉、控制器与主题改动即可；存储仍为 v4，旧快照和新话题均不需要删除。恢复旧控制器后，新话题无法从旧固定上下文路径访问，应保留数据文件以便恢复新版本。
