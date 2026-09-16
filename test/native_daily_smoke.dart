// In-memory notes: never reads or writes the user's real reminders.
import 'dart:convert';
import 'dart:io';

import 'package:desktop_memo/main.dart' as app;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final host = await WindowController.fromCurrentEngine();
  if (host.arguments.isNotEmpty) {
    await app.main(args);
    return;
  }
  final due = DateTime.now().subtract(const Duration(days: 2));
  SharedPreferences.setMockInitialValues({
    'notes.v1': jsonEncode([
      {
        'id': 'daily-test',
        'title': '每日提醒验证',
        'body': '测试用临时便利贴',
        'x': 650,
        'y': 250,
        'color': 0,
        'createdAt': 1,
        'daily': true,
        'reminder': due.toIso8601String(),
        'repeatUntil': DateTime.now()
            .add(const Duration(days: 2))
            .toIso8601String(),
      },
      {
        'id': 'sibling',
        'title': '保留测试',
        'body': '内容保持不变',
        'x': 950,
        'y': 250,
        'color': 1,
        'createdAt': 2,
      },
    ]),
  });
  await app.main(args);
  try {
    WindowController? note;
    for (var i = 0; i < 100; i++) {
      final all = await WindowController.getAll();
      final found = all.where((w) => w.arguments.contains('daily-test'));
      if (found.isNotEmpty) {
        note = found.first;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (note == null) throw StateError('No reminder window');
    await Future<void>.delayed(const Duration(seconds: 4));
    final state = await note.invokeMethod<Map>('flush');
    if (state?['alerting'] != true) {
      throw StateError('Startup catch-up did not pop up');
    }
    final snapshot = state?['note'] as Map;
    final next = DateTime.parse(snapshot['reminder'] as String);
    if (!next.isAfter(DateTime.now()) ||
        next.hour != due.hour ||
        next.minute != due.minute) {
      throw StateError('Next occurrence drifted or replayed missed days');
    }
    await host.invokeMethod('acknowledge', {'id': 'daily-test'});
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('notes.v1')!) as List;
    final daily = saved.singleWhere((n) => n['id'] == 'daily-test');
    if (daily['reminder'] != snapshot['reminder'] || daily['daily'] != true) {
      throw StateError('Acknowledgment removed recurrence');
    }
    if (saved.singleWhere((n) => n['id'] == 'sibling')['body'] != '内容保持不变') {
      throw StateError('Sibling changed');
    }
    await host.invokeMethod('cancel', {'id': 'daily-test'});
    final cancelled = (jsonDecode(prefs.getString('notes.v1')!) as List)
        .singleWhere((n) => n['id'] == 'daily-test');
    if (cancelled['reminder'] != null || cancelled['daily'] != false) {
      throw StateError('Cancellation failed');
    }
    stdout.writeln(
      'NATIVE_DAILY_PASS: startup catch-up pops up; fixed next time; acknowledgment preserves daily schedule; cancellation persists; sibling unchanged.',
    );
  } catch (error, stack) {
    stderr.writeln('NATIVE_DAILY_FAIL: $error\n$stack');
    exitCode = 1;
  } finally {
    await windowManager.destroy();
  }
}
