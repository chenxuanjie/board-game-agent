# APK 打包说明

这是一个 Flutter 安卓原型项目。我在当前这台机器上准备代码时，系统里 **没有可直接使用的** `Java` 和 Android SDK，也没有配好 `PATH`，所以这里没法直接产出真正的 `debug APK`。不过项目结构已经按可打包工程整理好了，只要把 Android 工具链装好，就可以继续生成安装包。

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

## 5. 安装项目依赖

在项目根目录执行：

```powershell
flutter pub get
```

## 6. 先本地运行调试

如果你已经连上开启 USB 调试的安卓手机，或者已经启动了 Android 模拟器，可以执行：

```powershell
flutter run
```

如果你的模拟器已经创建好了，也可以先手动启动它：

```powershell
emulator -avd board_game_agent_api36
```

## 7. 生成 Debug APK

在项目根目录执行：

```powershell
flutter build apk --debug
```

生成后的文件路径：

- [android/build/app/outputs/flutter-apk/app-debug.apk](/C:/Study/MyCode/MyProject/board-game-agent/android/build/app/outputs/flutter-apk/app-debug.apk)

## 8. 后续生成 Release APK

如果你后面要生成正式一点的本地安装包，可以执行：

```powershell
flutter build apk --release
```

生成后的文件路径：

- [android/build/app/outputs/flutter-apk/app-release.apk](/C:/Study/MyCode/MyProject/board-game-agent/android/build/app/outputs/flutter-apk/app-release.apk)

真正发布之前，建议再补自己的 Android 签名配置。

## 9. 后续接入真实 AI 的位置

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

## 10. 当前版本已完成的功能

- 一个参考 Ludomentor 风格的首页视觉
- 1 个桌游入口：`波多黎各`
- 默认简体中文界面
- 可切换英文界面
- 文字聊天输入
- 语音转文字输入
- AI 回答朗读
- 当前 AI 为模拟回声模式

## 11. 如果打包失败

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
