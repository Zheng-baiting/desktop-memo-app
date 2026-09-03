# Desktop Memo App / 桌面便利贴

面向容易忘事的人：纸质便利贴风格、可编辑标题和正文、桌面拖拽、多张独立便利贴、本地保存、提醒，以及移动端列表视图。

## 已实现

- Windows、macOS、Linux、Android、iOS 共用一套 Flutter 代码
- 桌面画布上的多张便利贴，拖动后自动置顶
- 标题、正文直接编辑；每张便利贴内都有“新建”按钮
- 本地持久化，不登录、不上传备忘录内容
- 一次提醒或每 10 分钟持续提醒
- 桌面端 `Ctrl + Alt + M` 全局新建快捷键（系统允许时）
- 桌面端开机自启动开关（系统允许时）

## 本地运行

需要 Flutter 3.47 或更高版本：

```powershell
flutter pub get
flutter run -d windows   # Windows
flutter run -d macos     # macOS
flutter run -d linux     # Linux
flutter run -d android   # Android
flutter run -d ios       # iOS（需 macOS + Xcode）
```

## 打包到桌面

```powershell
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

Windows 产物在 `build/windows/x64/runner/Release/`。首次 Windows 编译还需要 Visual Studio 的 Desktop development with C++；本机没有完整原生构建工具时，可使用 GitHub Actions 自动生成 Windows 构建产物。

## 开发检查

```powershell
flutter analyze
flutter test
```

## 隐私

备忘录保存在设备本地的 `shared_preferences` 中。当前版本的提醒是应用内提醒；系统级后台语音、振动、托盘收纳和安装包签名属于下一阶段平台适配工作。
