import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const papers = [
  Color(0xfffff3a6),
  Color(0xffffd6a5),
  Color(0xffffc6d9),
  Color(0xffcdeccf),
];
bool get desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (desktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1180, 760),
      minimumSize: Size(820, 560),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      title: '桌面便利贴',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
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
  });
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
  );
}

class MemoApp extends StatefulWidget {
  const MemoApp(this.prefs, {super.key});
  final SharedPreferences prefs;

  @override
  State<MemoApp> createState() => _MemoAppState();
}

class _MemoAppState extends State<MemoApp> {
  late final List<Memo> notes = _load();
  Timer? timer;
  HotKey? hotKey;
  bool autoStart = false;
  int z = 0;

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
      const Duration(seconds: 30),
      (_) => _checkReminders(),
    );
    _setupDesktop();
  }

  Future<void> _setupDesktop() async {
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
    super.dispose();
  }

  Future<void> _save() => widget.prefs.setString(
    'notes.v1',
    jsonEncode(notes.map((n) => n.toJson()).toList()),
  );

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
  }

  void _front(Memo n) {
    setState(() {
      z++;
      n.z = z;
    });
    _save();
  }

  void _delete(Memo n) {
    setState(() => notes.removeWhere((item) => item.id == n.id));
    _save();
  }

  void _checkReminders() {
    final now = DateTime.now();
    for (final n in notes) {
      if (n.reminder == null || n.reminder!.isAfter(now) || !mounted) continue;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('提醒：${n.title}')));
      setState(
        () => n.reminder = n.persistent
            ? now.add(const Duration(minutes: 10))
            : null,
      );
      _save();
    }
  }

  Future<void> _reminder(Memo n) async {
    final picked = await showTimePicker(
      context: context,
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
    final persistent =
        await showDialog<bool>(
          context: context,
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
        ) ??
        false;
    setState(() {
      n.reminder = when;
      n.persistent = persistent;
    });
    _save();
  }

  Future<void> _toggleAutoStart() async {
    if (!desktop) return;
    try {
      if (autoStart) {
        await launchAtStartup.disable();
      } else {
        await launchAtStartup.enable();
      }
      setState(() => autoStart = !autoStart);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前系统暂不支持开机自启动')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '桌面便利贴',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffc57b57)),
      scaffoldBackgroundColor: const Color(0xfff4ede4),
    ),
    home: LayoutBuilder(
      builder: (context, c) => c.maxWidth > 700 ? _desktop() : _mobile(),
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
                      : Stack(
                          children: [
                            for (final n in sorted)
                              Positioned(
                                left: n.x,
                                top: n.y,
                                child: MemoCard(
                                  note: n,
                                  onChanged: _save,
                                  onDelete: _delete,
                                  onReminder: _reminder,
                                  onNew: _newNote,
                                  onFront: _front,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
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
                  padding: const EdgeInsets.only(bottom: 14),
                  child: MemoCard(
                    note: n,
                    compact: true,
                    onChanged: _save,
                    onDelete: _delete,
                    onReminder: _reminder,
                    onNew: _newNote,
                    onFront: _front,
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
    this.compact = false,
  });
  final Memo note;
  final VoidCallback onChanged;
  final ValueChanged<Memo> onDelete;
  final ValueChanged<Memo> onReminder;
  final VoidCallback onNew;
  final ValueChanged<Memo> onFront;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: papers[note.color % papers.length],
      elevation: 5,
      shadowColor: Colors.brown.withValues(alpha: .25),
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: note.title),
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
                ),
                IconButton(
                  tooltip: '新建便利贴',
                  onPressed: onNew,
                  icon: const Icon(Icons.add, size: 20),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: () => onDelete(note),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TextField(
                controller: TextEditingController(text: note.body),
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
                TextButton(
                  onPressed: () => onReminder(note),
                  child: const Text('提醒'),
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
      onPanStart: (_) => onFront(note),
      onPanUpdate: (d) {
        note.x += d.delta.dx;
        note.y += d.delta.dy;
        onChanged();
      },
      onPanEnd: (_) => onChanged(),
      child: SizedBox(width: 270, height: 250, child: card),
    );
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
