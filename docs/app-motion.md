# 应用动效：第二、三阶段

## 范围与实现

本阶段属于 UI 交互：统一自定义动效、导航、菜单、卡片、状态反馈与键盘操作。复用 Flutter 3.41.9（framework `00b0c91f06`）内建组件，不新增依赖，不改变模型请求、Agent Run、引用和失败恢复协议。

动效令牌集中在 `lib/core/theme/app_motion.dart`。桌面主体和紧凑端标签页复用 `AppPageTransition`；AI 控件不再保留独立的时长策略。Material 内建表单和系统路由保留框架交互语义，没有复制另一套表单/路由引擎。

| 用途 | 时长 | 行为 |
| --- | --- | --- |
| 悬停、聚焦、状态颜色 | 160 ms | 柔和变化，不改变布局尺寸 |
| 主页面、选中底板、展开内容 | 200 ms | 当前页淡入，侧栏底板连续移动 |
| 菜单 | 180 / 140 ms | 展开 / 收起；模型面板位移 6 dp |
| 抽屉 | 240 ms | 按抽屉自身宽度滑入；同一次路由收起也为 240 ms |
| 底部面板 | 240 / 180 ms | 展开 / 收起 |
| 手动轮播、滚动 | 280 ms | 减少动画时直接跳至目标 |

所有自定义交互采用共享 `easeOutCubic`，菜单退出使用 `easeInCubic`。不做整页左右滑动、连续扫光或模拟 AI 打字。海报保留尺寸和宽高比，悬停上移 2 dp 并加轻阴影，移除 3D 倾斜、亮度滤镜和扫光绘制。

## 状态与可访问性

- 动画只呈现状态，操作立即执行。选中目的地立即挂载，旧页面立即卸载；不采用保留多个出场页的 AnimatedSwitcher 来承载工作区，避免快速切换产生重复 GlobalKey/ScrollController 或旧聊天页面。
- 仅目的地改变时播放页面过渡。控制器通知、流式 delta 和同页重建不重播。消息仍按真实消息 ID 播放一次入场。
- 侧栏和窗口操作由 InkWell 处理键盘激活，聚焦提示可见；共享卡片聚焦框在前景绘制，避免挤占内容尺寸。紧凑侧栏含标签语义和 Tooltip。
- AI 检测状态文字立即更新，颜色平滑变化，保留真实检测阶段和错误，并使用 liveRegion 提供辅助技术状态反馈。
- 读取系统 `MediaQuery.disableAnimations`；开启时自定义动效立即收敛，卡片不移动，首页自动轮播暂停，手动操作仍可使用。运行中开启该设置也能收敛页面过渡。
- 快速切页回归暴露了原先离开 AI 页即丢失草稿的问题。桌面和紧凑端使用同一 `AssistantViewState` 数据类型，存入 Flutter 路由内的 PageStorage，按控制器隔离会话草稿和滚动位置。此缓存只在当前路由生命周期有效，关闭程序不保留；不是会话持久化格式变更。

## 可追溯参考

- [Fluent 2 Motion](https://fluent2.microsoft.design/motion)：大范围导航使用快速淡入、动效服务操作、约束移动范围、提供减少动画。参考其行为原则，数值按本项目界面选取；未复制品牌或实现。
- [Flutter AnimatedSwitcher](https://api.flutter.dev/flutter/widgets/AnimatedSwitcher-class.html)：快速替换时可同时保留多个旧 child，因此主工作区使用单一当前 child 的淡入组件。
- [Flutter MediaQuery.disableAnimationsOf](https://api.flutter.dev/flutter/widgets/MediaQuery/disableAnimationsOf.html)：直接使用框架的系统动画偏好。
- [Flutter PageStorage](https://api.flutter.dev/flutter/widgets/PageStorage-class.html)：直接复用路由级临时状态缓存。
- Flutter 3.41.9 SDK 源码：`packages/flutter/lib/src/material/popup_menu.dart`、`bottom_sheet.dart`、`dialog.dart`，直接通过 `popUpAnimationStyle`、`sheetAnimationStyle`、`animationStyle` 接入现有控件；不复制 SDK 源码。

参考日期 2026-10-01。既有 Flutter 依赖为 BSD-3-Clause；本阶段没有引入开源代码片段、网络服务或新的许可/升级风险。升级 Flutter 时需回归菜单样式、焦点、PageStorage 和系统动画偏好。

## 验收与边界

入口：`test/app_motion_test.dart`、`test/desktop_workspace_test.dart`、`test/mobile_home_test.dart`、`test/conversation_drawer_test.dart`，最终构建还执行全工程测试。

重点验收：快速切页只保留一个当前页面；AI 草稿恢复；同页更新不重播；运行中减少动画立即收敛；Tab/Enter/Space 导航及卡片激活；聚焦不挤占卡片内容；海报宽高比稳定且悬停上移 2 dp；减少动画的轮播停止和手动操作；模型菜单、真实流式内容、失败/重试、窄屏与 125% 字体回归。

桌面/Web 构建和浏览器检查的实际结果交付后记录。Widget 测试不能代替原生 Android 真机、Windows GPU 帧耗时或真实网络服务验证；本阶段不宣称已达到某个帧率。

## 第三阶段：内容衔接与确认反馈

- 封面点击进入详情：桌面使用当前工作区中的真实起点/目标矩形，280 ms 轻量图片转场，最后 25% 淡出到详情横幅。浮层不接收点击、不增加辅助技术重复内容，不同时保留两套详情页面；快速切页、选择其他游戏或调整窗口尺寸立即取消。源位置仅在当前工作区保存，1 秒内匹配相同封面才使用，键盘/文字入口按正常页面过渡。
- 紧凑端首页、桌游库、我的封面直接复用 Flutter Hero / MaterialPageRoute，详情图库先显示同一封面并去重，返回仍由框架处理。搜索和专题等独立路由没有封面作用域，保留普通路由动画；不伪造封面位置。源 Hero 标签按组件实例隔离，重复游戏卡片不共用标签。
- 首屏推荐、游戏库前六张卡片与桌面详情主视觉短暂淡入、上移最多 4 dp。200 ms 基准，错峰最多 90 ms；稳定游戏 ID 避免业务通知时重播。同步缓存图片直接显示，异步解码后的图片按真实首帧淡入，不用计时器模拟加载。
- 修复宽屏 Web 沿用 `Image.file` 的既有平台缺口：Web 用打包资源 URL 显示图片，原生仍通过控制器文件缓存解析。Web 中未打包的远程图片保留缺图反馈，本次没有加入浏览器远程资源缓存服务。
- 浏览器验收暴露现有目录中谍报风云、璀璨宝石对决的封面/横幅遗漏打包，补齐其 `pubspec.yaml` 图片目录声明；未更改游戏资料内容。
- 收藏复用原有控制器的串行写入与失败回滚。写入中显示进度并禁用重复点击；成功保存后爱心一次 200 ms 轻弹，最大 1.15 倍。失败恢复原状态并展示可重试的错误，详情按钮保持 108 × 48 dp；旧收藏初次显示不播放庆祝动画。减少动画时不捕获封面位置、不移动内容、不播放爱心弹动。

直接复用 Flutter 3.41.9 的 `packages/flutter/lib/src/widgets/heroes.dart`、`src/material/page.dart`、`src/widgets/implicit_animations.dart` 和 `src/widgets/image.dart`，遵循现有 BSD-3-Clause 依赖许可，不新增依赖或复制第三方代码。参考 [Hero](https://api.flutter.dev/flutter/widgets/Hero-class.html) 的匹配标签/首帧要求和 [Image.frameBuilder](https://api.flutter.dev/flutter/widgets/Image/frameBuilder.html) 的缓存首帧语义。桌面详情位于同一路由内，因此使用小型几何浮层；没有添加第二套路由管理器。

新增验收覆盖：转场完成与快速离开取消；窗口缩放取消且不阻挡点击；首屏组件通知更新不重播；减少动画不捕获源封面/不弹爱心；收藏保存期间禁用、保存后反馈、写入异常回滚；紧凑端同一 Hero 进入和返回。桌面返回库仍使用页面淡入，未加入反向封面飞回；Android 实机和 GPU 帧耗时尚未验证。

## 第三阶段及回答模式简化验收记录（2026-10-01）

全工程静态检查无问题，270 项测试通过。独立分支 Windows x64 Release 与 Web JavaScript Release 均已重新构建，版本 2.1.0+22；Windows PE 标记 0x8664，Flutter 运行库、插件和 data 齐全，完整目录约 229.1 MiB。独立 Web 预览为 8084。浏览器检查了实际封面进入/返回详情、收藏切换以及新的 AI 回答模式菜单；模式菜单仅两个选项，概要强度文字隐藏，桌面页头没有更多菜单。菜单保存异常、恢复原值和重试由受控偏好写入测试覆盖。

Web Wasm 预检仍有既有 flutter_secure_storage_web / flutter_tts JS 互操作警告，交付为构建成功的 JavaScript Release；原有远程资料连接超时保留真实错误。未测试 Android 真机、Windows 原生 GPU 帧耗时或真实 AI 请求。可观察的动效与平台运行性能分别记录，不宣称所有平台已达到商业级性能。

## 回滚

改动位于独立 `codex/ai-workspace-polish` 分支及 worktree，未合并时原工作区不受影响。没有数据库/会话存储升级；合并后可回退界面提交。独立 Web 预览端口为 8084，原工作区 8081 不受本次预览影响。


2026-10-01 第二阶段验证：静态检查无问题，全工程 259 项测试通过；Windows x64 Release 2.1.0+22 已构建，PE 标记 0x8664，运行库/插件/data 齐全，目录约 228.5 MiB。Web JavaScript Release 已构建并在 8084 启动独立预览；浏览器实际检查了首页、AI 页和历史抽屉。Web 构建的 Wasm 预检仍提示既有 flutter_secure_storage_web/flutter_tts 兼容问题，本次交付为 JavaScript Release，不宣称支持 Wasm；原有资料库远程连接在浏览器中超时，界面保留真实可重试错误。未做原生 Windows/Android 实机帧耗时或真实 AI 服务调用验证。
