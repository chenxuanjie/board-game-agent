# PowerSync Web 运行资源

来源为官方 PowerSync Dart SDK 2.5.0：`package:powersync/web_worker.dart` 与官方发布的 SQLite WASM；遵循 Apache-2.0 及其依赖许可，应用的 Flutter NOTICE 仍需随正式 Web 交付保留。

这次按“不构建”的要求，复用本机已生成的官方 SDK Worker/WASM，核对了 `dependencies.json` 中全部运行依赖与本工程锁文件一致（包括 sqlite3 3.5.1、sqlite_async 0.14.6、sqlite3_web 0.9.5）。没有引入 Zheri 页面、业务代码、账号或配置，没有运行 APK/EXE/Web/Docker 发布构建。

后续更新 SDK 或这里列出的依赖时，明确构建范围后运行 `scripts/prepare-powersync-web.ps1`，从本工程锁定依赖重新生成 Worker；脚本更新内容 SHA-256 与依赖记录。测试校验文件摘要与依赖版本，Worker URL 带内容摘要，避免浏览器继续连接旧 SharedWorker。不能只替换官方预编译 Worker 而忽略两端 sqlite_async 的协议版本。

Web 部署须提供这些静态文件、正确的 WASM MIME 类型及 SQLite Worker 所需的跨源隔离响应头（COOP/COEP）。账号和业务走站点 `/api/v1/apps/board_game_agent/`；部署入口和浏览器现场联调属于用户暂缓的 Web 部署工作。本目录存在不代表该入口已经部署。
