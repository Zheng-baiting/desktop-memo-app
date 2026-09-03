# Desktop Memo App / 桌面便利贴

面向容易忘事的人：纸质便利贴风格、可编辑标题和正文、桌面拖拽、多张独立便利贴、本地保存、提醒，以及移动端列表视图。

## 已实现

- Windows、macOS、Linux、Android、iOS 共用一套 Flutter 代码
- 桌面画布上的多张便利贴，拖动后自动置顶
- 标题、正文直接编辑；每张便利贴内都有“新建”按钮
- 本地持久化，不登录、不上传备忘录内容
- 一次提醒或每 10 分钟持续提醒
- Android/iOS/macOS/Windows/Linux 的系统通知通道（声音、Android 振动；需系统授权）
- 桌面端 `Ctrl + Alt + M` 全局新建快捷键（系统允许时）
- 桌面端开机自启动开关（系统允许时）
- 桌面端托盘图标和“显示/退出”菜单
- 从画布四边拖入后收纳成可点击标签

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

Windows 产物在 `build/windows/x64/runner/Release/`。首次 Windows 编译还需要 Visual Studio 的 Desktop development with C++ 和系统开发者模式。

## 开发检查

```powershell
flutter analyze
flutter test
```

## 隐私

备忘录保存在设备本地的 `shared_preferences` 中。系统通知只使用本机通知服务，不上传备忘录内容；是否播放声音、振动由各系统权限和通知设置决定。正式商店签名与安装包发布仍需单独配置。
