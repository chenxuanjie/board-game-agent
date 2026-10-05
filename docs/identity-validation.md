# 群晖直连验证记录

2026-10-05，主项目与公共 `app_identity` 工作分支均为 `codex/synology-direct-auth`。
旧服务方案结果保存在 `codex/synology-auth`；不得将旧构建当成本次直连构建。

## 直连登录基线（账号云同步改动前）

- Windows 实际原生客户端：Shane 登录成功；使用应用相同的原生 HTTP 客户端直接连接 NAS，TLS 校验开启，不经过 Node / Supabase。
- Windows 系统安全存储：真实插件写入和读取会话成功，不保存密码 / OTP；销毁并重新创建客户端后再次向 NAS 验证身份成功。
- NAS 退出：系统存储清空；重新提交旧会话验证为未登录，旧 SID 无法恢复身份。探测使用独立临时存储命名空间并清理，没有改变正常应用个人数据。
- 公共认证包 25 项测试通过：验证码、错误码、独立 UID 验证、重启恢复、会话撤销、UID 变化、缺少权限、安全存储失败、迟到取消结果、断网退出、超时、坏 JSON、接口路径与 origin 限制。
- 账号页面 15 项测试通过：窄 / 中 / 宽窗口、验证码、登录退出、访客昵称、入口与 Web 隐藏登录字段。
- 主项目完整回归 405 项测试通过，主项目及公共包静态分析无问题。这是账号云同步改动前的基线。
- Web：只读 API.Info Origin 探测没有允许本机 Web origin 的 CORS 响应头。该版本显式禁用 Web 登录；验证 Web 平台分支不创建原生网关、不发送登录凭据并保持访客身份。

没有生成或交付渲染测试图片。真实 Windows 验证只断言认证与存储行为。

## 直连登录基线构建

已通过登记的 flutter-release-publisher 固定 `all` 流程：405 项主项目回归通过，Web / APK / Windows Release 均构建成功。
版本保持 2.2.0+25，没有发布或上传，也没有生成新安装器。

- Android：`build/app/outputs/flutter-apk/app-release.apk`，243924319 字节；apksigner v2 签名校验通过。
- Windows：`build/windows/x64/runner/Release/board_game_agent.exe`，新编译 Dart 应用位于同目录 `data/app.so`；必须与 DLL、插件、data 一起分发。
- Web：`build/web/`，常规 JavaScript 构建成功，账号登录明确禁用。现有 secure-storage / TTS 插件的 Wasm 预检及 Cupertino 字体依赖告警保留，不声称支持 Wasm或完成渲染验收。

## 尚未验证的环境

- Android 实机 Keystore、进程重启、实际网络切换和安装升级没有设备验收；共享协议测试和 APK 编译不能替代实机验证。
- 真实 NAS 的双重验证账号、禁用用户、账号重建 / UID 复用没有进行破坏性操作；相应失败分支使用接口测试覆盖。
- Web 不支持登录，不声称有浏览器会话或三端账号云同步。
- 没有新生成 Windows 安装器或执行安装升级、推送安装包，也没有修改 NAS 权限、证书、SSO 或跨域配置。

## 可重复验证

在私有进程环境提供 `SYNOLOGY_TEST_ACCOUNT` / `SYNOLOGY_TEST_PASSWORD`，执行：

```text
flutter test integration_test/direct_synology_auth_test.dart -d windows
```

测试凭据不写进源码、编译参数或日志；缺少环境变量时跳过。结束后清除进程环境。
测试用独立安全存储，不使用正常账号数据。验证恢复、退出和旧会话失效，最后再次退出并清理。

常规 `flutter test` 不依赖 NAS 或真实凭据。localhost WebSocket 的代理绕过仅限测试进程，未修改系统代理。
数据隔离验收包括：切换账号等待上一账号写入排空、收藏 / 最近浏览 / AI 会话不混用、退出后原访客数据保留。
回滚同时切换主项目和公共包，见 [保存点](identity-preservation.md)。

## 账号云同步验证与最新构建

2026-10-05，在同一工作分支新增账号云同步，范围与实现见 [账号云同步](account-cloud-sync.md)。

- 主项目完整回归 420 项通过，`app_identity` 29 项通过，`webdav_sync` 19 项通过；主项目及认证公共包静态分析无问题。
- Windows 真实原生客户端使用 Shane 账号验证私有 home 目录：上传、第二个独立本地存储读取、删除同步、重启读取均通过。使用独立临时目录和合成数据，测试结束删除该目录并退出，没有改变已有个人文件、NAS 权限或系统配置。
- 实际业务存储测试覆盖收藏、最近浏览、AI 会话与标题、昵称、个人偏好投影，账号隔离，以及暂停后恢复、离线重试、删除墓碑、并发对话冲突副本、损坏数据拒绝和投影失败后的恢复。
- 固定发布工具的 `all` 流程通过：Android APK、Windows Release、Web JavaScript 均构建成功，版本仍为 2.2.0+25；未上传发布，未生成新 Windows 安装器。
- 最新 APK：`build/app/outputs/flutter-apk/app-release.apk`，249515581 字节，apksigner v2 签名校验通过。
- 最新 Windows Dart 产物：`build/windows/x64/runner/Release/data/app.so`，12288944 字节；分发仍需包含 EXE、DLL、插件与 data。
- 最新 Web：`build/web/main.dart.js`，5348027 字节；Web 保持访客模式。既有 Wasm 预检与 Cupertino 字体依赖告警仍在，不声称完成 Wasm 或渲染验收。

Android 尚未进行实机网络、Keystore、进程重启和跨设备同步验收。Windows 的 NAS 验证不能替代 Android 实机验收。没有生成渲染测试图片。

原生 NAS 同步验证入口为 `integration_test/account_cloud_sync_test.dart`，使用私有进程环境提供测试凭据，临时目录严格限制于本应用独立测试命名空间并在结束后清理。普通单元测试无需 NAS 或凭据。

## 2.2.0+26 APK / Windows 发布验证

2026-10-05，已将包含当前账号登录、个人数据云同步改动的 APK 和 Windows 完整安装包推送至 WebDAV。此节取代上文构建基线中“未推送、未生成安装器”的状态；Web 本次未发布。

- APK：`release/board_game_agent-2.2.0+26.apk`，249515581 字节；沿用旧版应用签名，v2 校验通过。API 36 模拟器从 build 23 覆盖安装至 26，通过启动与重启检查；独立验证清单经公共更新引擎完成发现新版、下载和完整 SHA-256 校验，回读 APK 再安装通过。
- Windows：`release/board_game_agent-2.2.0+26-windows-x64-setup.exe`，161491344 字节，安装器版本 2.2.0.26，Authenticode 状态为 `NotSigned`。隔离 AppId、临时目录中的安装、升级、快捷方式、卸载与 AppData 保留检查通过，未改变正在使用的真实安装。
- 主项目 420 项回归通过。公共发布工具 39 项测试与静态分析通过；认证、同步包验证沿用本节前列明的 29 / 19 项结果。
- Windows 应用自身的更新服务从 NAS 检出 build 26，下载并完整校验安装器后才交接；此项用验收接收器替代真正启动安装器，实际安装与卸载由上面的独立 Inno 验证覆盖，避免退出当前使用中的程序。
- 两端安装包均通过远端完整 SHA-256 校验，发布记录上传后才切换各自正式清单；再次读取远端清单及不可变发布记录，与本地逐项一致。

正式更新入口为 `apps/board_game_agent/updates/manifest.json` 与 `apps/board_game_agent/updates/windows/x64/manifest.json`。两者均为 stable / 2.2.0+26。发布记录保留 `includesUncommittedChanges: true` 与应用、认证包、同步包的源文件摘要，没有把未提交功能伪称为已存在于 Git HEAD 中；本次没有额外 Git 提交。

发布阻塞的处理：原生库复用本机已有缓存（SQLite 构建钩子仍校验固定 SHA-256）；运行中的 EXE 占用通过独立源文件与资源副本构建解决；MSBuild 路径长度问题使用短路径目录解决。公共发布工具新增按包大小计算的三至十五分钟请求上限，并在远端包已存在时先完整校验后复用；同大小但内容变化的不可变包会阻止清单发布，重试不再重复发送整个大文件。

Android 实机登录、Keystore、真实网络切换与未知来源安装交互仍未验收，模拟器结果不能替代这些边界。没有生成渲染测试图片。Windows 尚无 Authenticode 签名。需要回滚时以更高 build 发布恢复版，保留远端历史包与发布记录。

## 2026-10-06 统一账号与资源连接

版本提升到 2.2.0+27。公共包 app_identity 已提交 85c191b，多入口身份稳定、实际会话按签发地址隔离；30 项测试与静态分析通过。主项目完整 434 项测试和静态分析通过，包括地址迁移、回退限制、验证码停留原地址、凭据恢复/退出清理、旧版凭据匹配迁移、合并导入回滚与窄屏放大文字布局。

使用仓库外发布 profile 中的 Shane 账号进行真实 NAS 验证：优先入口不可达后回退外网入口，SYNO.API.Auth 验证登录，认证读取资料目录 catalog.json，恢复会话及资料凭据，再退出撤销会话并清理缓存，均通过。此验证使用独立内存存储，并未访问或更改个人云同步文件；不能替代 Android Keystore 或实机网络验收。

不生成渲染图，不重新构建 Windows/Web。新版客户端不内置共享 WebDAV 凭据，登录后派生资料及更新连接。

### 2.2.0+27 Android 发布

- 固定发布入口 android 和正式 release --bump-build 均成功，远端原为 build 26，正式构建保留已提交的 build 27；发布源码提交为 617b68c。APK 为 release/board_game_agent-2.2.0+27.apk，249613837 字节，SHA-256 为 22c127e3d62ba05ffaefb16f3fd0bc96051ea57479ed7cfe28b04e298ec569f6。
- 沿用证书 SHA-256 e124b4a9841453ecb5543cc29d2880051a404400fa2e46c5b9fb830b6446951a，apksigner 验证成功。API 36 模拟器从 build 26 覆盖安装 27，启动和重启无 AndroidRuntime 崩溃；从验证渠道下载回来的 APK 再次覆盖安装和启动通过。
- 公共更新引擎在 validation-27-manifest.json 渠道检出、下载并完整校验新版，9 项更新引擎测试通过，包括 SHA-256 错误拒绝、Android 安装器交接和未知来源安装权限错误。验证渠道通过后才发布 stable。
- 正式 APK 已完整 SHA-256 回读验证，不可变发布记录已上传且逐字回读匹配，最后更新 apps/board_game_agent/updates/manifest.json。正式清单再次回读与本地一致，Android 当前为 stable / 2.2.0+27；Windows 保持 build 26。

Android 物理设备上的原生 Keystore、真实网络切换及系统安装确认交互未验收。真实登录与资料访问由独立原生网络测试验证，模拟器覆盖升级由 adb install -r 验证，没有将模拟器启动冒烟测试描述为完整实机验证。

## 2026-10-06 同设备资源入口并发访问

此轮只修改源码并提交 Git，已发布的 build 27 APK 不包含此次资源入口并发改动。

- 主项目 446 项测试与静态分析通过。新增验收覆盖首个成功响应胜出及取消其他请求、快速失败不抢占成功、全部失败、超时、目录 PROPFIND 竞速、错误内容拒绝、权限原因脱敏、重复检测合并、修改地址后取消旧检测，以及 320/1280 宽度的按需详情与实时状态更新。
- 真实 Windows 原生网络再次使用仓库外 profile 的 Shane 账号验证：两个资料入口并发探测返回 failure/success，真实知识库目录读取成功；会话及资料凭据恢复和退出清理仍通过。使用独立内存存储，没有访问或更改个人云同步文件、NAS 权限或系统配置。
- 登录仍按优先级回退；资源入口任一成功即显示整个设备可用。其他入口结果在详情中查看，不再生成“部分资料来源可用”的全局警告。
- 没有生成渲染测试图片。本轮未构建 Web、APK 或 Windows 安装包，浏览器 CORS 和 Android 实机网络切换仍需对应平台实际验收。
