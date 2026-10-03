# 可编辑资源连接

App 的“我的 → 设置 → 资料源”提供“WebDAV 连接设置”整页入口，也可点击具体来源旁的编辑按钮。桌面来源列表共用同一个编辑页。

可以修改 WebDAV 地址、账号、密码，单独检测连接或直接保存。保存不依赖网络可达，失败时保留表单并提供重试；检测不会擅自替换已保存配置。保存成功后，选中的来源移到优先级首位，后续规则、图片、目录访问、同步和应用更新使用新连接，不需要重新编译 APK。

连接配置存入现有 `SecureWebDavSettingsStore`，来源地址及顺序存入 PreferencesService；不将密码写入来源列表。跨存储写入复用配置导入的安全恢复日志，任一步失败回滚旧连接和来源。导入默认保持原来的本地模式，编辑连接的“保存”显式启用 WebDAV。离线资源缓存保持可用。

新版本的初始外网地址为 `https://cznas.dpdns.org:5006/friend/`，应用资源库相对路径仍是 `apps/board_game_agent/board-game-lib/`，APK 更新仍是 `apps/board_game_agent/updates/manifest.json`；Windows 更新使用独立的 `apps/board_game_agent/updates/windows/x64/manifest.json`。升级时只迁移已知旧默认地址 `cznas.dev:5006/friend/`，保留其已保存账号；其他自定义服务器地址和内网来源不自动替换。

发布种子不是运行时不可修改配置。地址及初始账号由仓库外的 flutter-release-publisher profile 通过 `dartDefineFile` 引用本地私有 JSON，在构建时注入 `BOARD_GAME_WEBDAV_URL`、`BOARD_GAME_WEBDAV_USERNAME`、`BOARD_GAME_WEBDAV_PASSWORD`。没有构建种子时账号默认留空，可在 App 设置填写。种子不进入源码、提交、更新清单或发布记录；它仍会包含在安装包中，不能将 APK 当作保密凭据仓库。

现有安装的安全存储优先于种子。请求只向已保存连接的同源根目录发送账号；初始回退仅适用于明确的默认来源，不向其他站点或同站其他目录发送凭据。编辑单个来源也会切换共用连接，因此页面说明该连接同时用于资源、同步和更新。

回归覆盖：旧默认迁移、自定义地址保留、离线保存、重启读取、实际请求地址及认证头、连接检测失败、跨存储失败回滚、320/390/1280 dp 与 150% 字号。按用户要求不生成截图。Android 发布沿用原签名，不验证真机升级安装时应明确报告该限制。
