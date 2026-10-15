// In-memory notes only. Checks a pending child edit when exiting through the
// actual taskbar close callback or the production tray callback.
import 'dart:convert';
import 'dart:io';

import 'package:desktop_memo/main.dart' as app;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

const pendingBody = '退出前最后输入的内容，必须由退出流程收齐保存';

Iterable<Element> elements(Element root) sync* {
  yield root;
  final children = <Element>[];
  root.visitChildren(children.add);
  for (final child in children) {
    yield* elements(child);
  }
}

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('Timed out waiting for the native exit fixture');
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await WindowController.fromCurrentEngine();
  final mode = Platform.environment['MEMO_EXIT_MODE'] ?? 'taskbar';
  if (!['taskbar', 'tray', 'child-close', 'save-close'].contains(mode)) {
    throw ArgumentError.value(mode, 'MEMO_EXIT_MODE');
  }
  final startSignal = File('native-save-exit-start.signal');
  final pendingSignal = File('native-save-exit-pending.signal');
  final hiddenSignal = File('native-save-exit-hidden.signal');
  if (controller.arguments.isNotEmpty) {
    final arguments = jsonDecode(controller.arguments) as Map;
    await app.runMemo(args, memoryOnly: true);
    if ((arguments['note'] as Map)['id'] != 'save-exit-0') return;
    await waitFor(startSignal.existsSync);
    final fields = elements(WidgetsBinding.instance.rootElement!)
        .map((element) => element.widget)
        .whereType<TextField>();
    final body = fields.singleWhere(
      (field) => field.key == const ValueKey('body-save-exit-0'),
    );
    body.controller!.text = pendingBody;
    body.onChanged!(pendingBody); // Arms the normal 150 ms edit debounce.
    pendingSignal.writeAsStringSync('pending', flush: true);
    if (mode == 'child-close') await windowManager.close();
    if (mode == 'save-close') {
      final menu = elements(WidgetsBinding.instance.rootElement!)
          .map((element) => element.widget)
          .whereType<PopupMenuButton<String>>()
          .single;
      menu.onSelected!('save-close');
      for (var i = 0; i < 200; i++) {
        if (!await windowManager.isVisible()) {
          hiddenSignal.writeAsStringSync('hidden', flush: true);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      throw StateError('Saving one note did not hide its window');
    }
    return;
  }

  // These two files are owned by this fixture in its isolated build directory.
  for (final signal in [startSignal, pendingSignal, hiddenSignal]) {
    if (signal.existsSync()) signal.deleteSync();
  }
  SharedPreferences.setMockInitialValues({
    'notes.v1': jsonEncode([
      for (var i = 0; i < 2; i++)
        {
          'id': 'save-exit-$i',
          'title': '保留的便签 $i',
          'body': '原始正文 $i',
          'x': 300 + i * 320,
          'y': 280,
          'createdAt': i,
          'completedTasks': ['date|completed-$i'],
        },
    ]),
  });
  await app.runMemo(args, memoryOnly: true);
  try {
    var ready = false;
    for (var i = 0; i < 100; i++) {
      final windows = (await WindowController.getAll())
          .where((window) => window.windowId != controller.windowId)
          .toList();
      if (windows.length == 2) {
        try {
          for (final window in windows) {
            await window.invokeMethod('flush');
          }
          ready = true;
          break;
        } catch (_) {} // A created engine can precede its channel registration.
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!ready) throw StateError('Both note windows did not become ready');
    startSignal.writeAsStringSync('ready', flush: true);
    await waitFor(pendingSignal.existsSync);
    stdout.writeln('NATIVE_EXIT_REQUEST: $mode with an unflushed child edit.');
    if (mode == 'taskbar') {
      await windowManager.close();
    } else if (mode == 'tray') {
      final host = elements(WidgetsBinding.instance.rootElement!)
          .whereType<StatefulElement>()
          .singleWhere((element) => element.widget is app.MemoApp);
      (host.state as tray.TrayListener).onTrayMenuItemClick(
        tray.MenuItem(key: 'exit', label: '保存并退出'),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    String? saved;
    await waitFor(() {
      final raw = prefs.getString('notes.v1')!;
      final notes = jsonDecode(raw) as List;
      if (notes.length != 2) throw StateError('Exit deleted an existing note');
      final edited = notes.singleWhere((n) => n['id'] == 'save-exit-0') as Map;
      final sibling = notes.singleWhere((n) => n['id'] == 'save-exit-1') as Map;
      if (edited['body'] != pendingBody) return false;
      if (sibling['body'] != '原始正文 1' ||
          (edited['completedTasks'] as List).single != 'date|completed-0' ||
          (sibling['completedTasks'] as List).single != 'date|completed-1') {
        throw StateError('Exit changed sibling text or task completion');
      }
      saved = raw;
      return true;
    });
    File('native-save-exit-$mode.json').writeAsStringSync(saved!, flush: true);
    if (mode == 'save-close') {
      await waitFor(hiddenSignal.existsSync);
      final windows = await WindowController.getAll();
      if (windows.length != 3) {
        throw StateError('Closing one note exited another engine');
      }
      final sibling = windows.singleWhere(
        (window) => window.arguments.contains('save-exit-1'),
      );
      final snapshot = await sibling.invokeMethod<Map>('flush');
      if (snapshot?['note']['body'] != '原始正文 1') {
        throw StateError('The sibling note did not remain responsive');
      }
      await controller.invokeMethod('manage');
      app.NoteManager manager() =>
          elements(WidgetsBinding.instance.rootElement!)
              .map((element) => element.widget)
              .whereType<app.NoteManager>()
              .single;
      await waitFor(
        () =>
            !manager().visibleIds.contains('save-exit-0') &&
            manager().visibleIds.contains('save-exit-1'),
      );
      manager().onOpen(
        manager().notes.singleWhere((note) => note.id == 'save-exit-0'),
      );
      await waitFor(() => manager().visibleIds.length == 2);
      if ((await WindowController.getAll()).length != 3) {
        throw StateError('Reopening a retained note created duplicate windows');
      }
    }
    stdout.writeln(
      'NATIVE_SAVE_EXIT_PASS: $mode saved both IDs, the pending '
      'child edit and task completion without deleting any note.',
    );
    if (mode == 'save-close') await controller.invokeMethod('exit');
    await Future<void>.delayed(const Duration(seconds: 10));
    throw StateError('Save completed but the application did not exit');
  } catch (error, stack) {
    stderr.writeln('NATIVE_SAVE_EXIT_FAIL: $error\n$stack');
    exitCode = 1;
    await controller.invokeMethod('exit');
  }
}
