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

import 'exit_timing_log.dart';
import 'note_storage.dart';

part 'desktop_notes.dart';
part 'reminder_actions.dart';

const memoPaper = Color(0xFFFFF3BA);
const memoInk = Color(0xFF493A29);
const memoMuted = Color(0xFF79654D);
const memoAccent = Color(0xFF756044);
const memoDivider = Color(0xFFD7C69D);

ThemeData memoTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
  fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC', 'sans-serif'],
  colorScheme: ColorScheme.fromSeed(seedColor: memoAccent).copyWith(
    primary: memoAccent,
    onPrimary: memoPaper,
    secondary: memoAccent,
    tertiary: memoAccent,
    surface: memoPaper,
    onSurface: memoInk,
    onSurfaceVariant: memoMuted,
    outline: memoMuted,
    outlineVariant: memoDivider,
    surfaceTint: Colors.transparent,
  ),
  scaffoldBackgroundColor: memoPaper,
  iconTheme: const IconThemeData(color: memoMuted),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(foregroundColor: memoMuted),
  ),
  dividerTheme: const DividerThemeData(color: memoDivider),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: memoAccent,
    selectionColor: Color(0x33756044),
    selectionHandleColor: memoAccent,
  ),
);

// Preserve stored color indexes while rendering every note in one paper palette.
const papers = [memoPaper];
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

Future<void> main(List<String> args) => runMemo(args);

Future<void> runMemo(List<String> args, {bool memoryOnly = false}) async {
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
  final prefs = await SharedPreferences.getInstance();
  final storage = Platform.isWindows && !memoryOnly
      ? NoteStorage.windowsDefault()
      : null;
  // Read and validate before writing. A failed migration must not replace
  // existing records with an empty list.
  runApp(MemoApp(prefs, storage: storage));
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
    this.snoozedUntil,
    this.persistent = false,
    this.daily = false,
    this.repeatUntil,
    this.dailyPlan = const {},
    this.reminderTimes = const {},
    this.planDate,
    Set<String>? completedTasks,
    this.z = 0,
    this.collapsed = false,
    this.dock = 'left',
  }) : completedTasks = {...?completedTasks} {
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
  DateTime? snoozedUntil;
  bool persistent;
  bool daily;
  DateTime? repeatUntil;
  final Map<String, String> dailyPlan;
  final Map<String, String> reminderTimes;
  String? planDate;
  final Set<String> completedTasks;

  String taskKey(String line) => '${planDate ?? ""}|$line';
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
    if (snoozedUntil != null) 'snoozedUntil': snoozedUntil!.toIso8601String(),
    'persistent': persistent,
    'daily': daily,
    'repeatUntil': repeatUntil?.toIso8601String(),
    if (dailyPlan.isNotEmpty) 'dailyPlan': dailyPlan,
    if (reminderTimes.isNotEmpty) 'reminderTimes': reminderTimes,
    if (planDate != null) 'planDate': planDate,
    if (completedTasks.isNotEmpty) 'completedTasks': completedTasks.toList(),
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
    snoozedUntil: DateTime.tryParse(j['snoozedUntil'] as String? ?? ''),
    persistent: j['persistent'] as bool? ?? false,
    daily: j['daily'] as bool? ?? false,
    repeatUntil: DateTime.tryParse(j['repeatUntil'] as String? ?? ''),
    dailyPlan: Map<String, String>.from(j['dailyPlan'] as Map? ?? {}),
    reminderTimes: Map<String, String>.from(j['reminderTimes'] as Map? ?? {}),
    planDate: j['planDate'] as String?,
    completedTasks: Set<String>.from(j['completedTasks'] as List? ?? []),
    z: j['z'] as int? ?? 0,
    collapsed: j['collapsed'] as bool? ?? false,
    dock: j['dock'] as String? ?? 'left',
  );

  bool expiredAt(DateTime now) =>
      daily &&
      repeatUntil != null &&
      !now.isBefore(
        DateTime(repeatUntil!.year, repeatUntil!.month, repeatUntil!.day + 1),
      );

  // A snooze postpones this alert without changing a daily reminder's clock.
  DateTime? get nextAlertAt => snoozedUntil ?? reminder;

  bool reminderDueAt(DateTime now) {
    final next = nextAlertAt;
    return next != null && !next.isAfter(now);
  }

  bool allowsReminderAlert(DateTime now) =>
      (snoozedUntil != null || (!expiredAt(now) && calendarAllowsAlert(now)));

  void snoozeReminder(Duration delay, {DateTime? now}) {
    if (delay != const Duration(minutes: 10) &&
        delay != const Duration(minutes: 30)) {
      throw ArgumentError.value(delay, 'delay', '只能暂缓 10 或 30 分钟');
    }
    snoozedUntil = (now ?? DateTime.now()).add(delay);
  }

  void consumeReminder(DateTime now) {
    if (!reminderDueAt(now)) return;
    snoozedUntil = null;
    if (reminder != null && !reminder!.isAfter(now)) {
      reminder = expiredAt(now) ? null : nextReminderAfter(now);
    }
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool updateDailyPlan(DateTime now) {
    if (dailyPlan.isEmpty) return false;
    final today = dateKey(now);
    if (planDate == today) return false;
    final dates = dailyPlan.keys.toList()..sort();
    // Before the start, preview day one; after the end, keep the last plan.
    final selected = dates.lastWhere(
      (d) => d.compareTo(today) <= 0,
      orElse: () => dates.first,
    );
    if (planDate == selected) return false;
    planDate = selected;
    title = selected;
    body = dailyPlan[selected]!;
    titleController.text = title;
    bodyController.text = body;
    return true;
  }

  DateTime? nextReminderAfter(DateTime now) {
    final previous = reminder;
    if (previous == null) return null;
    if (!daily) return persistent ? now.add(const Duration(minutes: 10)) : null;
    // A dated calendar is exhaustive: missing dates are intentional rest days.
    if (reminderTimes.isNotEmpty) {
      final upcoming =
          reminderTimes.keys
              .map(reminderOn)
              .whereType<DateTime>()
              .where((at) => at.isAfter(now) && !expiredAt(at))
              .toList()
            ..sort();
      return upcoming.isEmpty ? null : upcoming.first;
    }
    DateTime atDay(DateTime day) => DateTime(
      day.year,
      day.month,
      day.day,
      previous.hour,
      previous.minute,
      previous.second,
    );

    // Legacy daily notes retain their selected local clock time.
    var next = atDay(now);
    if (!next.isAfter(now)) {
      next = atDay(DateTime(now.year, now.month, now.day + 1));
    }
    return expiredAt(next) ? null : next;
  }

  DateTime? reminderOn(String day) {
    final time = reminderTimes[day];
    if (time == null ||
        !RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').hasMatch(time)) {
      return null;
    }
    return DateTime.tryParse('${day}T$time:00');
  }

  bool calendarAllowsAlert(DateTime now) {
    if (reminderTimes.isEmpty) return true;
    final today = reminderOn(dateKey(now));
    if (today == null || today.isAfter(now)) return false;
    // Catch up only inside a planned time block, including its short breaks.
    final blocks = RegExp(
      r'^(\d{2}):(\d{2})[–-](\d{2}):(\d{2})',
      multiLine: true,
    ).allMatches(dailyPlan[dateKey(now)] ?? '').toList();
    if (blocks.isEmpty) return true;
    final minute = now.hour * 60 + now.minute;
    return blocks.any(
      (m) =>
          minute >= int.parse(m[1]!) * 60 + int.parse(m[2]!) &&
          minute < int.parse(m[3]!) * 60 + int.parse(m[4]!),
    );
  }
}

Future<(String, DateTime?)?> chooseReminderFrequency(
  BuildContext context,
  DateTime start,
  DateTime? until,
) async {
  final mode = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('提醒方式'),
      content: const Text('每天按选定时间提醒。每日和每10分钟的后续提醒需要保持应用运行；错过多天只补提醒一次。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'once'),
          child: const Text('提醒一次'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'repeat'),
          child: const Text('持续提醒'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'daily'),
          child: const Text('每天重复'),
        ),
      ],
    ),
  );
  if (mode == null || !context.mounted) return null;
  if (mode != 'daily') return (mode, null);
  final first = DateTime(start.year, start.month, start.day);
  final end = await showDatePicker(
    context: context,
    helpText: '每日提醒结束日期（含当天）',
    initialDate: until != null && !until.isBefore(first)
        ? until
        : DateTime(start.year, start.month + 6, start.day),
    firstDate: first,
    lastDate: DateTime(2101),
  );
  return end == null ? null : (mode, end);
}

class MemoApp extends StatefulWidget {
  const MemoApp(
    this.prefs, {
    super.key,
    this.initializePlatform = true,
    this.storage,
  });
  final SharedPreferences prefs;
  final NoteStorage? storage;
  final bool initializePlatform;

  @override
  State<MemoApp> createState() => _MemoAppState();
}

class _MemoAppState extends State<MemoApp>
    with tray.TrayListener, WindowListener {
  late final List<Memo> notes;
  Object? loadError;
  final Set<String> changingDeletion = {};
  Timer? timer;
  HotKey? hotKey;
  bool autoStart = false;
  int z = 0;
  Size canvasSize = const Size(1100, 650);
  Future<void> notificationQueue = Future.value();
  final Set<String> scheduled = {};
  bool trayReady = false;
  bool exiting = false;
  final Map<String, WindowController> noteWindows = {};
  final Set<String> readyNotes = {};
  WindowController? mainWindow;
  Future<void> saveQueue = Future.value();
  Future<void> desktopSetup = Future.value();
  void _refresh() {
    if (mounted) setState(() {});
  }

  List<Memo> _load() {
    final loaded = <Memo>[];
    try {
      final legacy = widget.prefs.getString('notes.v1');
      final raw = widget.storage?.read(legacy) ?? legacy;
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
      final ids = <String>{};
      for (final item in jsonDecode(raw) as List) {
        final note = Memo.fromJson(Map<String, dynamic>.from(item as Map));
        loaded.add(note);
        if (note.id.isEmpty || !ids.add(note.id)) {
          throw const FormatException('便利贴编号为空或重复');
        }
        // Older versions used a soft-deletion marker without confirmation.
        // Read those records as ordinary notes so they remain accessible.
        note.updateDailyPlan(DateTime.now());
      }
      return loaded;
    } catch (error) {
      for (final note in loaded) {
        note.dispose();
      }
      loadError = error;
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    notes = _load();
    if (loadError != null) {
      if (desktop && widget.initializePlatform) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showManager());
      }
      return;
    }
    z = notes.fold(0, (max, n) => n.z > max ? n.z : max);
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkReminders(),
    );
    if (!widget.initializePlatform) return;
    for (final n in notes) {
      if (n.nextAlertAt != null) {
        _scheduleNotification(n);
      }
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
    if (exiting) return;
    exiting = true;
    final timing = ExitTimingLog();
    try {
      await timing.measure(ExitStage.shutdown, () async {
        // Let any in-flight deletion finish its save or rollback before
        // asking child windows to flush their still-active note IDs.
        while (changingDeletion.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await _pruneClosedNoteWindows();
        final windows = noteWindows.values.toList();
        for (var i = 0; i < windows.length; i++) {
          await timing.measure(
            ExitStage.saveNote,
            () => windows[i].invokeMethod('flush'),
            noteIndex: i + 1,
          );
        }
        await timing.measure(ExitStage.saveAll, _save);
        await timing.measure(ExitStage.notifications, () => notificationQueue);
        // Keep the host's message loop and channel registry alive until every
        // child engine has shut down. Leaving them for static destruction can
        // call back into Flutter after its registries have already gone away.
        await timing.measure(ExitStage.closeNotes, () async {
          final host = mainWindow ?? await WindowController.fromCurrentEngine();
          for (final window in await WindowController.getAll()) {
            if (window.windowId == host.windowId) continue;
            final needsSave = noteWindows.values.any(
              (noteWindow) => noteWindow.windowId == window.windowId,
            );
            await window.invokeMethod('close', {'flush': needsSave});
          }
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          // Include windows whose deletion has removed them from noteWindows
          // but whose delayed native close has not run yet.
          while ((await WindowController.getAll()).any(
            (window) => window.windowId != host.windowId,
          )) {
            if (DateTime.now().isAfter(deadline)) {
              throw StateError('便利贴窗口尚未关闭，请重试');
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          noteWindows.clear();
          readyNotes.clear();
        });
        await timing.measure(ExitStage.tray, tray.trayManager.destroy);
        // The engine may terminate before this future replies. A start without
        // done here means "close requested", not necessarily a stalled close.
        await timing.measure(ExitStage.closeWindows, windowManager.destroy);
      });
    } catch (error) {
      exiting = false;
      try {
        await _pruneClosedNoteWindows();
      } catch (_) {}
      await _showManager();
      _notice('保存尚未完成，未退出：$error');
    }
  }

  Future<void> _save() {
    if (loadError != null) {
      return Future.error(StateError('原有数据未能读取，已停止保存以保护记录'));
    }
    saveQueue = saveQueue.catchError((Object _) {}).then((_) async {
      final snapshot = jsonEncode([for (final n in notes) n.toJson()]);
      if (widget.storage != null) {
        await widget.storage!.write(snapshot);
      } else if (!await widget.prefs.setString('notes.v1', snapshot)) {
        throw StateError('无法保存便利贴');
      }
    });
    return saveQueue;
  }

  void _newNote() {
    if (exiting) return;
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

  Future<void> _delete(Memo n) async {
    if (exiting || !notes.contains(n) || !changingDeletion.add(n.id)) return;
    final index = notes.indexOf(n);
    setState(() => notes.remove(n));
    try {
      try {
        await _save();
      } catch (_) {
        setState(() {
          notes.insert(index.clamp(0, notes.length), n);
        });
        // A concurrent edit may have queued another save during this failed
        // operation. Persist the rollback after those requests as well.
        try {
          await _save();
        } catch (_) {}
        rethrow;
      }
      readyNotes.remove(n.id);
      unawaited(_stopReminderSpeech());
      final window = noteWindows.remove(n.id);
      if (window != null) await window.invokeMethod('close');
      await _scheduleNotification(n);
      _notice('已彻底删除便利贴');
      WidgetsBinding.instance.addPostFrameCallback((_) => n.dispose());
      if (notes.isEmpty && desktop && widget.initializePlatform && !trayReady) {
        await _showManager();
      }
    } finally {
      changingDeletion.remove(n.id);
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
    if (exiting) return;
    final now = DateTime.now();
    for (final n in notes) {
      if (n.updateDailyPlan(now)) {
        _refresh();
        _save();
        _updateNoteWindow(n);
      }
      if (!n.reminderDueAt(now) || !mounted) continue;
      // A missed reminder must wait until its window can receive the alert.
      if (desktop && widget.initializePlatform && !readyNotes.contains(n.id)) {
        continue;
      }
      if (!n.allowsReminderAlert(now)) {
        n.consumeReminder(now);
        _save();
        _scheduleNotification(n);
        _updateNoteWindow(n);
        continue;
      }
      messengerKey.currentState?.hideCurrentSnackBar();
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(minutes: 1),
          content: ReminderActions(
            daily: n.daily,
            onAction: (minutes) async {
              if (minutes == null) {
                await _acknowledgeReminder(n);
              } else {
                await _snoozeReminder(n, Duration(minutes: minutes));
              }
              messengerKey.currentState?.hideCurrentSnackBar();
            },
          ),
        ),
      );
      if (!scheduled.remove(n.id)) _showSystemNotification(n);
      _speakReminder(n);
      noteWindows[n.id]?.invokeMethod('alert');
      setState(() => n.consumeReminder(now));
      _save();
      _updateNoteWindow(n);
      if (n.nextAlertAt != null) _scheduleNotification(n);
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
        // Dated desktop plans use their own window, without an OS toast entry.
        if (desktop && n.dailyPlan.isNotEmpty) return;
        final when = n.nextAlertAt;
        if (when == null || !notes.contains(n)) return;
        if (!when.isAfter(DateTime.now())) return;
        if (Platform.isLinux) {
          _notice('Linux 定时提醒需要保持应用运行。');
          return;
        }
        await notifications.zonedSchedule(
          id: id,
          title: n.dailyPlan.containsKey(Memo.dateKey(when))
              ? Memo.dateKey(when)
              : n.title,
          body:
              n.dailyPlan[Memo.dateKey(when)] ??
              (n.body.isEmpty ? '该看一眼这张便利贴了' : n.body),
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
      n.snoozedUntil = null;
      n.persistent = false;
      n.daily = false;
      n.repeatUntil = null;
    });
    unawaited(_stopReminderSpeech());
    await _save();
    await _scheduleNotification(n);
    _updateNoteWindow(n);
  }

  Future<void> _snoozeReminder(Memo n, Duration delay) async {
    if (!mounted || exiting || !notes.contains(n)) {
      return;
    }
    setState(() => n.snoozeReminder(delay));
    unawaited(_stopReminderSpeech());
    await _save();
    await _scheduleNotification(n);
    _updateNoteWindow(n);
  }

  Future<void> _acknowledgeReminder(Memo n) async {
    if (!n.daily) {
      await _cancelReminder(n);
      return;
    }
    setState(() => n.snoozedUntil = null);
    unawaited(_stopReminderSpeech());
    await _save();
    await _scheduleNotification(n);
    _updateNoteWindow(n);
  }

  Future<void> _stopReminderSpeech() async {
    if (!widget.initializePlatform) return;
    try {
      await speech.stop();
    } catch (_) {}
  }

  Future<void> _showSystemNotification(Memo n) async {
    if (desktop && n.dailyPlan.isNotEmpty) return;
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
    if (n.nextAlertAt != null) {
      final action = await showDialog<String>(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('已有提醒'),
          content: Text(
            '提醒时间：${n.nextAlertAt}${n.daily ? '\n每天重复，至 ${n.repeatUntil?.toIso8601String().split('T').first ?? '不限'}' : ''}',
          ),
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
    final frequency = await chooseReminderFrequency(
      navigatorKey.currentContext!,
      when,
      n.repeatUntil,
    );
    if (!mounted || !notes.contains(n) || frequency == null) return;
    setState(() {
      n.reminder = when;
      n.snoozedUntil = null;
      n.persistent = frequency.$1 == 'repeat';
      n.daily = frequency.$1 == 'daily';
      n.repeatUntil = frequency.$2;
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
    home: loadError != null
        ? Scaffold(
            appBar: AppBar(title: const Text('原有便利贴暂时无法读取')),
            body: const Padding(
              padding: EdgeInsets.all(24),
              child: Text('已停止自动保存，原始记录不会被空白便利贴覆盖。请保留数据文件并重新打开应用，或修复数据后重试。'),
            ),
          )
        : LayoutBuilder(
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
          Text('Ctrl + Alt + M 新建', style: const TextStyle(color: memoMuted)),
        const SizedBox(width: 10),
        IconButton(
          tooltip: autoStart ? '已启用开机自启动' : '启用开机自启动',
          onPressed: _toggleAutoStart,
          icon: Icon(
            Icons.power_settings_new,
            color: autoStart ? memoAccent : memoMuted,
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

Future<bool> confirmMemoDeletion(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(12),
        title: const Text('彻底删除便利贴？'),
        content: const Text('正文、计划和提醒将永久删除，无法恢复。'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-permanent-delete'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    ) ==
    true;

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
    this.onTaskChanged,
    this.onClose,
    this.onConfirmDelete,
  });
  final Memo note;
  final VoidCallback onChanged;
  final FutureOr<void> Function(Memo) onDelete;
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
  final void Function(String key, bool done)? onTaskChanged;
  final VoidCallback? onClose;
  final Future<bool> Function()? onConfirmDelete;

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
      shadowColor: memoInk.withValues(alpha: .18),
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
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onSelected: (action) async {
                      if (action != 'delete') return;
                      try {
                        final confirmed =
                            await (onConfirmDelete?.call() ??
                                confirmMemoDeletion(context));
                        if (!confirmed) return;
                        await onDelete(note);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('操作未完成，请重试：$error')),
                          );
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('删除便利贴'),
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  textSurface(
                    IconButton(
                      tooltip: '收起便利贴',
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: note.dailyPlan.isNotEmpty
                  ? textSurface(
                      PlanTaskList(
                        key: ValueKey('${note.id}-${note.planDate}'),
                        note: note,
                        onChanged: (key, done) {
                          if (onTaskChanged != null) {
                            onTaskChanged!(key, done);
                          } else {
                            onChanged();
                          }
                        },
                      ),
                    )
                  : textSurface(
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
                  note.nextAlertAt == null
                      ? Icons.notifications_none
                      : Icons.notifications_active,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    note.nextAlertAt == null
                        ? '设置提醒'
                        : '${note.nextAlertAt!.hour.toString().padLeft(2, '0')}:${note.nextAlertAt!.minute.toString().padLeft(2, '0')}${note.snoozedUntil != null
                              ? ' · 稍后'
                              : note.daily
                              ? (note.reminderTimes.isNotEmpty ? ' · 学习日' : ' · 每天')
                              : note.persistent
                              ? ' · 持续'
                              : ''}',
                    style: const TextStyle(fontSize: 12, color: memoMuted),
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

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .2, size.height * .5)
        ..lineTo(size.width * .42, size.height * .72)
        ..lineTo(size.width * .82, size.height * .28),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) =>
      color != oldDelegate.color;
}

class PlanTaskList extends StatefulWidget {
  const PlanTaskList({super.key, required this.note, required this.onChanged});
  final Memo note;
  final void Function(String key, bool done) onChanged;

  @override
  State<PlanTaskList> createState() => _PlanTaskListState();
}

class _PlanTaskListState extends State<PlanTaskList> {
  static final timed = RegExp(r'^\d{2}:\d{2}[–—-]\d{2}:\d{2}');

  @override
  Widget build(BuildContext context) {
    final lines = widget.note.body.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        if (!timed.hasMatch(line)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              line,
              style: const TextStyle(fontSize: 12, color: memoMuted),
            ),
          );
        }
        final key = widget.note.taskKey(line);
        final done = widget.note.completedTasks.contains(key);
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 450);
        return AnimatedContainer(
          key: ValueKey('task-$key'),
          duration: duration,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
          decoration: BoxDecoration(
            color: done ? const Color(0xFFE0E0E0) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                checked: done,
                child: IconButton(
                  tooltip: done ? '撤销完成' : '标记完成',
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  // Draw the check so neither emoji colors nor icon-font
                  // availability can change its appearance on Windows.
                  icon: CustomPaint(
                    size: const Size(20, 20),
                    painter: _CheckPainter(
                      done ? const Color(0xFF616161) : memoAccent,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      if (done) {
                        widget.note.completedTasks.remove(key);
                      } else {
                        widget.note.completedTasks.add(key);
                      }
                    });
                    widget.onChanged(key, !done);
                  },
                ),
              ),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: done ? const Color(0xFF616161) : memoInk,
                    decoration: done
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                  child: Text(line),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
