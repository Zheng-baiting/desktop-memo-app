import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_memo/exit_timing_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() {
    final root = Directory('build/test-artifacts')..createSync(recursive: true);
    directory = root.createTempSync('exit-log-');
    file = File('${directory.path}/exit-timing.jsonl');
  });
  tearDown(() => directory.deleteSync(recursive: true));
  List<Map<String, dynamic>> records() => file
      .readAsLinesSync()
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();

  test('records ordered stages and durations, never return values', () async {
    final log = ExitTimingLog(file: file);
    final result = await log.measure(ExitStage.shutdown, () async {
      return log.measure(
        ExitStage.saveNote,
        () async => 'private note body',
        noteIndex: 1,
      );
    });
    expect(result, 'private note body');
    expect(records().map((r) => '${r['stage']}:${r['event']}'), [
      'shutdown:start',
      'saveNote:start',
      'saveNote:done',
      'shutdown:done',
    ]);
    expect(records().map((r) => r['session']).toSet().length, 1);
    expect(records()[1]['note_index'], 1);
    expect(records().last['elapsed_ms'], greaterThanOrEqualTo(0));
    expect(file.readAsStringSync(), isNot(contains('private note body')));
  });

  test('records failure without private error messages and rethrows', () async {
    final failure = StateError('secret title and local path');
    await expectLater(
      ExitTimingLog(file: file)
          .measure<void>(ExitStage.saveAll, () async => throw failure),
      throwsA(same(failure)),
    );
    expect(records().last['event'], 'failed');
    expect(file.readAsStringSync(), isNot(contains('secret')));
  });

  test(
    'a blocked stage leaves waiting records and stops after completion',
    () async {
      final pending = Completer<void>();
      final result = ExitTimingLog(file: file)
          .measure(ExitStage.notifications, () => pending.future);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(records().last['event'], 'waiting');
      expect(records().last['elapsed_ms'], greaterThanOrEqualTo(1900));
      pending.complete();
      await result;
      expect(records().last['event'], 'done');
      final length = file.lengthSync();
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(file.lengthSync(), length);
    },
  );

  test(
    'unwritable log does not prevent the original action or error',
    () async {
      final blocked = File('${directory.path}/not-a-directory')
        ..writeAsStringSync('fixture');
      final log = ExitTimingLog(file: File('${blocked.path}/exit.jsonl'));
      expect(await log.measure(ExitStage.saveAll, () async => 42), 42);
      await expectLater(
        log.measure<void>(
          ExitStage.saveNote,
          () async => throw StateError('save failed'),
        ),
        throwsStateError,
      );
    },
  );

  test('rotation retains only current and previous bounded logs', () async {
    for (var i = 0; i < 2; i++) {
      file.writeAsStringSync('x' * ExitTimingLog.maxBytes);
      await ExitTimingLog(file: file).measure(ExitStage.tray, () async {});
      expect(
        File('${file.path}.previous').lengthSync(),
        ExitTimingLog.maxBytes,
      );
      expect(file.lengthSync(), lessThan(1024));
    }
    expect(directory.listSync().length, 2);
  });
}
