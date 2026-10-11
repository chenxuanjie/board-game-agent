# Android APK 资源范围

Android APK 不内置 PDF、规则书、FAQ、知识文本、索引、翻译、研究素材或压缩资料。所有 `assets/games/<slug>/docs/` 通过 Flutter 的平台资源声明排除 Android，Windows/Web 继续保留原有资料。

APK 保留界面必需字体/图标/插图、游戏封面以及 game.json/manifest.json/catalog.json 轻量目录元数据。目录中的远端文档路径是索引信息，不代表 PDF 或文档正文已内置。登录后从 NAS 按需下载；已下载缓存位于设备应用数据目录，不参与 APK 打包。

规则写在项目 AGENTS.md；Android Gradle 的所有 merge*Assets 任务检查合并产物，禁止 docs、PDF 及放在其他桌游目录中的正文/压缩文件。没有修改、删减或重新签名已生成 APK。

交付检查：

```powershell
pwsh -NoProfile -File C:/Users/win10/.codex/skills/flutter-release-publisher/scripts/flutter-release.ps1 android
pwsh -NoProfile -File scripts/verify-android-assets.ps1
```

检查实际 APK ZIP 条目，确认没有文档并且保留游戏目录，同时报告 APK 大小。新增资料必须遵守同一排除规则，禁止注册游戏根目录或 assets/games/ 整树。平台过滤使用当前安装的 Flutter SDK 支持的 `assets.path/platforms` 字段，参考 [Flutter 官方 pubspec 文档](https://docs.flutter.dev/tools/pubspec#assets)。

## 2026-10-08 验收

| 项目 | 结果 |
| --- | --- |
| 旧 APK | 250,796,921 字节，239.18 MiB |
| 精简 APK | 150,190,955 字节，143.23 MiB，减少 40.11% |
| 桌游文档条目 | 0；目录与封面保留 |
| APK 签名 | apksigner verify 通过，v2 签名有效 |
| 自动回归 | 497 项测试通过，flutter analyze 无问题 |

APK 位于 `build/app/outputs/flutter-apk/app-release.apk`。构建使用 Flutter 3.41.9；41 条桌游文档资源声明均排除 Android。检查器验证旧 APK 会明确拒绝其中的 105 项文档，验证新 APK 通过。尚未执行 Android 实机安装和真实 NAS 公共 ACL 验收。
