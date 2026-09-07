# Desktop Memo App / 桌面便利贴

纸质便利贴风格的 Flutter 应用，面向容易忘事的人。备忘录保存在设备本地，不登录、不跨设备同步。

## 当前完成情况

目前是**单个应用窗口内的便利贴画布**，尚未实现每张便利贴作为独立窗口贴在操作系统桌面上。Windows、macOS、Linux、Android、iOS 工程均已建立，不代表五个平台都已通过实机验收。

已通过 Flutter 交互测试：

- 文字旁空白区域实时拖拽，文字和操作按钮不拖动便利贴。
- 最后拖动的便利贴置顶，编辑内容在排序后保持。
- 按实际画布尺寸四边收纳、点击恢复，缩小窗口后标签仍可找回。
- 新建、编辑、删除，以及取消提醒并在重新加载后保持取消。
- 放弃提醒设置不会误建提醒。

已接入但待实机验收：

- 桌面托盘显示、新建、退出；托盘初始化成功后关闭窗口收进托盘。
- 桌面全局快捷键 Ctrl+Alt+M 和开机启动开关。
- 系统定时通知、Android 通知/精确闹钟权限与重启接收器。
- 应用运行期间的语音播报与每 10 分钟持续提醒。

## 提醒限制

一次定时通知交给系统调度；实际送达取决于权限与系统设置。
Linux 没有插件提供的后台定时调度，必须保持应用运行。
持续提醒的后续调度、语音播报依赖应用进程；退出应用后不能保证持续播报。
取消/删除会尝试撤销对应系统通知，调度失败会提示，不能将静态分析通过视为已实际送达。

待完善：独立桌面窗口、系统屏幕边缘吸附、手机后台持续语音、界面振动、完整提醒时间/周期设置、多屏测试，以及正式安装与签名。

## 运行和检查

需要 Flutter 3.47 / Dart 3.13 或兼容版本，并安装目标平台编译工具。

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

macOS/Linux 可分别使用 `-d macos` / `-d linux`；Android/iOS 请先连接设备，再从 `flutter devices` 选择设备 ID。iOS 构建需要 macOS 与 Xcode。

## Windows 打包

```powershell
flutter build windows --release
```

产物目录为 `build/windows/x64/runner/Release/`，需保留其中全部 DLL 和 data 目录，不能只复制 exe。

2026-09-07 本机检查：Visual Studio Community 2022 和 Windows SDK 已存在；构建仍被符号链接权限阻断，尚未生成可运行产物。通常可通过 Windows 开发者模式提供该能力，但本项目没有自动更改系统设置。Android SDK 当前未安装。GitHub Actions 尚未启用，也没有发布安装包或 Releases。

平台接入依据：[通知插件官方说明](https://pub.dev/packages/flutter_local_notifications)。自动测试覆盖应用逻辑，不覆盖系统托盘、系统通知送达和后台生命周期。
