// Uses mock preferences and real window channels, without reading user notes.
// Run with: flutter run -d windows --release -t test/native_upgrade_smoke.dart
import 'dart:convert';
import 'dart:io';

import 'package:desktop_memo/main.dart' as app;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final host = await WindowController.fromCurrentEngine();
  if (host.arguments.isNotEmpty) {
    await app.runMemo(args, memoryOnly: true);
    return;
  }

  const noteId = 'upgrade-daily';
  const siblingId = 'upgrade-sibling';
  const body = '原生升级测试：正文与每日提醒设置必须保留';
  final due = DateTime.now().subtract(const Duration(seconds: 2));
  final until = DateTime(due.year, due.month, due.day + 3);
  SharedPreferences.setMockInitialValues({
    'notes.v1': jsonEncode([
      {
        'id': noteId,
        'title': '升级回归测试',
        'body': body,
        'x': 300,
        'y': 220,
        'createdAt': 1,
        'daily': true,
        'persistent': false,
        'reminder': due.toIso8601String(),
        'repeatUntil': until.toIso8601String(),
      },
      {
        'id': siblingId,
        'title': '保留的同级便签',
        'body': '升级测试中不得改变这张便签',
        'x': 650,
        'y': 220,
        'createdAt': 2,
      },
    ]),
  });
  await app.runMemo(args, memoryOnly: true);

  final elapsed = Stopwatch()..start();
  Duration remaining() {
    final remaining = const Duration(seconds: 25) - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw StateError('Native upgrade checks exceeded 25 seconds');
    }
    return remaining;
  }

  Future<T> bounded<T>(Future<T> action) => action.timeout(remaining());

  Future<void> waitFor(
    Future<bool> Function() condition,
    String failure,
  ) async {
    while (elapsed.elapsed < const Duration(seconds: 25)) {
      if (await bounded(condition())) return;
      final delay = remaining();
      await Future<void>.delayed(
        delay < const Duration(milliseconds: 100)
            ? delay
            : const Duration(milliseconds: 100),
      );
    }
    throw StateError(failure);
  }

  bool belongsTo(WindowController window, String id) {
    if (window.arguments.isEmpty) return false;
    final arguments = jsonDecode(window.arguments) as Map;
    return (arguments['note'] as Map?)?['id'] == id;
  }

  Future<Map> readNote(WindowController window) async {
    final result = await bounded(window.invokeMethod<Map>('flush'));
    if (result == null) {
      throw StateError('Child did not return a note snapshot');
    }
    return result;
  }

  try {
    WindowController? note;
    WindowController? sibling;
    await waitFor(() async {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (belongsTo(window, noteId)) note = window;
        if (belongsTo(window, siblingId)) sibling = window;
      }
      return note != null && sibling != null;
    }, 'Both temporary note windows did not start');

    Map? first;
    await waitFor(() async {
      try {
        final snapshot = await readNote(note!);
        final saved = snapshot['note'] as Map;
        final next = DateTime.tryParse(saved['reminder'] as String? ?? '');
        if (snapshot['alerting'] != true ||
            next == null ||
            !next.isAfter(DateTime.now())) {
          return false;
        }
        first = saved;
        return true;
      } on MissingPluginException {
        return false; // The engine exists before its window handler is ready.
      } on PlatformException {
        return false;
      } on WindowChannelException catch (error) {
        if (error.code != 'CHANNEL_UNREGISTERED') rethrow;
        return false;
      }
    }, 'The overdue daily reminder did not reach its ready child');
    final fixedReminder = first!['reminder'] as String;
    final nextDay = DateTime.parse(fixedReminder);
    if (nextDay.hour != due.hour ||
        nextDay.minute != due.minute ||
        nextDay.second != due.second ||
        first!['daily'] != true) {
      throw StateError('Daily occurrence changed the chosen local clock time');
    }

    for (final minutes in [10, 30]) {
      final earliest = DateTime.now().add(Duration(minutes: minutes));
      await bounded(
        host.invokeMethod('snooze', {'id': noteId, 'minutes': minutes}),
      );
      await waitFor(() async {
        final snapshot = await readNote(note!);
        final saved = snapshot['note'] as Map;
        final snoozed = DateTime.tryParse(
          saved['snoozedUntil'] as String? ?? '',
        );
        return snoozed != null &&
            !snoozed.isBefore(earliest) &&
            !snoozed.isAfter(DateTime.now().add(Duration(minutes: minutes))) &&
            saved['reminder'] == fixedReminder &&
            saved['daily'] == true &&
            snapshot['alerting'] == false;
      }, '$minutes-minute snooze did not synchronize or shifted recurrence');
    }

    await bounded(host.invokeMethod('acknowledge', {'id': noteId}));
    await waitFor(() async {
      final snapshot = await readNote(note!);
      final saved = snapshot['note'] as Map;
      return saved['snoozedUntil'] == null &&
          saved['reminder'] == fixedReminder &&
          saved['daily'] == true &&
          snapshot['alerting'] == false;
    }, 'Daily acknowledgment cleared recurrence or retained its snooze');

    final prefs = await SharedPreferences.getInstance();
    Map stored(String id) =>
        (jsonDecode(prefs.getString('notes.v1')!) as List).singleWhere(
          (item) => item['id'] == id,
        ) as Map;

    await bounded(note!.invokeMethod('hide'));
    if (stored(noteId)['deletedAt'] != null || stored(noteId)['body'] != body) {
      throw StateError('Hiding a note deleted or modified its content');
    }
    final hiddenWindows = await bounded(WindowController.getAll());
    if (!hiddenWindows.any((window) => window.windowId == note!.windowId)) {
      throw StateError('Hiding destroyed the note window');
    }
    await bounded(note!.invokeMethod('reveal'));
    if ((await readNote(note!))['note']['body'] != body) {
      throw StateError('The hidden note could not be reopened with its body');
    }

    final deletedWindowId = note!.windowId;
    final rejected = await bounded(host.invokeMethod('delete', {'id': noteId}));
    if (rejected != false || stored(noteId)['body'] != body) {
      throw StateError('An unconfirmed request deleted a note');
    }
    await bounded(
      host.invokeMethod('delete', {'id': noteId, 'confirmed': true}),
    );
    bool remains() => (jsonDecode(prefs.getString('notes.v1')!) as List).any(
      (item) => item['id'] == noteId,
    );
    if (remains()) {
      throw StateError('Confirmed deletion retained a persisted record');
    }
    await waitFor(() async {
      final windows = await WindowController.getAll();
      return !windows.any((window) => window.windowId == deletedWindowId) &&
          windows.any((window) => window.windowId == sibling!.windowId);
    }, 'Deleting one note closed its sibling or left the deleted child alive');
    final siblingSnapshot = (await readNote(sibling!))['note'] as Map;
    if (siblingSnapshot['body'] != '升级测试中不得改变这张便签' ||
        stored(siblingId)['body'] != siblingSnapshot['body'] ||
        remains()) {
      throw StateError(
        'Deletion changed its sibling or a later save revived it',
      );
    }
    stdout.writeln(
      'NATIVE_UPGRADE_PASS: daily alert; 10/30-minute snooze without clock drift; '
      'acknowledgment preserves recurrence; hide/reveal keeps content; '
      'unconfirmed delete rejected; confirmed delete removes persisted record; '
      'sibling save cannot revive it; sibling remains responsive.',
    );
  } catch (error, stack) {
    stderr.writeln('NATIVE_UPGRADE_FAIL: $error\n$stack');
    exitCode = 1;
  } finally {
    await host.invokeMethod('exit');
  }
}
