import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:screen_retriever/screen_retriever.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:window_manager/window_manager.dart';

part 'desktop_notes.dart';

ThemeData memoTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
  fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC', 'sans-serif'],
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff9c603e)),
  scaffoldBackgroundColor: const Color(0xfff4ede4),
);

const papers = [
  Color(0xfffff3a6),
  Color(0xffffd6a5),
  Color(0xffffc6d9),
  Color(0xffcdeccf),
];
bool get desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
final notifications = FlutterLocalNotificationsPlugin();
final speech = FlutterTts();
final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  try {
    await speech.setLanguage('zh-CN');
    await speech.setSpeechRate(0.48);
  } catch (_) {}
  try {
    final local = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(local.identifier));
  } catch (_) {}
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwin = DarwinInitializationSettings();
  const linux = LinuxInitializationSettings(defaultActionName: '打开便利贴');
  const windows = WindowsInitializationSettings(
    appName: '桌面便利贴',
    appUserModelId: 'com.zhengbaiting.desktop_memo',
    guid: 'a8c22b55-049e-422f-b30f-863694de08c8',
  );
  try {
    await notifications.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        linux: linux,
        windows: windows,
      ),
    );
  } catch (_) {}
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (desktop) {
    final controller = await WindowController.fromCurrentEngine();
    if (controller.arguments.isNotEmpty) {
      final arguments =
          jsonDecode(controller.arguments) as Map<String, dynamic>;
      if (arguments['type'] == 'note') {
        await windowManager.ensureInitialized();
        runApp(DesktopNoteApp(controller: controller, arguments: arguments));
        return;
      }
    }
  }
  await initNotifications();
  if (desktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1180, 760),
      minimumSize: Size(820, 560),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.normal,
      title: '桌面便利贴',
    );
    await windowManager.waitUntilReadyToShow(options);
    await windowManager.hide();
  }
  runApp(MemoApp(await SharedPreferences.getInstance()));
}

class Memo {
  Memo({
    required this.id,
    required this.title,
    required this.body,
    required this.x,
    required this.y,
    required this.color,
    required this.createdAt,
    this.reminder,
    this.persistent = false,
    this.z = 0,
    this.collapsed = false,
    this.dock = 'left',
  }) {
    titleController = TextEditingController(text: title);
    bodyController = TextEditingController(text: body);
  }
  final String id;
  String title;
  String body;
  double x;
  double y;
  int color;
  int createdAt;
  DateTime? reminder;
  bool persistent;
  int z;
  bool collapsed;
  String dock;
  late final TextEditingController titleController;
  late final TextEditingController bodyController;
  bool textPointerDown = false;
  bool dragAccepted = false;

  void dispose() {
    titleController.dispose();
    bodyController.dispose();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'x': x,
    'y': y,
    'color': color,
    'createdAt': createdAt,
    'reminder': reminder?.toIso8601String(),
    'persistent': persistent,
    'z': z,
    'collapsed': collapsed,
    'dock': dock,
  };

  factory Memo.fromJson(Map<String, dynamic> j) => Memo(
    id: j['id'] as String,
    title: j['title'] as String? ?? '新便利贴',
    body: j['body'] as String? ?? '',
    x: (j['x'] as num?)?.toDouble() ?? 72,
    y: (j['y'] as num?)?.toDouble() ?? 96,
    color: j['color'] as int? ?? 0,
    createdAt: j['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    reminder: DateTime.tryParse(j['reminder'] as String? ?? ''),
    persistent: j['persistent'] as bool? ?? false,
    z: j['z'] as int? ?? 0,
    collapsed: j['collapsed'] as bool? ?? false,
    dock: j['dock'] as String? ?? 'left',
  );
}

class MemoApp extends StatefulWidget {
  const MemoApp(this.prefs, {super.key, this.initializePlatform = true});
  final SharedPreferences prefs;
  final bool initializePlatform;

  @override
  State<MemoApp> createState() => _MemoAppState();
}

class _MemoAppState extends State<MemoApp>
    with tray.TrayListener, WindowListener {
  late final List<Memo> notes = _load();
  Timer? timer;
  HotKey? hotKey;
  bool autoStart = false;
  int z = 0;
  Size canvasSize = const Size(1100, 650);
  Future<void> notificationQueue = Future.value();
  final Set<String> scheduled = {};
  bool trayReady = false;
  final Map<String, WindowController> noteWindows = {};
  WindowController? mainWindow;
  Future<void> saveQueue = Future.value();
  Future<void> desktopSetup = Future.value();
  void _refresh() {
    if (mounted) setState(() {});
  }

  List<Memo> _load() {
    final raw = widget.prefs.getString('notes.v1');
    if (raw == null) {
      return [
        Memo(
          id: 'welcome',
          title: '欢迎使用',
          body: '点击空白处拖动我\n标题和内容都可以直接修改。',
          x: 76,
          y: 100,
          color: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
    }
    try {
      return (jsonDecode(raw) as List)
          .map((item) => Memo.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    z = notes.fold(0, (max, n) => n.z > max ? n.z : max);
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkReminders(),
    );
    if (!widget.initializePlatform) return;
    for (final n in notes) {
      if (n.reminder != null) _scheduleNotification(n);
    }
    desktopSetup = _setupDesktop();
    _setupTray();
    if (desktop) _setupNoteWindows();
  }

  Future<void> _setupTray() async {
    if (!desktop) return;
    try {
      tray.trayManager.addListener(this);
      await tray.trayManager.setIcon(
        Platform.isWindows
            ? 'windows/runner/resources/app_icon.ico'
            : 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png',
      );
      if (!Platform.isLinux) await tray.trayManager.setToolTip('桌面便利贴');
      await tray.trayManager.setContextMenu(
        tray.Menu(
          items: [
            tray.MenuItem(key: 'show', label: '显示便利贴'),
            tray.MenuItem(key: 'new', label: '新建便利贴'),
            tray.MenuItem(key: 'manage', label: '全部便利贴'),
            tray.MenuItem.separator(),
            tray.MenuItem(key: 'exit', label: '退出'),
          ],
        ),
      );
      if (!mounted) return;
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      trayReady = true;
    } catch (_) {
      _notice('托盘暂不可用，关闭窗口将退出应用。');
    }
  }

  Future<void> _setupDesktop() async {
    try {
      await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestExactAlarmsPermission();
      await notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await notifications
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
    if (!desktop) return;
    try {
      launchAtStartup.setup(
        appName: 'desktop_memo',
        appPath: Platform.resolvedExecutable,
        packageName: 'com.zhengbaiting.desktop_memo',
      );
      autoStart = await launchAtStartup.isEnabled();
      hotKey = HotKey(
        key: PhysicalKeyboardKey.keyM,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(hotKey!, keyDownHandler: (_) => _newNote());
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    if (hotKey != null) hotKeyManager.unregister(hotKey!);
    for (final n in notes) {
      n.dispose();
    }
    if (desktop && widget.initializePlatform) {
      windowManager.removeListener(this);
      tray.trayManager.removeListener(this);
      tray.trayManager.destroy();
    }
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() {
    _showNotes();
  }

  @override
  void onTrayIconRightMouseDown() {
    tray.trayManager.popUpContextMenu();
  }

  @override
  void onWindowClose() async {
    await _save();
    if (trayReady) await windowManager.hide();
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) async {
    if (menuItem.key == 'show') {
      await _showNotes();
    } else if (menuItem.key == 'new') {
      _newNote();
    } else if (menuItem.key == 'manage') {
      await _showManager();
    } else if (menuItem.key == 'exit') {
      await _exitApp();
    }
  }

  Future<void> _exitApp() async {
    try {
      for (final window in noteWindows.values.toList()) {
        await window.invokeMethod('flush');
      }
      await _save();
      await notificationQueue;
      await tray.trayManager.destroy();
      await windowManager.destroy();
    } catch (error) {
      await _showManager();
      _notice('保存尚未完成，未退出：$error');
    }
  }

  Future<void> _save() {
    final snapshot = jsonEncode(notes.map((n) => n.toJson()).toList());
    saveQueue = saveQueue.catchError((Object _) {}).then((_) async {
      if (!await widget.prefs.setString('notes.v1', snapshot)) {
        throw StateError('无法保存便利贴');
      }
    });
    return saveQueue;
  }

  void _newNote() {
    setState(() {
      z++;
      notes.add(
        Memo(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: '新便利贴',
          body: '',
          x: 84 + (notes.length % 4) * 28,
          y: 112 + (notes.length % 4) * 28,
          color: notes.length % papers.length,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          z: z,
        ),
      );
    });
    _save();
    if (mainWindow != null) _openNote(notes.last);
  }

  void _front(Memo n) {
    setState(() {
      z++;
      n.z = z;
    });
    _save();
  }

  void _delete(Memo n) {
    final window = noteWindows.remove(n.id);
    window?.invokeMethod('close');
    setState(() => notes.removeWhere((item) => item.id == n.id));
    WidgetsBinding.instance.addPostFrameCallback((_) => n.dispose());
    n.reminder = null;
    _scheduleNotification(n);
    _save();
    if (notes.isEmpty && desktop && widget.initializePlatform && !trayReady) {
      _showManager();
    }
  }

  void _toggleCollapsed(Memo n) {
    setState(() {
      n.collapsed = !n.collapsed;
      if (!n.collapsed) {
        if (n.dock == 'left') n.x = 16;
        if (n.dock == 'right') n.x = canvasSize.width - 286;
        if (n.dock == 'top') n.y = 16;
        if (n.dock == 'bottom') n.y = canvasSize.height - 266;
        n.z = ++z;
      }
      _fitNote(n);
    });
    _save();
  }

  void _fitNote(Memo n) {
    final vertical = n.dock == 'left' || n.dock == 'right';
    final width = n.collapsed ? (vertical ? 34.0 : 150.0) : 270.0;
    final height = n.collapsed ? (vertical ? 150.0 : 34.0) : 250.0;
    final maxX = (canvasSize.width - width).clamp(0.0, double.infinity);
    final maxY = (canvasSize.height - height).clamp(0.0, double.infinity);
    n.x = n.x.clamp(0.0, maxX);
    n.y = n.y.clamp(0.0, maxY);
    if (n.collapsed) {
      if (n.dock == 'left') n.x = 0;
      if (n.dock == 'right') n.x = maxX;
      if (n.dock == 'top') n.y = 0;
      if (n.dock == 'bottom') n.y = maxY;
    }
  }

  void _move(Memo n, Offset delta) {
    setState(() {
      n.x += delta.dx;
      n.y += delta.dy;
      _fitNote(n);
    });
  }

  void _finishDrag(Memo n) {
    setState(() {
      final edges = <String, double>{
        'left': n.x,
        'right': canvasSize.width - n.x - 270,
        'top': n.y,
        'bottom': canvasSize.height - n.y - 250,
      };
      final edge = edges.entries.reduce((a, b) => a.value <= b.value ? a : b);
      if (edge.value <= 12) {
        n.dock = edge.key;
        n.collapsed = true;
      }
      _fitNote(n);
    });
    _save();
  }

  void _checkReminders() {
    final now = DateTime.now();
    for (final n in notes) {
      if (n.reminder == null || n.reminder!.isAfter(now) || !mounted) continue;
      messengerKey.currentState?.hideCurrentSnackBar();
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('提醒：${n.title}')),
      );
      if (!scheduled.remove(n.id)) _showSystemNotification(n);
      _speakReminder(n);
      noteWindows[n.id]?.invokeMethod('alert');
      setState(
        () => n.reminder = n.persistent
            ? now.add(const Duration(minutes: 10))
            : null,
      );
      _save();
      _updateNoteWindow(n);
      if (n.reminder != null) _scheduleNotification(n);
    }
  }

  Future<void> _speakReminder(Memo n) async {
    try {
      await speech.speak('提醒：${n.title}');
    } catch (_) {}
  }

  // Serialize changes so a slow schedule cannot recreate a deleted reminder.
  Future<void> _scheduleNotification(Memo n) {
    notificationQueue = notificationQueue.then((_) async {
      if (!widget.initializePlatform) return;
      final id = n.id.hashCode & 0x7fffffff;
      scheduled.remove(n.id);
      try {
        await notifications.cancel(id: id);
        final when = n.reminder;
        if (when == null || !notes.contains(n)) return;
        if (!when.isAfter(DateTime.now())) return;
        if (Platform.isLinux) {
          _notice('Linux 定时提醒需要保持应用运行。');
          return;
        }
        await notifications.zonedSchedule(
          id: id,
          title: n.title,
          body: n.body.isEmpty ? '该看一眼这张便利贴了' : n.body,
          scheduledDate: tz.TZDateTime.from(when, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'reminders',
              '便利贴提醒',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
            ),
            macOS: DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        scheduled.add(n.id);
      } catch (_) {
        _notice('系统提醒设置或取消失败，请检查通知和精确闹钟权限。应用内提醒需要保持运行。');
      }
    });
    return notificationQueue;
  }

  void _notice(String message) {
    if (!mounted) return;
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancelReminder(Memo n) async {
    setState(() {
      n.reminder = null;
      n.persistent = false;
    });
    await _save();
    await _scheduleNotification(n);
    try {
      await speech.stop();
    } catch (_) {}
    _updateNoteWindow(n);
  }

  Future<void> _showSystemNotification(Memo n) async {
    const android = AndroidNotificationDetails(
      'reminders',
      '便利贴提醒',
      channelDescription: '到点提醒你的便利贴',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    try {
      await notifications.show(
        id: n.id.hashCode & 0x7fffffff,
        title: n.title,
        body: n.body.isEmpty ? '该看一眼这张便利贴了' : n.body,
        notificationDetails: const NotificationDetails(
          android: android,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _reminder(Memo n) async {
    if (n.reminder != null) {
      final action = await showDialog<String>(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('已有提醒'),
          content: Text('提醒时间：${n.reminder}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('取消提醒'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('修改时间'),
            ),
          ],
        ),
      );
      if (!mounted || !notes.contains(n) || action == null) return;
      if (action == 'cancel') {
        await _cancelReminder(n);
        return;
      }
    }
    final picked = await showTimePicker(
      context: navigatorKey.currentContext!,
      initialTime: TimeOfDay.fromDateTime(
        n.reminder ?? DateTime.now().add(const Duration(minutes: 10)),
      ),
    );
    if (picked == null) return;
    if (!mounted) return;
    final now = DateTime.now();
    var when = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    final persistent = await showDialog<bool>(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('提醒方式'),
        content: const Text('选择一次提醒，或每 10 分钟持续提醒。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('提醒一次'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('持续提醒'),
          ),
        ],
      ),
    );
    if (!mounted || !notes.contains(n) || persistent == null) return;
    setState(() {
      n.reminder = when;
      n.persistent = persistent;
    });
    await _save();
    await _scheduleNotification(n);
    _updateNoteWindow(n);
  }

  Future<void> _toggleAutoStart() async {
    if (!desktop) return;
    try {
      await _autoStartSetting(!await _autoStartSetting(null));
    } catch (_) {
      if (mounted) {
        messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('当前系统暂不支持开机自启动')),
        );
      }
    }
  }

  Future<bool> _autoStartSetting(bool? enabled) async {
    await desktopSetup;
    if (enabled != null) {
      final changed = enabled
          ? await launchAtStartup.enable()
          : await launchAtStartup.disable();
      if (!changed) throw StateError('开机自启动设置失败，请重试');
    }
    final actual = await launchAtStartup.isEnabled();
    if (enabled != null && actual != enabled) {
      throw StateError('系统未应用开机自启动设置');
    }
    if (mounted) setState(() => autoStart = actual);
    return actual;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: messengerKey,
    debugShowCheckedModeBanner: false,
    title: '桌面便利贴',
    theme: memoTheme(),
    home: LayoutBuilder(
      builder: (context, c) => desktop && widget.initializePlatform
          ? _windowManagerPage()
          : c.maxWidth > 700
          ? _desktop()
          : _mobile(),
    ),
  );

  Widget _desktop() {
    final sorted = [...notes]..sort((a, b) => a.z.compareTo(b.z));
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _PaperPainter())),
          SafeArea(
            child: Column(
              children: [
                _bar(),
                Expanded(
                  child: notes.isEmpty
                      ? Center(
                          child: FilledButton.icon(
                            onPressed: _newNote,
                            icon: const Icon(Icons.add),
                            label: const Text('创建第一张便利贴'),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            canvasSize = constraints.biggest;
                            return Stack(
                              key: const ValueKey('memo-canvas'),
                              children: [
                                for (final n in sorted) _positionedNote(n),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionedNote(Memo n) {
    _fitNote(n);
    return Positioned(
      key: ValueKey(n.id),
      left: n.x,
      top: n.y,
      child: MemoCard(
        note: n,
        onChanged: _save,
        onDelete: _delete,
        onReminder: _reminder,
        onNew: _newNote,
        onFront: _front,
        onToggleCollapsed: _toggleCollapsed,
        onMove: (delta) => _move(n, delta),
        onDragEnd: () => _finishDrag(n),
      ),
    );
  }

  Widget _bar() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
    child: Row(
      children: [
        const Icon(Icons.sticky_note_2_outlined),
        const SizedBox(width: 10),
        const Text(
          '桌面便利贴',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (desktop)
          Text(
            'Ctrl + Alt + M 新建',
            style: TextStyle(color: Colors.brown.shade400),
          ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: autoStart ? '已启用开机自启动' : '启用开机自启动',
          onPressed: _toggleAutoStart,
          icon: Icon(
            Icons.power_settings_new,
            color: autoStart ? Colors.green.shade700 : null,
          ),
        ),
        IconButton(
          tooltip: '新建便利贴',
          onPressed: _newNote,
          icon: const Icon(Icons.add_circle_outline),
        ),
        if (desktop && widget.initializePlatform)
          IconButton(
            tooltip: '保存并退出应用',
            onPressed: _exitApp,
            icon: const Icon(Icons.exit_to_app),
          ),
      ],
    ),
  );

  Widget _mobile() => Scaffold(
    appBar: AppBar(
      title: const Text('桌面便利贴'),
      actions: [IconButton(onPressed: _newNote, icon: const Icon(Icons.add))],
    ),
    body: notes.isEmpty
        ? Center(
            child: FilledButton.icon(
              onPressed: _newNote,
              icon: const Icon(Icons.add),
              label: const Text('创建第一张便利贴'),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final n in notes)
                Padding(
                  key: ValueKey(n.id),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: MemoCard(
                    note: n,
                    compact: true,
                    onChanged: _save,
                    onDelete: _delete,
                    onReminder: _reminder,
                    onNew: _newNote,
                    onFront: _front,
                    onToggleCollapsed: _toggleCollapsed,
                  ),
                ),
            ],
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: _newNote,
      child: const Icon(Icons.add),
    ),
  );
}

class MemoCard extends StatelessWidget {
  const MemoCard({
    super.key,
    required this.note,
    required this.onChanged,
    required this.onDelete,
    required this.onReminder,
    required this.onNew,
    required this.onFront,
    required this.onToggleCollapsed,
    this.compact = false,
    this.onMove,
    this.onDragEnd,
    this.onDragStart,
    this.titleFocusNode,
    this.bodyFocusNode,
    this.collapsedOverride,
    this.onSettings,
  });
  final Memo note;
  final VoidCallback onChanged;
  final ValueChanged<Memo> onDelete;
  final ValueChanged<Memo> onReminder;
  final VoidCallback onNew;
  final ValueChanged<Memo> onFront;
  final ValueChanged<Memo> onToggleCollapsed;
  final bool compact;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onDragEnd;
  final VoidCallback? onDragStart;
  final FocusNode? titleFocusNode;
  final FocusNode? bodyFocusNode;
  final bool? collapsedOverride;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    Widget textSurface(Widget child, {bool textOnly = false}) {
      final surface = Listener(
        onPointerDown: (_) => note.textPointerDown = true,
        onPointerUp: (_) => note.textPointerDown = false,
        onPointerCancel: (_) => note.textPointerDown = false,
        child: child,
      );
      return textOnly && !compact ? _TextHitArea(child: surface) : surface;
    }

    if ((collapsedOverride ?? note.collapsed) && !compact) {
      final vertical = note.dock == 'left' || note.dock == 'right';
      return GestureDetector(
        onTap: () => onToggleCollapsed(note),
        onPanStart: (_) => onFront(note),
        child: Container(
          width: vertical ? 34 : 150,
          height: vertical ? 150 : 34,
          decoration: BoxDecoration(
            color: papers[note.color % papers.length],
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(blurRadius: 5, color: Color(0x33000000)),
            ],
          ),
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: vertical ? 1 : 0,
            child: Text(
              note.title.isEmpty ? '便利贴' : note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }
    final card = Material(
      color: papers[note.color % papers.length],
      elevation: 3,
      shadowColor: Colors.brown.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: textSurface(
                    TextField(
                      controller: note.titleController,
                      focusNode: titleFocusNode,
                      key: ValueKey('title-${note.id}'),
                      onChanged: (v) {
                        note.title = v;
                        onChanged();
                      },
                      decoration: const InputDecoration(
                        hintText: '标题',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    textOnly: true,
                  ),
                ),
                textSurface(
                  IconButton(
                    tooltip: '新建便利贴',
                    onPressed: onNew,
                    icon: const Icon(Icons.add, size: 20),
                  ),
                ),
                textSurface(
                  IconButton(
                    tooltip: '删除',
                    onPressed: () => onDelete(note),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: textSurface(
                TextField(
                  controller: note.bodyController,
                  focusNode: bodyFocusNode,
                  key: ValueKey('body-${note.id}'),
                  onChanged: (v) {
                    note.body = v;
                    onChanged();
                  },
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '写下要记住的事…',
                    border: InputBorder.none,
                  ),
                ),
                textOnly: true,
              ),
            ),
            Row(
              children: [
                Icon(
                  note.reminder == null
                      ? Icons.notifications_none
                      : Icons.notifications_active,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    note.reminder == null
                        ? '设置提醒'
                        : '${note.reminder!.hour.toString().padLeft(2, '0')}:${note.reminder!.minute.toString().padLeft(2, '0')}${note.persistent ? ' · 持续' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.brown.shade700,
                    ),
                  ),
                ),
                textSurface(
                  TextButton(
                    onPressed: () => onReminder(note),
                    child: const Text('提醒'),
                  ),
                ),
                if (onSettings != null)
                  textSurface(
                    IconButton(
                      tooltip: '便利贴设置',
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined, size: 18),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (compact) {
      return SizedBox(height: 250, child: card);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        note.dragAccepted = !note.textPointerDown;
        if (note.dragAccepted) {
          onFront(note);
          onDragStart?.call();
        }
      },
      onPanUpdate: (d) {
        if (note.dragAccepted) onMove?.call(d.delta);
      },
      onPanEnd: (_) {
        if (note.dragAccepted) onDragEnd?.call();
        note.dragAccepted = false;
      },
      onPanCancel: () => note.dragAccepted = false,
      child: SizedBox(width: 270, height: 250, child: card),
    );
  }
}

// Use the rendered text bounds, including scroll offset, to leave the rest of
// an editor available for dragging. Empty editors keep their first line clickable.
class _TextHitArea extends SingleChildRenderObjectWidget {
  const _TextHitArea({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _TextHitRender();
}

class _TextHitRender extends RenderProxyBox {
  RenderEditable? _editable(RenderObject node) {
    if (node is RenderEditable) return node;
    RenderEditable? found;
    node.visitChildren((child) => found ??= _editable(child));
    return found;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final editor = child == null ? null : _editable(child!);
    if (editor != null) {
      final point = editor.globalToLocal(localToGlobal(position));
      final text = editor.text?.toPlainText() ?? '';
      final boxes = editor.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      final onText = boxes.any(
        (box) => box.toRect().inflate(2).contains(point),
      );
      final emptyLine =
          text.isEmpty &&
          Rect.fromLTWH(
            0,
            0,
            editor.size.width,
            editor.preferredLineHeight + 4,
          ).contains(point);
      if (!onText && !emptyLine) return false;
    }
    return super.hitTest(result, position: position);
  }
}

class _PaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x0b8a6748)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
