part of 'main.dart';

Future<void> closeDesktopNoteWindow() async {
  await windowManager.setPreventClose(false);
  // destroy() posts WM_QUIT on Windows; close() targets this window only.
  await windowManager.close();
}

// The manager is the only writer and reminder scheduler. Note windows only
// send field-level edits, so moving one note cannot overwrite another's text.
extension _DesktopHost on _MemoAppState {
  Future<void> _pruneClosedNoteWindows() async {
    final liveIds = (await WindowController.getAll())
        .map((window) => window.windowId)
        .toSet();
    noteWindows.removeWhere((_, window) => !liveIds.contains(window.windowId));
    readyNotes.removeWhere((id) => !noteWindows.containsKey(id));
  }

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
        if (call.method == 'manage') {
          await _showManager();
          return true;
        }
        if (call.method == 'language') {
          return _setLanguage(data['code'] as String?);
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
            readyNotes.add(note.id);
            hiddenNoteIds.remove(note.id);
            noteWindows[note.id] = WindowController.fromWindowId(
              data['window'] as String,
            );
            _refresh();
            return {...note.toJson(), 'language': language};
          case 'visibility':
            if (data['visible'] == true) {
              hiddenNoteIds.remove(note.id);
            } else if (data['visible'] == false) {
              hiddenNoteIds.add(note.id);
            } else {
              throw ArgumentError('便利贴显示状态无效');
            }
            _refresh();
            return true;
          case 'edit':
            // Task identity includes its date and text. A late click from the
            // previous day must never complete a different day's task.
            if (data['taskKey'] is String && data['taskDone'] is bool) {
              final key = data['taskKey'] as String;
              if (data['taskDone'] == true) {
                note.completedTasks.add(key);
              } else {
                note.completedTasks.remove(key);
              }
            }
            final currentDay =
                note.planDate == null || data['planDate'] == note.planDate;
            if (currentDay && data.containsKey('title')) {
              note.title = data['title'] as String;
              note.titleController.text = note.title;
            }
            if (currentDay && data.containsKey('body')) {
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
              note.snoozedUntil = null;
              note.reminder = DateTime.tryParse(
                data['reminder'] as String? ?? '',
              );
              note.persistent = data['persistent'] as bool;
              note.daily = data['daily'] as bool? ?? false;
              note.repeatUntil = DateTime.tryParse(
                data['repeatUntil'] as String? ?? '',
              );
              await _scheduleNotification(note);
              if (note.reminder == null) await speech.stop();
            }
            _refresh();
            await _save();
            return true;
          case 'delete':
            // Only the explicit confirmation dialog sends this flag. Closing,
            // hiding and stale callers cannot turn into a deletion request.
            if (data['confirmed'] != true) return false;
            await _delete(note);
            return true;
          case 'cancel':
            await _cancelReminder(note);
            await noteWindows[note.id]?.invokeMethod('dismissAlert');
            return true;
          case 'acknowledge':
            await _acknowledgeReminder(note);
            await noteWindows[note.id]?.invokeMethod('dismissAlert');
            return true;
          case 'snooze':
            final minutes = data['minutes'];
            if (minutes != 10 && minutes != 30) {
              throw ArgumentError('仅支持10分钟或30分钟后提醒');
            }
            await _snoozeReminder(note, Duration(minutes: minutes as int));
            await noteWindows[note.id]?.invokeMethod('dismissAlert');
            return true;
          case 'front':
            _front(note);
            return true;
        }
        return null;
      });
      if (notes.isEmpty) {
        await _showManager();
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
    if (exiting) return;
    try {
      final existing = noteWindows[note.id];
      if (existing != null) {
        await _pruneClosedNoteWindows();
        if (noteWindows.containsKey(note.id)) {
          await existing.invokeMethod('reveal');
          return;
        }
      }
      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode({
            'type': 'note',
            'parent': mainWindow!.windowId,
            'language': language,
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
    if (exiting) return;
    if (notes.isEmpty) {
      await _showManager();
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
        'snoozedUntil': note.snoozedUntil?.toIso8601String(),
        'persistent': note.persistent,
        'daily': note.daily,
        'repeatUntil': note.repeatUntil?.toIso8601String(),
        if (note.planDate != null) 'planDate': note.planDate,
        if (note.planDate != null) 'title': note.title,
        if (note.planDate != null) 'body': note.body,
      });
    } catch (_) {
      _notice('便利贴窗口同步失败，请重新打开应用。');
    }
  }

  Widget _windowManagerPage() => NoteManager(
    notes: notes,
    visibleIds: {
      for (final note in notes)
        if (readyNotes.contains(note.id) && !hiddenNoteIds.contains(note.id))
          note.id,
    },
    toolbar: _bar(),
    onOpen: _openNote,
    onNew: _newNote,
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
  bool reminderOpen = false;
  late String language = widget.arguments['language'] as String? ?? 'zh';
  String _tr(String zh, String en) => language == 'en' ? en : zh;
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
          case 'language':
            setState(
              () => language = (call.arguments as Map)['code'] as String,
            );
            return true;
          case 'hide':
            await _hide();
            return true;
          case 'dismissAlert':
            if (mounted) setState(() => alerting = false);
            _scheduleHide();
            return true;
          case 'flush':
            await _flush();
            return {
              'note': note.toJson(),
              'alerting': alerting,
              'language': language,
              'reminderOpen': reminderOpen,
            };
          case 'close':
            if (closing) return true;
            setState(() => closing = true);
            titleFocus.unfocus();
            bodyFocus.unfocus();
            try {
              // Deletion has already removed the note from the host. Only
              // application shutdown requests a final save before closing.
              if ((call.arguments as Map?)?['flush'] == true) await _flush();
              // Reply before destroying the engine that owns this channel.
              Timer(const Duration(milliseconds: 100), () async {
                try {
                  await closeDesktopNoteWindow();
                } catch (error) {
                  if (mounted) setState(() => closing = false);
                  _error(error);
                }
              });
              return true;
            } catch (_) {
              if (mounted) setState(() => closing = false);
              rethrow;
            }
          case 'reveal':
            if (settingsOpen) _closeSettings();
            if (note.collapsed) await _expand();
            await windowManager.show();
            await host.invokeMethod('visibility', {
              'id': note.id,
              'visible': true,
            });
            await windowManager.focus();
            return true;
          case 'reminderState':
            final data = call.arguments as Map;
            final planChanged =
                data['planDate'] != null && data['planDate'] != note.planDate;
            setState(() {
              if (planChanged) {
                note.planDate = data['planDate'] as String;
                note.title = data['title'] as String;
                note.body = data['body'] as String;
                note.titleController.text = note.title;
                note.bodyController.text = note.body;
                alerting = false;
              }
              note.reminder = DateTime.tryParse(
                data['reminder'] as String? ?? '',
              );
              note.snoozedUntil = DateTime.tryParse(
                data['snoozedUntil'] as String? ?? '',
              );
              note.persistent = data['persistent'] as bool;
              note.daily = data['daily'] as bool? ?? false;
              note.repeatUntil = DateTime.tryParse(
                data['repeatUntil'] as String? ?? '',
              );
            });
            if (planChanged) await windowManager.setTitle(note.title);
            return true;
          case 'alert':
            if (note.collapsed) await _expand();
            await windowManager.show();
            await host.invokeMethod('visibility', {
              'id': note.id,
              'visible': true,
            });
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
          final ready = await host.invokeMethod<Map>('ready', {
            'id': note.id,
            'window': widget.controller.windowId,
          });
          if (mounted && ready?['language'] is String) {
            setState(() => language = ready!['language'] as String);
          }
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
    await _send({
      'title': note.title,
      'body': note.body,
      if (note.planDate != null) 'planDate': note.planDate,
    });
    await windowManager.setTitle(
      note.title.isEmpty ? _tr('便利贴', 'Note') : note.title,
    );
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
    hideTimer?.cancel();
    try {
      await _flush();
      if (mounted) setState(() => reminderOpen = true);
    } catch (error) {
      editorOpen = false;
      _error(error);
      _scheduleHide();
    }
  }

  void _closeReminder() {
    if (!mounted) return;
    setState(() => reminderOpen = false);
    editorOpen = false;
    _scheduleHide();
  }

  @override
  void onWindowClose() async {
    if (closing) return;
    try {
      // An OS/taskbar close exits the application without deleting any note.
      // The host flushes every child before closing its engines.
      await host.invokeMethod('exit');
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _hide() async {
    if (closing) return;
    await _flush();
    await windowManager.hide();
    await host.invokeMethod('visibility', {'id': note.id, 'visible': false});
  }

  Future<bool> _confirmDelete() async {
    if (editorOpen || closing) return false;
    editorOpen = true;
    hideTimer?.cancel();
    try {
      return await confirmMemoDeletion(navigator.currentContext!);
    } finally {
      editorOpen = false;
      _scheduleHide();
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
    theme: memoTheme(language: language),
    locale: Locale(language),
    supportedLocales: memoLocales,
    localizationsDelegates: memoDelegates,
    builder: (context, child) => IgnorePointer(
      ignoring: closing,
      child: ExcludeFocus(excluding: closing, child: child!),
    ),
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
                        child: reminderOpen
                            ? ReminderEditor(
                                note: note,
                                onBack: _closeReminder,
                                onSave: (selection) async {
                                  await _send({
                                    'reminder': selection.when
                                        .toIso8601String(),
                                    'persistent': selection.mode == 'repeat',
                                    'daily': selection.mode == 'daily',
                                    'repeatUntil': selection.until
                                        ?.toIso8601String(),
                                  });
                                  if (mounted) {
                                    setState(() {
                                      note.reminder = selection.when;
                                      note.snoozedUntil = null;
                                      note.persistent =
                                          selection.mode == 'repeat';
                                      note.daily = selection.mode == 'daily';
                                      note.repeatUntil = selection.until;
                                    });
                                  }
                                  _closeReminder();
                                },
                                onCancel: () async {
                                  await host.invokeMethod('cancel', {
                                    'id': note.id,
                                  });
                                  _closeReminder();
                                },
                              )
                            : settingsOpen
                            ? NoteSettingsPanel(
                                language: language,
                                onLanguage: (code) async {
                                  await host.invokeMethod('language', {
                                    'code': code,
                                  });
                                },
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
                                onManage: () async {
                                  try {
                                    await _flush();
                                    await host.invokeMethod('manage');
                                  } catch (error) {
                                    _error(error);
                                  }
                                },
                                onReminder: () {
                                  _closeSettings();
                                  _remind();
                                },
                                onExit: () async {
                                  final timing = ExitTimingLog();
                                  await timing.measure(
                                    ExitStage.noteRequest,
                                    () async {
                                      await timing.measure(
                                        ExitStage.saveCurrentNote,
                                        _flush,
                                      );
                                      await timing.measure(
                                        ExitStage.sendExitRequest,
                                        () => host.invokeMethod('exit'),
                                      );
                                    },
                                  );
                                },
                              )
                            : MemoCard(
                                note: note,
                                collapsedOverride: visualCollapsed,
                                titleFocusNode: titleFocus,
                                bodyFocusNode: bodyFocus,
                                onChanged: _changed,
                                onTaskChanged: (key, done) {
                                  _send({'taskKey': key, 'taskDone': done})
                                      .catchError((Object error) {
                                        _error(error);
                                      });
                                },
                                onDelete: (_) async {
                                  await _flush();
                                  await host.invokeMethod('delete', {
                                    'id': note.id,
                                    'confirmed': true,
                                  });
                                },
                                onReminder: (_) => _remind(),
                                onConfirmDelete: _confirmDelete,
                                onClose: _hide,
                                onActionMenuChanged: (open) {
                                  editorOpen = open;
                                  if (open) {
                                    hideTimer?.cancel();
                                  } else {
                                    _scheduleHide();
                                  }
                                },
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
                            color: memoAccent,
                            borderRadius: BorderRadius.circular(12),
                            child: ReminderActions(
                              daily: note.daily,
                              onAction: (minutes) async {
                                await host.invokeMethod(
                                  minutes == null ? 'acknowledge' : 'snooze',
                                  {'id': note.id, 'minutes': ?minutes},
                                );
                                if (mounted) setState(() => alerting = false);
                                _scheduleHide();
                              },
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
    this.onManage,
    this.language = 'zh',
    this.onLanguage,
  });

  final Color color;
  final Future<bool> Function(bool? enabled) onStartup;
  final VoidCallback onBack;
  final VoidCallback onReminder;
  final Future<void> Function() onExit;
  final VoidCallback? onManage;
  final String language;
  final Future<void> Function(String)? onLanguage;

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
      if (mounted) {
        setState(
          () => error = uiText(
            context,
            '自启动设置失败，点击重试',
            'Startup setting failed. Retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _exit() async {
    setState(() => busy = true);
    try {
      await widget.onExit();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = uiText(
            context,
            '保存未完成，请稍后重试退出',
            'Could not save. Please retry before exiting.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _language(String? code) async {
    if (code == null) return;
    setState(() => busy = true);
    try {
      await widget.onLanguage!(code);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = uiText(
            context,
            '语言设置失败，请重试',
            'Could not save language. Try again.',
          ),
        );
      }
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
                  tooltip: uiText(context, '返回便利贴', 'Back to note'),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : widget.onBack,
                  icon: const Icon(Icons.arrow_back, size: 20),
                ),
                Text(
                  uiText(context, '便利贴设置', 'Note settings'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
              child: TextButtonTheme(
                data: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (widget.onLanguage != null)
                      SizedBox(
                        height: 36,
                        child: Row(
                          children: [
                            Text(
                              uiText(context, '语言', 'Language'),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const Spacer(),
                            DropdownButton<String>(
                              key: const ValueKey('language-choice'),
                              value: widget.language,
                              isDense: true,
                              borderRadius: BorderRadius.circular(14),
                              dropdownColor: memoPaper,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(
                                  value: 'zh',
                                  child: Text('中文'),
                                ),
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text('English'),
                                ),
                              ],
                              onChanged: busy ? null : _language,
                            ),
                          ],
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(uiText(context, '开机自启动', 'Start on login')),
                      value: autoStart ?? false,
                      onChanged: busy || autoStart == null ? null : _startup,
                    ),
                    if (error != null)
                      TextButton(
                        onPressed: busy ? null : () => _startup(null),
                        child: Text(
                          error!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: busy ? null : widget.onReminder,
                      icon: const Icon(Icons.notifications_none, size: 18),
                      label: Text(
                        uiText(context, '本张便利贴的提醒', 'Reminder for this note'),
                      ),
                    ),
                    if (widget.onManage != null)
                      TextButton.icon(
                        onPressed: busy ? null : widget.onManage,
                        icon: const Icon(Icons.notes, size: 18),
                        label: Text(uiText(context, '全部便利贴', 'All notes')),
                      ),
                    TextButton.icon(
                      onPressed: busy ? null : _exit,
                      icon: const Icon(Icons.exit_to_app, size: 18),
                      label: Text(
                        uiText(context, '保存并退出应用', 'Save and exit app'),
                      ),
                    ),
                  ],
                ),
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
