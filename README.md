# Desktop Memo App / 桌面便利贴

纸质便利贴风格的 Flutter 应用，面向容易忘事的人。备忘录保存在设备本地，不登录、不跨设备同步。

## 当前完成情况

桌面端现在使用**独立的无边框便利贴窗口**，不再局限于管理窗口中的画布。纸张使用 18 像素柔和圆角；空白处拖动原生窗口，拖动时抬到其他便利贴上方，靠近屏幕工作区边缘收成标签，点击标签展开。便利贴是普通桌面窗口，不会强行盖住所有其他软件，也不是嵌入系统壁纸层。

贴边后收成四角圆润的小标签。鼠标悬停自动滑出，移开约半秒后自动收回；编辑标题/正文、设置提醒、拖拽或处理到点提醒时保持展开。拖离边缘后退出自动收纳模式。悬停不会主动抢键盘焦点，展开/收起遵循系统减少动画设置。

每张便利贴右上角的 × 只删除当前这一张，+ 新建另一张。管理窗口按创建时间列出便利贴；关闭管理窗口后便利贴仍保留，彻底退出请用“保存并退出应用”或托盘菜单。

Windows 已构建并通过原生多窗口回归验证。macOS、Linux 的多窗口插件已接入，Android、iOS 继续使用手机列表界面；这些平台未完成实机验收，不能称为全平台已验证。

已通过 Flutter 交互测试：

- 文字旁空白区域实时拖拽，文字和操作按钮不拖动便利贴。
- 最后拖动的便利贴置顶，编辑内容在排序后保持。
- 按实际画布尺寸四边收纳、点击恢复，缩小窗口后标签仍可找回。
- 新建、编辑、删除，以及取消提醒并在重新加载后保持取消。
- 放弃提醒设置不会误建提醒。
- 圆角抗锯齿、负坐标屏幕工作区边界，以及单张关闭不得调用全应用退出。

Windows 原生回归已通过：创建两张独立便利贴，删除 A 后 B 与管理窗口仍在，B 的内容不变且能保存；到点提醒能送达 B 并显示提醒状态。测试使用内存偏好设置，不读写真实备忘事项。

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

独立便利贴支持日期和时间选择、一次/每 10 分钟提醒、取消提醒、到点窗口提示和短暂晃动（尊重系统减少动画设置）。手机后台持续语音、自定义重复周期、跨平台/多屏实机测试，以及正式安装与签名仍待完善。系统通知是否实际显示、语音是否能听到仍需在目标设备上确认，原生回归不等于这些外部效果已验收。

## 运行和检查

需要 Flutter 3.47 / Dart 3.13 或兼容版本，并安装目标平台编译工具。

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

原生多窗口隔离回归（会显示两张临时贴并触发一条临时提醒）：

```powershell
flutter run -d windows --release -t test/native_smoke.dart
```

看到 `NATIVE_SMOKE_PASS` 表示通过；若命令仍在等待，按 q 结束。测试后交付前必须使用 `flutter build windows --release -t lib/main.dart` 重新生成正常程序，不要分发测试入口产物。

macOS/Linux 可分别使用 `-d macos` / `-d linux`；Android/iOS 请先连接设备，再从 `flutter devices` 选择设备 ID。iOS 构建需要 macOS 与 Xcode。

## Windows 打包

```powershell
flutter build windows --release
```

产物目录为 `build/windows/x64/runner/Release/`，需保留其中全部 DLL 和 data 目录，不能只复制 exe。

2026-09-08 本机验证：Windows Release 构建成功，独立圆角便利贴可正常打开；14 项自动测试与上述原生回归通过。系统托盘、快捷键、系统通知送达、可听见的语音与开机启动仍待逐项验收。

Windows 语音插件构建还需要 [NuGet CLI](https://learn.microsoft.com/zh-cn/nuget/reference/nuget-exe-cli-reference)。本机将经过微软数字签名验证的 `nuget.exe` 放在忽略提交的 `build/tools/` 内，仅在构建进程中加入 PATH，没有全局安装。重新生成构建目录后需重新提供该工具。若早期失败的 CMake 配置留下指向 `Program Files` 的安装路径缓存，需将 `CMAKE_INSTALL_PREFIX` 修正为项目内输出目录，不要以管理员身份强行构建。

Android SDK 当前未安装。GitHub Actions 尚未启用，也没有发布安装包或 Releases。

平台接入依据：[通知插件官方说明](https://pub.dev/packages/flutter_local_notifications)、[多窗口插件说明](https://pub.dev/packages/desktop_multi_window)。单张删除使用窗口级 close；Windows 的全应用 destroy 只用于明确退出整个程序。
