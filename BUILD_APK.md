# APK 打包说明

这是一个 Flutter 项目。当前仓库已经配置 Android release 签名和共享发布器，可以生成 Windows release、Android APK，并将 Android OTA 版本发布到配置的 WebDAV。版本号唯一来源是 `pubspec.yaml` 的 `version: x.y.z+build`。

## 1. 安装需要的工具

建议参考 Flutter 官方文档安装最新版环境：

- Windows 安装 Flutter： [docs.flutter.dev/get-started/install/windows/mobile](https://docs.flutter.dev/get-started/install/windows/mobile)
- Android 打包说明： [docs.flutter.dev/deployment/android](https://docs.flutter.dev/deployment/android)

你至少需要准备：

1. 安装 **Android Studio**
2. 在 Android Studio 安装过程中勾选：
   - Android SDK
   - Android SDK Platform
   - Android SDK Command-line Tools
   - Android SDK Build-Tools
3. 安装 **Flutter SDK**
4. 如果 Android Studio 没有自带可用的 JDK，再额外安装 **JDK**

## 2. 推荐的 Windows 路径

一个比较直接的配置方式是：

- Flutter SDK：`C:\src\flutter`
- Android SDK：`C:\Users\你的用户名\AppData\Local\Android\Sdk`

然后把 Flutter 加入 `PATH`：

```powershell
$env:Path += ";C:\src\flutter\bin"
```

如果你想永久生效，就把 `C:\src\flutter\bin` 加到 Windows 的系统环境变量或用户环境变量里。

## 3. 检查环境是否就绪

在项目根目录执行：

```powershell
flutter doctor
```

你需要确保 Android 相关检查基本通过。如果 Flutter 提示你接受 Android 许可协议，再执行：

```powershell
flutter doctor --android-licenses
```

## 4. 必要时手动创建 `local.properties`

通常 Flutter 会自动生成这个文件；如果 Android Studio 或 Flutter 没帮你生成，就手动创建：

文件位置：[android/local.properties](/C:/Study/MyCode/MyProject/board-game-agent/android/local.properties)

```properties
flutter.sdk=C:\\src\\flutter
sdk.dir=C:\\Users\\YOUR_NAME\\AppData\\Local\\Android\\Sdk
```

把这两个路径改成你自己机器上的真实路径。

## 5. 安装项目依赖与本地校验

在项目根目录执行：

```powershell
flutter pub get
flutter analyze
flutter test
```

## 6. 本地构建 Windows 和 Android

Windows release：

```powershell
flutter build windows --release
```

产物路径：

- `build/windows/x64/runner/Release/board_game_agent.exe`

Android release APK：

```powershell
flutter build apk --release
```

产物路径：

- `build/app/outputs/flutter-apk/app-release.apk`

## 7. 使用共享发布器

发布器位于：

- `C:\Study\MyCode\MyProject\shared_packages\flutter_release_publisher`

使用技能目录中的 `profiles\board_game_agent.json`，不要把 WebDAV 密码写入项目仓库。构建 Windows：

```powershell
dart run bin/publish.dart compile --profile <profile-path> --target windows
```

发布 Android OTA：

```powershell
dart run bin/publish.dart release --profile <profile-path> --target android --bump-build
```

发布器会自动完成依赖安装、分析、测试、Android release 编译、版本化 APK、SHA-256、release 记录和 WebDAV 上传。上传顺序是 APK、release 记录、更新 manifest。

本地 APK 和 release 记录保存在 `release/`；远端历史版本保存在 `apps/board_game_agent/updates/` 和 `apps/board_game_agent/releases/`。

## 8. 先运行调试版

```powershell
flutter run
```

## 9. 编译 iOS 版本

当前项目已经补齐了 `ios/` 工程骨架，但 **真正编译 iOS App 必须在 macOS 上完成**，因为需要：

- Xcode
- Apple 的 iOS SDK
- CocoaPods
- Apple 开发者签名

这台 Windows 机器上 **不能直接产出可安装的 iOS `.ipa`**。不过你后面把项目拷到 Mac 上后，可以按下面的最短步骤走。

### 9.1 在 Mac 上准备环境

你需要先安装：

1. Xcode（从 App Store 安装）
2. Flutter SDK
3. CocoaPods

建议先检查环境：

```bash
flutter doctor -v
```

你需要看到：

- `Xcode` 正常
- `CocoaPods` 正常
- `iOS toolchain` 正常

### 9.2 进入项目并拉依赖

```bash
flutter pub get
cd ios
pod install
cd ..
```

如果是第一次在这台 Mac 上打开该项目，建议先执行一次：

```bash
flutter clean
flutter pub get
cd ios
pod install
cd ..
```

### 9.3 运行到 iPhone 模拟器

先打开一个 iOS 模拟器，然后执行：

```bash
flutter run -d ios
```

或者先列出设备：

```bash
flutter devices
```

再指定某个模拟器运行。

### 9.4 用 Xcode 配置签名

如果你要装到真实 iPhone，先在 Xcode 打开：

- `ios/Runner.xcworkspace`

然后：

1. 选中 `Runner`
2. 打开 `Signing & Capabilities`
3. 选择你的 `Team`
4. 确认 `Bundle Identifier` 唯一可用

### 9.5 生成 iOS Release

在命令行生成 iOS release 构建：

```bash
flutter build ios --release
```

这一步会生成 iOS release 构建产物，但**默认还不是可分发的 `.ipa`**。

### 9.6 导出 IPA

通常推荐在 Xcode 中导出：

1. 用 Xcode 打开 `ios/Runner.xcworkspace`
2. 菜单选择：
   - `Product > Archive`
3. Archive 完成后，在 Organizer 中选择：
   - `Distribute App`
4. 选择导出方式：
   - Development
   - Ad Hoc
   - App Store Connect

如果只是自己装机测试，通常选 `Development` 或 `Ad Hoc`。

### 9.7 常用 iOS 命令

```bash
flutter build ios --debug
flutter build ios --release
flutter run -d ios
```

### 9.8 iOS 版本当前状态说明

- 我已经帮你生成了 `ios/` 工程
- 你现在可以把整个项目直接拷到 Mac 上继续
- Windows 这边无法替你完成最终 iOS 签名和 `.ipa` 导出

## 10. 后续接入真实 AI 的位置

现在这版模拟 AI 的行为只是“复读用户输入”。

你后面主要改这两个文件：

- [lib/services/mock_ai_service.dart](/C:/Study/MyCode/MyProject/board-game-agent/lib/services/mock_ai_service.dart)
- [lib/services/ai_service.dart](/C:/Study/MyCode/MyProject/board-game-agent/lib/services/ai_service.dart)

建议的下一步接法：

1. 加入一个 HTTP 请求库，比如 `http` 或 `dio`
2. 把用户消息发送到你的 API `url`
3. 在请求头里放入你的 `key`
4. 解析 AI 返回的文本内容
5. 把结果返回到聊天页面里显示

## 11. 当前版本已完成的功能

- 一个参考 Ludomentor 风格的首页视觉
- 1 个桌游入口：`波多黎各`
- 默认简体中文界面
- 可切换英文界面
- 文字聊天输入
- 语音转文字输入
- AI 回答朗读
- 当前 AI 为模拟回声模式

## 12. 如果打包失败

先检查这几项：

1. `flutter doctor` 输出里大部分检查已经通过
2. `java -version` 能正常执行
3. Android Studio 的 SDK 路径配置正确
4. `android/local.properties` 里写的是你真实的 Flutter SDK 和 Android SDK 路径
5. 重新执行下面这组命令：

```powershell
flutter clean
flutter pub get
flutter build apk --debug
```
