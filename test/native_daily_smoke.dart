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
    await app.runMemo(args, memoryOnly: true);
    return;
  }
  final due = DateTime.now().subtract(const Duration(days: 2));
  final today = app.Memo.dateKey(DateTime.now());
  final tomorrow = app.Memo.dateKey(
    DateTime.now().add(const Duration(days: 1)),
  );
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
        'z': 2,
        'planDate': app.Memo.dateKey(due),
        'dailyPlan': {
          for (var i = 2; i < 181; i++)
            app.Memo.dateKey(
              DateTime.now().add(Duration(days: i)),
            ): List.filled(
              12,
              '09:00–10:00 大容量学习日历启动验证：英语、网络与Python练习',
            ).join('\n'),
          today: '22:00–22:35 今日英语',
          tomorrow: '22:00–22:35 明日英语',
        },
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
        'z': 1,
        'collapsed': true,
      },
    ]),
  });
  await app.runMemo(args, memoryOnly: true);
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
    if (snapshot['title'] != today || snapshot['body'] != '22:00–22:35 今日英语') {
      throw StateError('Startup did not select the current dated plan');
    }
    final next = DateTime.parse(snapshot['reminder'] as String);
    if (!next.isAfter(DateTime.now()) ||
        next.hour != due.hour ||
        next.minute != due.minute) {
      throw StateError('Next occurrence drifted or replayed missed days');
    }
    await host.invokeMethod('acknowledge', {'id': 'daily-test'});
    final prefs = await SharedPreferences.getInstance();
    final taskKey = '$today|22:00–22:35 今日英语';
    await host.invokeMethod('edit', {
      'id': 'daily-test',
      'taskKey': taskKey,
      'taskDone': true,
    });
    var checked = (jsonDecode(prefs.getString('notes.v1')!) as List)
        .singleWhere((n) => n['id'] == 'daily-test');
    if (!(checked['completedTasks'] as List).contains(taskKey)) {
      throw StateError('Task completion was not saved by the host');
    }
    // A body flush from the window must not overwrite saved checkbox state.
    await note.invokeMethod('flush');
    checked = (jsonDecode(prefs.getString('notes.v1')!) as List).singleWhere(
      (n) => n['id'] == 'daily-test',
    );
    final restored = app.Memo.fromJson(Map<String, dynamic>.from(checked));
    restored.updateDailyPlan(DateTime.now().add(const Duration(days: 1)));
    if (!restored.completedTasks.contains(taskKey) ||
        restored.completedTasks.contains(
          restored.taskKey('22:00–22:35 明日英语'),
        )) {
      throw StateError('Task persistence or day isolation failed');
    }
    restored.dispose();
    await host.invokeMethod('edit', {
      'id': 'daily-test',
      'taskKey': taskKey,
      'taskDone': false,
    });
    final undone = (jsonDecode(prefs.getString('notes.v1')!) as List)
        .singleWhere((n) => n['id'] == 'daily-test');
    if ((undone['completedTasks'] as List? ?? []).isNotEmpty) {
      throw StateError('Task undo failed');
    }
    final saved = jsonDecode(prefs.getString('notes.v1')!) as List;
    final daily = saved.singleWhere((n) => n['id'] == 'daily-test');
    if (daily['reminder'] != snapshot['reminder'] || daily['daily'] != true) {
      throw StateError('Acknowledgment removed recurrence');
    }
    if (saved.singleWhere((n) => n['id'] == 'sibling')['body'] != '内容保持不变') {
      throw StateError('Sibling changed');
    }
    await note.invokeMethod('reminderState', {
      'reminder': snapshot['reminder'],
      'persistent': false,
      'daily': true,
      'repeatUntil': snapshot['repeatUntil'],
      'planDate': tomorrow,
      'title': tomorrow,
      'body': '22:00–22:35 明日英语',
    });
    final rolled = await note.invokeMethod<Map>('flush');
    if ((rolled?['note'] as Map)['title'] != tomorrow ||
        (rolled?['note'] as Map)['body'] != '22:00–22:35 明日英语') {
      throw StateError('Window did not update dated title and body');
    }
    final protected = (jsonDecode(prefs.getString('notes.v1')!) as List)
        .singleWhere((n) => n['id'] == 'daily-test');
    if (protected['planDate'] != today || protected['title'] != today) {
      throw StateError('Out-of-date child edit overwrote the host plan');
    }
    await host.invokeMethod('cancel', {'id': 'daily-test'});
    final cancelled = (jsonDecode(prefs.getString('notes.v1')!) as List)
        .singleWhere((n) => n['id'] == 'daily-test');
    if (cancelled['reminder'] != null || cancelled['daily'] != false) {
      throw StateError('Cancellation failed');
    }
    stdout.writeln(
      'NATIVE_DAILY_PASS: checklist persistence, undo and day isolation; dated plan rollover; stale edits rejected; catch-up popup; fixed next time; acknowledgment preserves recurrence; cancellation and sibling verified.',
    );
  } catch (error, stack) {
    stderr.writeln('NATIVE_DAILY_FAIL: $error\n$stack');
    exitCode = 1;
  } finally {
    await windowManager.destroy();
  }
}
