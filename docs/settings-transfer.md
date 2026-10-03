# 设置导入与导出

此功能属于设置 UI 与持久化层，不修改 AI 协议、Agent Run 或知识库链路。桌面、宽屏 Web、Android 与窄屏 Web 复用同一页面、解析器和保存服务。

## 使用入口

- 设置页标题右侧“导入 / 导出”：支持 AI、WebDAV、两项一起。
- AI 设置、资料与同步标题右侧菜单：默认导出对应配置。
- 导入：粘贴 → 本地识别 → 预览、编辑、勾选 → 应用配置。识别不会保存，也不会连接外部服务。
- 导出：选择范围、配置码或可读文本，复制已保存配置。未保存的设置草稿不在导出范围内。
- 默认不导出 API Key 和密码，主动开启“包含密钥和密码”才导出凭据。配置码是编码，不是加密；SHA-256 校验仅用于发现损坏，不证明来源可信。

导入 AI 配置后，当前回复继续使用发送时的配置；下一次发送使用新配置。WebDAV 地址、账号、密码可离线保存，保持本地模式；通过页面中的显式连接检测后才启用 WebDAV 模式。导入不自动开始投票同步或更新检查。

## 兼容格式与覆盖规则

配置码为 `BGA1:` 加 Base64URL 编码的 UTF-8 JSON：

```json
{
  "payload": {
    "format": "board-game-agent.settings",
    "version": 1,
    "ai": {"name": "服务名称", "baseUrl": "https://ai.example/v1", "model": "gpt-6-astra"},
    "webdav": {"baseUrl": "https://dav.example/friend/", "username": "账号"}
  },
  "checksum": "sha256(jsonEncode(payload))"
}
```

可直接粘贴上述 `payload` JSON，也可使用中英文字段名的多行文本，例如：

```text
[AI]
服务名称: "我的服务"
地址: "https://ai.example/v1"
API Key: "示例密钥"
模型: "gpt-6-astra"

[WebDAV]
地址: "https://dav.example/friend/"
账号: "示例账号"
密码: "示例密码"
```

也识别 `AI 地址`、`WebDAV 地址`、`Base URL`、`API Key`、`Username` 等标签。只有一种连接类型时，可将通用“地址”归入该类型；同时出现两种类型且地址没有用途标签时，不猜测归属。冲突或未知字段需指定用途或明确忽略。导出文本的值使用 JSON 引号，保留空格、冒号和多行密码。

只覆盖勾选的配置；缺失字段沿用已有值，明确空字符串表示清空。地址变化且没有提供凭据时，不沿用旧 API Key 或 WebDAV 账号密码。导入遵循现有模型白名单与推理能力限制，模型可留空后在设置中选择；不支持的模型不会静默替换。请求头与路径保持现有 `Authorization`、`/chat/completions` 策略。

WebDAV 来源只替换 `configured_webdav` 条目，保留其他来源及其相对优先级。资料请求按 scheme、host、port 与路径根范围选择凭据，导入账号不会用于不相关的服务器或目录。现有两个内置来源继续使用其原有独立凭据。

本版导出范围为当前 AI 服务及 WebDAV 连接，不导出所有供应商历史、聊天、资料文件、主题或投票。导入不额外写入供应商历史。尚不支持无字段名的任意口语段落、图片 OCR、二维码、文件选择或加密分享。

## 保存与恢复

`SettingsTransferService` 复用 AppController、PreferencesService 和 WebDavSettingsController。保存前将选中配置的原值写入现有 `FlutterSecureStorage` 恢复记录；先保存 WebDAV 和来源，再保存 AI，最后标记已提交并清理记录。

多个存储并非数据库原子事务。写入失败会恢复选中配置；进程中断后，在主控制器初始化前恢复未提交记录。已提交但清理失败的记录只清理，不回滚。如果恢复也失败，保留记录并提供重试；启动恢复失败由既有启动错误页提供重试。恢复记录不打印凭据或原始内容，解析错误也不附带敏感 JSON。

## 复用与依赖

参考 Open WebUI **v0.6.0** 的 [Connections.svelte](https://github.com/open-webui/open-webui/blob/v0.6.0/src/lib/components/admin/Settings/Connections.svelte)：地址与密钥成对管理、表单编辑与保存边界分离、保存后刷新模型状态。它使用 Svelte/TypeScript 与服务端管理 API，无法直接作为 Flutter/Dart 的离线设置组件使用；本版不复制其源码或引入该服务，继续复用已有控制器和持久化接口。

没有新增 pub 依赖。编码与校验使用已存在的 `dart:convert`、`crypto`；剪贴板、路由、表单和选择控件使用 Flutter SDK；恢复记录使用已存在的 `flutter_secure_storage`。升级这些依赖时保留 BGA1 格式及失败恢复回归用例。

现有本地依赖 `../shared_packages/webdav_settings` **0.1.0**，基线提交 `32186cd`，需要两个兼容接口补充：

- `saveConfiguration`：无网络保存并刷新已保存值与草稿，清除旧连接检测结果。
- 连接检测异常通过 `finally` 释放忙状态，允许重试。

修改位于共享包 `lib/src/webdav_settings_controller.dart`。该包是独立仓库，补丁同时记录在本项目 [webdav-settings-offline-save.patch](../patches/webdav-settings-offline-save.patch)，不包含共享包原有的用户测试改动。新的工作环境需在上述共享包基线上应用此补丁后再运行本分支；共享包正式纳入接口后删除补丁说明，避免保留第二套控制器实现。

## 验收与回滚

- `test/settings_transfer_test.dart` 的 21 个用例覆盖三种范围、两种文本语言、凭据包含/省略、损坏与不支持版本、歧义、地址更换、离线保存、四个存储失败点回滚、中断恢复、可重试检测、来源凭据隔离、剪贴板复制、勾选预览、重新编辑后清除旧预览、忽略字段后清除旧凭据状态，以及 320/390/1280 dp 与 150% 文字缩放。
- 布局测试加载实际打包字体；现有通知弹层测试也补齐该字体，避免默认 Ahem 字体误报窄窗口溢出。
- `flutter analyze --no-pub` 无问题；全量 `flutter test --no-pub` 共 307 个用例通过；共享 WebDAV 包 7 个用例通过。未生成渲染图，未构建或发布安装包。
- 原生 Android/Windows 剪贴板权限、Web 浏览器权限及安全存储、真实服务连接尚未实机验收。网络测试使用模拟响应，不触达现有账户。
- 回滚应用变更到 `b1bcbc3`，再仅反向应用共享包的上述补丁；保留共享包原有用户改动。若存在未提交恢复记录，先让当前版本完成恢复再回退，避免老版本无法识别中断记录。
