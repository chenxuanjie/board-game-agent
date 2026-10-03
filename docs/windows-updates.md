# Windows 应用内更新

Windows 设置的“关于与更新 → 检查更新”和启动更新提示复用 `app_about`，但使用独立的 `WindowsWebDavUpdateService`。Android 继续使用现有服务，浏览器不会下载或执行桌面安装器。

## 发布与版本

- `pubspec.yaml` 是唯一版本源，本次 Windows 为 `2.1.0+24`。
- 清单：`apps/board_game_agent/updates/windows/x64/manifest.json`。
- 安装器：同目录下的 `board_game_agent-<version>+<build>-windows-x64-setup.exe`。
- 发布记录：`apps/board_game_agent/releases/board_game_agent-<version>+<build>-windows.release.json`。
- 更新使用设置中保存的 WebDAV 连接；检查和下载期间连接改变后需要重新检查。
- 只接受当前应用、stable 通道、Windows x64 的较新 build，不影响 Android 更新清单。无法读取本机版本时显示失败，不猜测旧版本并触发覆盖安装。

此前 Windows 版本没有接入此更新服务，首次需要手动安装本次 Setup.exe。之后的新版本可在应用内检查、下载并启动安装器。

## 下载与安装

复用工程已有的 `remote_update` / `remote_update_webdav` 0.1.0：清单检查、流式下载、大小与 SHA-256 校验、临时文件清理及有效缓存复用。安装前再次核对文件大小、SHA-256 和 EXE 文件头。校验失败不执行安装器；下载或启动失败保留重试。

网络使用 `app_ai_client` 已有的原生客户端工厂，沿用环境代理优先、Windows 手动系统代理及其既有 DIRECT 回退策略。该工厂暂未从包顶层导出，本版集中引用其 `src/default_http_client.dart`，不复制代理实现；PAC 和完整系统 bypass 列表仍是现有工厂的限制。Windows 更新不接受公网 HTTP，不绕过 TLS 验证；只允许 HTTP 回环地址用于测试。单请求/流空闲上限 30 秒，整包下载上限 10 分钟；离开关于页销毁服务会取消请求。没有无界自动重试，失败后由用户重新操作。用户文案不包含服务器响应体、凭据或内部异常。

安装前等待聊天、收藏、最近浏览等现有写入队列完成（15 秒上限）。AI 回复、语音输入或设置导入保存进行中时提示完成后重试。安装器通过 `Process.start` 参数数组启动，不经过 shell，不强制杀进程、不请求系统重启；启动成功后才关闭当前窗口。正常 Inno 安装目录通过 `unins000.exe` 识别，并把原目录传给安装器；便携或开发目录打开普通安装向导，不自动覆盖构建目录。

Inno Setup 保持固定 AppId，打包完整 Flutter Release 目录，仅覆盖安装目录，保留 AppData 设置、聊天和缓存。安装交互沿用官方的 [CloseApplications](https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm)、[RestartApplications](https://jrsoftware.org/ishelp/topic_setup_restartapplications.htm) 和 [命令行参数](https://jrsoftware.org/ishelp/topic_setupcmdline.htm)；禁用强制关闭和系统重启，完成页允许用户重新启动应用。

当前安装包尚未配置 Authenticode 签名，SHA-256 只验证文件完整性，不证明发布者身份。

## 验证与回滚

`test/windows_update_test.dart` 覆盖真实 Windows 清单路径、版本判断、平台/身份/路径错误、凭据范围、401/403/404/429/503、无效 JSON、TLS/超时失败、下载损坏、重复请求、连接变更、取消、缓存重试、安装交接顺序及关于页操作。不生成截图或渲染图。

发布前运行全工程分析、测试、Windows Release 构建，并在独立安装身份与临时目录中检查安装、升级、快捷方式、卸载及数据保留；不使用真实用户的安装目录做卸载测试。远端安装器完整 SHA-256 校验通过后才发布 Windows 清单。历史安装器和发布记录不可变。

回滚可还原 Windows 工厂接线及服务；已发布的历史安装包保留。更新器拒绝降低 build，需要回滚代码时以更高 build 发布恢复版，不将清单指回旧 build。
