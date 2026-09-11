part of 'main.dart';

Future<void> closeDesktopNoteWindow() async {
  await windowManager.setPreventClose(false);
  // destroy() posts WM_QUIT on Windows; close() targets this window only.
  await windowManager.close();
}

// The manager is the only writer and reminder scheduler. Note windows only
// send field-level edits, so moving one note cannot overwrite another's text.
extension _DesktopHost on _MemoAppState {
  Future<void> _setupNoteWindows() async {
    try {
      mainWindow = await WindowController.fromCurrentEngine();
      await mainWindow!.setWindowMethodHandler((call) async {
        final data = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        if (call.method == 'new') {
          _newNote();
          return null;
        }
        if (call.method == 'startup') {
          return _autoStartSetting(data['enabled'] as bool?);
        }
        if (call.method == 'exit') {
          // Reply before the host flushes and closes all child engines.
          Timer(const Duration(milliseconds: 100), _exitApp);
          return true;
        }
        final matches = notes.where((n) => n.id == data['id']);
        if (matches.isEmpty) return null;
        final note = matches.first;
        switch (call.method) {
          case 'ready':
            noteWindows[note.id] = WindowController.fromWindowId(
              data['window'] as String,
            );
            return note.toJson();
          case 'edit':
            if (data.containsKey('title')) {
              note.title = data['title'] as String;
              note.titleController.text = note.title;
            }
            if (data.containsKey('body')) {
              note.body = data['body'] as String;
              note.bodyController.text = note.body;
            }
            if (data.containsKey('x')) {
              note.x = (data['x'] as num).toDouble();
              note.y = (data['y'] as num).toDouble();
              note.collapsed = data['collapsed'] as bool;
              note.dock = data['dock'] as String;
            }
            if (data.containsKey('reminder')) {
              note.reminder = DateTime.tryParse(
                data['reminder'] as String? ?? '',
              );
              note.persistent = data['persistent'] as bool;
              await _scheduleNotification(note);
              if (note.reminder == null) await speech.stop();
            }
            _refresh();
            await _save();
            return true;
          case 'delete':
            _delete(note);
            return true;
          case 'cancel':
            await _cancelReminder(note);
            return true;
          case 'front':
            _front(note);
            return true;
        }
        return null;
      });
      if (notes.isEmpty) {
        _newNote();
      } else {
        for (final note in [...notes]..sort((a, b) => a.z.compareTo(b.z))) {
          await _openNote(note);
        }
      }
    } catch (error) {
      await _showManager();
      _notice('独立便利贴窗口打开失败：$error');
    }
  }

  Future<void> _openNote(Memo note) async {
    try {
      final existing = noteWindows[note.id];
      if (existing != null) {
        await existing.invokeMethod('reveal');
        return;
      }
      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode({
            'type': 'note',
            'parent': mainWindow!.windowId,
            'note': note.toJson(),
          }),
        ),
      );
      noteWindows[note.id] = controller;
    } catch (error) {
      await _showManager();
      _notice('无法打开便利贴：$error');
    }
  }

  Future<void> _showManager() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _showNotes() async {
    if (notes.isEmpty) {
      _newNote();
    } else {
      for (final note in [...notes]..sort((a, b) => a.z.compareTo(b.z))) {
        await _openNote(note);
      }
    }
  }

  Future<void> _updateNoteWindow(Memo note) async {
    try {
      await noteWindows[note.id]?.invokeMethod('reminderState', {
        'reminder': note.reminder?.toIso8601String(),
        'persistent': note.persistent,
      });
    } catch (_) {
      _notice('便利贴窗口同步失败，请重新打开应用。');
    }
  }

  Widget _windowManagerPage() => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          _bar(),
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text('便利贴已独立显示在桌面。关闭这个管理窗口不会关闭便利贴。'),
          ),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _newNote,
                      icon: const Icon(Icons.add),
                      label: const Text('创建第一张便利贴'),
                    ),
                  )
                : ListView(
                    children: [
                      for (final note in [
                        ...notes,
                      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
                        ListTile(
                          leading: Icon(
                            Icons.sticky_note_2,
                            color: papers[note.color % papers.length],
                          ),
                          title: Text(
                            note.title.isEmpty ? '未命名便利贴' : note.title,
                          ),
                          subtitle: Text(
                            note.reminder == null
                                ? '未设提醒'
                                : '提醒：${note.reminder}',
                          ),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => _openNote(note),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

// Geometry stays in logical pixels, including displays left/above the primary.
Rect fitDesktopNote(Rect bounds, Rect workArea) => Rect.fromLTWH(
  bounds.left.clamp(
    workArea.left,
    math.max(workArea.left, workArea.right - bounds.width),
  ),
  bounds.top.clamp(
    workArea.top,
    math.max(workArea.top, workArea.bottom - bounds.height),
  ),
  bounds.width,
  bounds.height,
);

String? desktopDockEdge(Rect bounds, Rect workArea) {
  // Signed gaps: crossing an edge must still count as touching it.
  final edges = {
    'left': bounds.left - workArea.left,
    'right': workArea.right - bounds.right,
    'top': bounds.top - workArea.top,
    'bottom': workArea.bottom - bounds.bottom,
  };
  final nearest = edges.entries.reduce((a, b) => a.value <= b.value ? a : b);
  return nearest.value <= 14 ? nearest.key : null;
}

Alignment desktopDockAlignment(String edge) => switch (edge) {
  'left' => Alignment.centerLeft,
  'right' => Alignment.centerRight,
  'top' => Alignment.topCenter,
  _ => Alignment.bottomCenter,
};

Rect desktopNoteBounds(Rect bounds, Rect work, {String? dock}) {
  final fitted = fitDesktopNote(bounds, work);
  return switch (dock) {
    'left' => fitted.shift(Offset(work.left - fitted.left, 0)),
    'right' => fitted.shift(Offset(work.right - fitted.right, 0)),
    'top' => fitted.shift(Offset(0, work.top - fitted.top)),
    'bottom' => fitted.shift(Offset(0, work.bottom - fitted.bottom)),
    _ => fitted,
  };
}

class DesktopNoteApp extends StatefulWidget {
  const DesktopNoteApp({
    super.key,
    required this.controller,
    required this.arguments,
  });
  final WindowController controller;
  final Map<String, dynamic> arguments;
  @override
  State<DesktopNoteApp> createState() => _DesktopNoteAppState();
}

class _DesktopNoteAppState extends State<DesktopNoteApp>
    with WindowListener, TickerProviderStateMixin {
  late final Memo note = Memo.fromJson(
    Map<String, dynamic>.from(widget.arguments['note'] as Map),
  );
  late final host = WindowController.fromWindowId(
    widget.arguments['parent'] as String,
  );
  final navigator = GlobalKey<NavigatorState>();
  final messenger = GlobalKey<ScaffoldMessengerState>();
  late final shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final dockSlide = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 180),
  );
  late bool visualCollapsed = note.collapsed;
  Timer? editTimer;
  Timer? moveTimer;
  Timer? hideTimer;
  final titleFocus = FocusNode();
  final bodyFocus = FocusNode();
  late bool autoDock = note.collapsed;
  bool pointerInside = false;
  bool dragging = false;
  bool changingDock = false;
  Future<void> edits = Future.value();
  bool applyingBounds = false;
  bool editorOpen = false;
  bool settingsOpen = false;
  bool closing = false;
  bool alerting = false;

  @override
  void initState() {
    super.initState();
    titleFocus.addListener(_scheduleHide);
    bodyFocus.addListener(_scheduleHide);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.controller.setWindowMethodHandler((call) async {
        switch (call.method) {
          case 'flush':
            await _flush();
            return {'note': note.toJson(), 'alerting': alerting};
          case 'close':
            closing = true;
            // Reply before destroying the engine that owns this channel.
            Timer(const Duration(milliseconds: 100), closeDesktopNoteWindow);
            return true;
          case 'reveal':
            if (note.collapsed) await _expand();
            await windowManager.show();
            await windowManager.focus();
            return true;
          case 'reminderState':
            final data = call.arguments as Map;
            setState(() {
              note.reminder = DateTime.tryParse(
                data['reminder'] as String? ?? '',
              );
              note.persistent = data['persistent'] as bool;
            });
            return true;
          case 'alert':
            if (note.collapsed) await _expand();
            await windowManager.show();
            await windowManager.focus();
            if (!mounted) return false;
            setState(() => alerting = true);
            if (!WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations) {
              shake.forward(from: 0);
            }
            return true;
        }
        return null;
      });
      await host.invokeMethod('ready', {
        'id': note.id,
        'window': widget.controller.windowId,
      });
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(286, 266),
          minimumSize: Size(34, 34),
          backgroundColor: Colors.transparent,
          skipTaskbar: true,
          titleBarStyle: TitleBarStyle.hidden,
        ),
        () async {
          await windowManager.setAsFrameless();
          await windowManager.setResizable(false);
          await windowManager.setTitle(note.title);
          await windowManager.setPreventClose(true);
          await _place(await _workArea(Offset(note.x, note.y)));
          windowManager.addListener(this);
          await windowManager.show();
        },
      );
    } catch (error) {
      _error(error);
    }
  }

  void _error(Object error) {
    messenger.currentState?.showSnackBar(
      SnackBar(content: Text('操作未完成：$error')),
    );
  }

  Future<void> _send(Map<String, dynamic> fields) {
    edits = edits
        .catchError((Object error) {
          _error(error);
        })
        .then((_) async {
          final saved = await host.invokeMethod('edit', {
            'id': note.id,
            ...fields,
          });
          if (saved != true) throw StateError('保存失败，请勿关闭便利贴');
        });
    return edits;
  }

  void _changed() {
    editTimer?.cancel();
    editTimer = Timer(const Duration(milliseconds: 150), () {
      _flush().catchError((Object error) {
        _error(error);
      });
    });
  }

  Future<void> _flush() async {
    editTimer?.cancel();
    await _send({'title': note.title, 'body': note.body});
    await windowManager.setTitle(note.title.isEmpty ? '便利贴' : note.title);
  }

  Future<Rect> _workArea(Offset point) async {
    final displays = await screenRetriever.getAllDisplays();
    final areas = displays
        .map(
          (d) => (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
        )
        .toList();
    if (areas.isEmpty) throw StateError('无法读取屏幕尺寸');
    areas.sort(
      (a, b) => (a.center - point).distanceSquared.compareTo(
        (b.center - point).distanceSquared,
      ),
    );
    return areas.firstWhere(
      (area) => area.contains(point),
      orElse: () => areas.first,
    );
  }

  Future<void> _place(Rect work, {bool animate = false}) async {
    applyingBounds = true;
    try {
      final vertical = note.dock == 'left' || note.dock == 'right';
      final size = note.collapsed
          ? (vertical ? const Size(50, 166) : const Size(166, 50))
          : const Size(286, 266);
      var bounds = desktopNoteBounds(
        Offset(note.x, note.y) & size,
        work,
        dock: note.collapsed ? note.dock : null,
      );
      final smooth =
          animate &&
          !WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations;
      // Keep the full native surface while Flutter slides the paper out.
      if (smooth && note.collapsed && !visualCollapsed) {
        await dockSlide.reverse(from: 1).orCancel;
      }
      if (!mounted || closing) return;
      visualCollapsed = note.collapsed;
      dockSlide.value = smooth && !note.collapsed ? 0 : 1;
      setState(() {});
      // One resize per transition, never one per animation frame. Windows may
      // enforce a wider minimum; position using the size it actually accepted.
      await windowManager.setBounds(bounds);
      final actual = await windowManager.getBounds();
      bounds = desktopNoteBounds(
        actual,
        work,
        dock: note.collapsed ? note.dock : null,
      );
      if ((bounds.topLeft - actual.topLeft).distance > 0.5) {
        await windowManager.setPosition(bounds.topLeft);
      }
      if (smooth && !note.collapsed) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || closing) return;
        await dockSlide.forward().orCancel;
      }
      note.x = bounds.left;
      note.y = bounds.top;
      if (mounted) setState(() {});
    } finally {
      applyingBounds = false;
    }
  }

  Future<void> _savePosition() => _send({
    'x': note.x,
    'y': note.y,
    // Hover expansion is temporary; reopen in the compact docked state.
    'collapsed': autoDock || note.collapsed,
    'dock': note.dock,
  });

  @override
  void onWindowMoved() async {
    if (applyingBounds ||
        editorOpen ||
        note.collapsed ||
        closing ||
        !dragging) {
      return;
    }
    try {
      final bounds = await windowManager.getBounds();
      final work = await _workArea(bounds.center);
      note.x = bounds.left;
      note.y = bounds.top;
      final edge = desktopDockEdge(bounds, work);
      autoDock = edge != null;
      if (edge != null) {
        note.dock = edge;
        note.collapsed = true;
      }
      await _place(work, animate: edge != null);
      await _savePosition();
    } catch (error) {
      _error(error);
    } finally {
      dragging = false;
    }
  }

  Future<void> _expand({bool focus = true}) async {
    if (applyingBounds || changingDock || closing || !note.collapsed) return;
    changingDock = true;
    try {
      hideTimer?.cancel();
      final work = await _workArea(Offset(note.x, note.y));
      note.collapsed = false;
      if (note.dock == 'left') note.x = work.left;
      if (note.dock == 'right') note.x = work.right - 286;
      if (note.dock == 'top') note.y = work.top;
      if (note.dock == 'bottom') note.y = work.bottom - 266;
      await _place(work, animate: true);
      await _savePosition();
      if (focus) await windowManager.focus();
    } finally {
      changingDock = false;
    }
    _scheduleHide();
  }

  bool get _mayHide =>
      mounted &&
      canAutoHideNote(
        docked: autoDock,
        collapsed: note.collapsed,
        hovered: pointerInside,
        editing: titleFocus.hasFocus || bodyFocus.hasFocus,
        busy:
            editorOpen ||
            alerting ||
            dragging ||
            closing ||
            applyingBounds ||
            changingDock,
      );

  void _scheduleHide() {
    hideTimer?.cancel();
    if (!_mayHide) return;
    hideTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!_mayHide) return;
      try {
        await _flush();
        if (!_mayHide) return;
        changingDock = true;
        note.collapsed = true;
        await _place(await _workArea(Offset(note.x, note.y)), animate: true);
        await _savePosition();
      } catch (error) {
        _error(error);
      } finally {
        changingDock = false;
      }
      if (mounted && pointerInside && note.collapsed && !closing) {
        await _expand(focus: false);
      }
    });
  }

  @override
  void onWindowBlur() {
    if (editorOpen) return;
    titleFocus.unfocus();
    bodyFocus.unfocus();
    _scheduleHide();
  }

  Future<void> _openSettings() async {
    if (editorOpen || applyingBounds || changingDock) return;
    editorOpen = true;
    hideTimer?.cancel();
    try {
      await _flush();
      titleFocus.unfocus();
      bodyFocus.unfocus();
      if (mounted) setState(() => settingsOpen = true);
    } catch (error) {
      editorOpen = false;
      _error(error);
      _scheduleHide();
    }
  }

  void _closeSettings() {
    setState(() => settingsOpen = false);
    editorOpen = false;
    _scheduleHide();
  }

  Future<void> _remind() async {
    if (editorOpen) return;
    editorOpen = true;
    try {
      await _flush();
      // A picker needs more space than the paper; restore the note afterwards.
      await windowManager.setSize(const Size(420, 580));
      if (note.reminder != null) {
        final action = await showDialog<String>(
          context: navigator.currentContext!,
          builder: (ctx) => AlertDialog(
            title: const Text('已有提醒'),
            content: Text('提醒时间：${note.reminder}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('返回'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('取消提醒'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'edit'),
                child: const Text('修改时间'),
              ),
            ],
          ),
        );
        if (action == null || !mounted) return;
        if (action == 'cancel') {
          await host.invokeMethod('cancel', {'id': note.id});
          return;
        }
      }
      final when = await showDatePicker(
        context: navigator.currentContext!,
        initialDate: note.reminder ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (when == null || !mounted) return;
      final time = await showTimePicker(
        context: navigator.currentContext!,
        initialTime: TimeOfDay.fromDateTime(
          note.reminder ?? DateTime.now().add(const Duration(minutes: 5)),
        ),
      );
      if (time == null || !mounted) return;
      final date = DateTime(
        when.year,
        when.month,
        when.day,
        time.hour,
        time.minute,
      );
      if (!date.isAfter(DateTime.now())) {
        _error('请选择未来的提醒时间');
        return;
      }
      final mode = await showDialog<String>(
        context: navigator.currentContext!,
        builder: (ctx) => AlertDialog(
          title: const Text('提醒方式'),
          content: const Text('持续提醒每 10 分钟再次提醒，直到手动取消。语音需要保持应用运行。'),
          actions: [
            if (note.reminder != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('取消已有提醒'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'once'),
              child: const Text('提醒一次'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'repeat'),
              child: const Text('持续提醒'),
            ),
          ],
        ),
      );
      if (mode == null || !mounted) return;
      setState(() {
        note.reminder = mode == 'cancel' ? null : date;
        note.persistent = mode == 'repeat';
      });
      await _send({
        'reminder': note.reminder?.toIso8601String(),
        'persistent': note.persistent,
      });
    } catch (error) {
      _error(error);
    } finally {
      editorOpen = false;
      await _place(await _workArea(Offset(note.x, note.y)));
      _scheduleHide();
    }
  }

  @override
  void onWindowClose() async {
    if (closing) return;
    try {
      await _flush();
      await windowManager.hide();
    } catch (error) {
      _error(error);
    }
  }

  @override
  void onWindowMove() {
    // Linux does not emit the final "moved" event.
    if (!Platform.isLinux || applyingBounds || editorOpen || closing) return;
    moveTimer?.cancel();
    moveTimer = Timer(const Duration(milliseconds: 250), onWindowMoved);
  }

  @override
  void dispose() {
    editTimer?.cancel();
    moveTimer?.cancel();
    hideTimer?.cancel();
    titleFocus.dispose();
    bodyFocus.dispose();
    dockSlide.dispose();
    shake.dispose();
    note.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    scaffoldMessengerKey: messenger,
    debugShowCheckedModeBanner: false,
    theme: memoTheme(),
    home: Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) {
          pointerInside = true;
          hideTimer?.cancel();
          if (note.collapsed) {
            _expand(focus: false).catchError((Object error) {
              _error(error);
            });
          }
        },
        onExit: (_) {
          pointerInside = false;
          _scheduleHide();
        },
        child: ClipRect(
          child: OverflowBox(
            alignment: visualCollapsed
                ? desktopDockAlignment(note.dock)
                : Alignment.center,
            minWidth: visualCollapsed
                ? (note.dock == 'left' || note.dock == 'right' ? 50 : 166)
                : 286,
            maxWidth: visualCollapsed
                ? (note.dock == 'left' || note.dock == 'right' ? 50 : 166)
                : 286,
            minHeight: visualCollapsed
                ? (note.dock == 'left' || note.dock == 'right' ? 166 : 50)
                : 266,
            maxHeight: visualCollapsed
                ? (note.dock == 'left' || note.dock == 'right' ? 166 : 50)
                : 266,
            child: Center(
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: dockSlideOffset(note.dock),
                      end: Offset.zero,
                    ).animate(
                      dockSlide.drive(CurveTween(curve: Curves.easeOutCubic)),
                    ),
                child: AnimatedBuilder(
                  animation: shake,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                      math.sin(shake.value * math.pi * 8) *
                          4 *
                          (1 - shake.value),
                      0,
                    ),
                    child: child,
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: settingsOpen
                            ? NoteSettingsPanel(
                                color: papers[note.color % papers.length],
                                onStartup: (enabled) async {
                                  final result = await host.invokeMethod<bool>(
                                    'startup',
                                    {'enabled': ?enabled},
                                  );
                                  if (result == null) {
                                    throw StateError('无法读取开机自启动设置');
                                  }
                                  return result;
                                },
                                onBack: _closeSettings,
                                onReminder: () {
                                  _closeSettings();
                                  _remind();
                                },
                                onExit: () async {
                                  await _flush();
                                  await host.invokeMethod('exit');
                                },
                              )
                            : MemoCard(
                                note: note,
                                collapsedOverride: visualCollapsed,
                                titleFocusNode: titleFocus,
                                bodyFocusNode: bodyFocus,
                                onChanged: _changed,
                                onDelete: (_) async {
                                  await _flush();
                                  await host.invokeMethod('delete', {
                                    'id': note.id,
                                  });
                                },
                                onReminder: (_) => _remind(),
                                onSettings: _openSettings,
                                onNew: () async {
                                  await _flush();
                                  await host.invokeMethod('new');
                                },
                                onFront: (_) {
                                  windowManager.focus();
                                  host.invokeMethod('front', {'id': note.id});
                                },
                                onToggleCollapsed: (_) => _expand(),
                                onDragStart: () {
                                  hideTimer?.cancel();
                                  dragging = true;
                                  windowManager.startDragging();
                                },
                              ),
                      ),
                      if (alerting)
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 16,
                          child: Material(
                            color: const Color(0xff67452f),
                            borderRadius: BorderRadius.circular(12),
                            child: TextButton(
                              onPressed: () async {
                                await host.invokeMethod('cancel', {
                                  'id': note.id,
                                });
                                if (mounted) setState(() => alerting = false);
                                _scheduleHide();
                              },
                              child: const Text(
                                '到时间了 · 我知道了，停止提醒',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class NoteSettingsPanel extends StatefulWidget {
  const NoteSettingsPanel({
    super.key,
    required this.color,
    required this.onStartup,
    required this.onBack,
    required this.onReminder,
    required this.onExit,
  });

  final Color color;
  final Future<bool> Function(bool? enabled) onStartup;
  final VoidCallback onBack;
  final VoidCallback onReminder;
  final Future<void> Function() onExit;

  @override
  State<NoteSettingsPanel> createState() => _NoteSettingsPanelState();
}

class _NoteSettingsPanelState extends State<NoteSettingsPanel> {
  bool? autoStart;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _startup(null);
  }

  Future<void> _startup(bool? enabled) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final actual = await widget.onStartup(enabled);
      if (mounted) setState(() => autoStart = actual);
    } catch (_) {
      if (mounted) setState(() => error = '自启动设置失败，点击重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _exit() async {
    setState(() => busy = true);
    try {
      await widget.onExit();
    } catch (_) {
      if (mounted) setState(() => error = '保存未完成，请稍后重试退出');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 270,
    height: 250,
    child: Material(
      color: widget.color,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回便利贴',
                  onPressed: busy ? null : widget.onBack,
                  icon: const Icon(Icons.arrow_back, size: 20),
                ),
                const Text(
                  '便利贴设置',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (busy) ...[
                  const Spacer(),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('开机自启动'),
                    subtitle: const Text('此电脑的所有便利贴'),
                    value: autoStart ?? false,
                    onChanged: busy || autoStart == null ? null : _startup,
                  ),
                  if (error != null)
                    TextButton(
                      onPressed: busy ? null : () => _startup(null),
                      child: Text(error!, style: const TextStyle(fontSize: 12)),
                    ),
                  const Text(
                    'Ctrl + Alt + M  随时新建',
                    style: TextStyle(fontSize: 12, color: Colors.brown),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : widget.onReminder,
                    icon: const Icon(Icons.notifications_none, size: 18),
                    label: const Text('本张便利贴的提醒'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : _exit,
                    icon: const Icon(Icons.exit_to_app, size: 18),
                    label: const Text('保存并退出应用'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Offset dockSlideOffset(String edge) => switch (edge) {
  'left' => const Offset(-1, 0),
  'right' => const Offset(1, 0),
  'top' => const Offset(0, -1),
  _ => const Offset(0, 1),
};

bool canAutoHideNote({
  required bool docked,
  required bool collapsed,
  required bool hovered,
  required bool editing,
  required bool busy,
}) => docked && !collapsed && !hovered && !editing && !busy;
