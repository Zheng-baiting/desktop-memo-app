// Run with: flutter run -d windows --release -t test/native_smoke.dart
// Mock preferences isolate this check from the user's real notes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_memo/main.dart' as app;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await WindowController.fromCurrentEngine();
  if (controller.arguments.isNotEmpty) {
    await app.main(args);
    return;
  }
  SharedPreferences.setMockInitialValues({
    'notes.v1': jsonEncode([
      for (final id in ['native-check-a', 'native-check-b'])
        {
          'id': id,
          'title': id,
          'body': '独立窗口回归测试',
          'x': id.endsWith('a') ? 300 : 650,
          'y': 200,
          'color': 0,
          'collapsed': id.endsWith('a'),
          'dock': 'left',
          'createdAt': 1,
        },
    ]),
  });
  await app.main(args);
  Future<void> waitFor(bool Function(List<WindowController>) condition) async {
    for (var i = 0; i < 100; i++) {
      if (condition(await WindowController.getAll())) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Timed out waiting for native windows');
  }

  try {
    await waitFor((windows) => windows.length == 3);
    await Future<void>.delayed(const Duration(seconds: 2));
    final windows = await WindowController.getAll();
    final survivor = windows.singleWhere(
      (w) => w.arguments.contains('native-check-b'),
    );
    final deleted = windows.singleWhere(
      (w) => w.arguments.contains('native-check-a'),
    );
    await deleted.invokeMethod('reveal');
    final expanded = await deleted.invokeMethod<Map>('flush');
    if ((expanded?['note'] as Map?)?['collapsed'] != false) {
      throw StateError('Docked note failed to expand');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    final tucked = await deleted.invokeMethod<Map>('flush');
    if ((tucked?['note'] as Map?)?['collapsed'] != true) {
      throw StateError('Idle docked note failed to auto-hide');
    }
    await survivor.invokeMethod('flush');
    await controller.invokeMethod('delete', {'id': 'native-check-a'});
    await waitFor(
      (windows) => !windows.any((w) => w.windowId == deleted.windowId),
    );
    await survivor.invokeMethod('reveal');
    await survivor.invokeMethod('flush');
    await controller.invokeMethod('edit', {
      'id': 'native-check-b',
      'reminder': DateTime.now()
          .add(const Duration(seconds: 3))
          .toIso8601String(),
      'persistent': false,
    });
    await Future<void>.delayed(const Duration(seconds: 5));
    final alertState = await survivor.invokeMethod<Map>('flush');
    if (alertState?['alerting'] != true) {
      throw StateError(
        'Due reminder did not reach the independent note window',
      );
    }
    await controller.invokeMethod('cancel', {'id': 'native-check-b'});
    final prefs = await SharedPreferences.getInstance();
    final notes = jsonDecode(prefs.getString('notes.v1')!) as List;
    if (notes.length != 1 ||
        notes.single['id'] != 'native-check-b' ||
        notes.single['body'] != '独立窗口回归测试') {
      throw StateError('Deleting a note affected its sibling');
    }
    stdout.writeln(
      'NATIVE_SMOKE_PASS: dock expands and auto-hides; delete A; B responds and saves; manager alive; sibling data intact; due reminder reaches B.',
    );
  } catch (error, stack) {
    stderr.writeln('NATIVE_SMOKE_FAIL: $error\n$stack');
    exitCode = 1;
  } finally {
    await windowManager.destroy();
  }
}
