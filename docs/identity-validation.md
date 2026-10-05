# 群晖直连验证记录

2026-10-05，主项目与公共 `app_identity` 工作分支均为 `codex/synology-direct-auth`。
旧服务方案结果保存在 `codex/synology-auth`；不得将旧构建当成本次直连构建。

## 已验证

- Windows 实际原生客户端：Shane 登录成功；使用应用相同的原生 HTTP 客户端直接连接 NAS，TLS 校验开启，不经过 Node / Supabase。
- Windows 系统安全存储：真实插件写入和读取会话成功，不保存密码 / OTP；销毁并重新创建客户端后再次向 NAS 验证身份成功。
- NAS 退出：系统存储清空；重新提交旧会话验证为未登录，旧 SID 无法恢复身份。探测使用独立临时存储命名空间并清理，没有改变正常应用个人数据。
- 公共认证包 25 项测试通过：验证码、错误码、独立 UID 验证、重启恢复、会话撤销、UID 变化、缺少权限、安全存储失败、迟到取消结果、断网退出、超时、坏 JSON、接口路径与 origin 限制。
- 账号页面 15 项测试通过：窄 / 中 / 宽窗口、验证码、登录退出、访客昵称、入口与 Web 隐藏登录字段。
- 主项目完整回归 405 项测试通过，主项目及公共包静态分析无问题。三端最新构建结果见下文。
- Web：只读 API.Info Origin 探测没有允许本机 Web origin 的 CORS 响应头。该版本显式禁用 Web 登录；验证 Web 平台分支不创建原生网关、不发送登录凭据并保持访客身份。

没有生成或交付渲染测试图片。真实 Windows 验证只断言认证与存储行为。

## 本地构建

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
