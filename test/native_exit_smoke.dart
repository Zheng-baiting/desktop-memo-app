// Uses in-memory notes and the real shutdown path. The host process exits.
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
      for (var i = 0; i < 2; i++)
        {
          'id': 'exit-test-$i',
          'title': '退出测试',
          'body': '不得进入日志的测试正文',
          'x': 300 + i * 320,
          'y': 300,
          'createdAt': i,
        },
    ]),
  });
  await app.main(args);
  try {
    var ready = false;
    for (var i = 0; i < 100; i++) {
      if ((await WindowController.getAll()).length == 3) {
        ready = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!ready) throw StateError('Note windows did not start');
    await Future<void>.delayed(const Duration(seconds: 2));
    stdout.writeln(
      'NATIVE_EXIT_REQUEST: flushing two temporary notes through the real exit handler.',
    );
    await controller.invokeMethod('exit');
    // Normal shutdown destroys this engine before the watchdog completes.
    await Future<void>.delayed(const Duration(seconds: 10));
    throw StateError('Exit did not terminate the host within 10 seconds');
  } catch (error) {
    stderr.writeln('NATIVE_EXIT_FAIL: $error');
    exitCode = 1;
    await windowManager.destroy();
  }
}
