import 'dart:convert';
import 'dart:io';

import 'package:desktop_memo/note_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'different launcher preferences share notes and completion on disk',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'memo-storage-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final store = NoteStorage(File('${folder.path}/notes.json'));
      final plan = [
        {
          'id': 'plan',
          'title': '2026-09-20',
          'completedTasks': ['day|task'],
        },
      ];
      await store.write(jsonEncode(plan));
      final scheduled = NoteStorage(store.file);
      expect(jsonDecode(scheduled.read('[]')!), plan);
      final manuallyLaunched = NoteStorage(store.file);
      expect(jsonDecode(manuallyLaunched.read('[{"id":"old"}]')!), plan);
      plan[0]['completedTasks'] = ['day|task', 'day|task2'];
      await scheduled.write(jsonEncode(plan));
      expect(jsonDecode(manuallyLaunched.read('[]')!), plan);
      expect(File('${store.file.path}.tmp').existsSync(), isFalse);
    },
  );
  test(
    'invalid shared data is not silently replaced with an empty list',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'memo-storage-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/notes.json')
        ..writeAsStringSync('{broken');
      final store = NoteStorage(file);
      expect(() => store.read('[]'), throwsFormatException);
      expect(file.readAsStringSync(), '{broken');
    },
  );
  test(
    'stale instances cannot replace newer notes or resurrect a deletion',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'memo-conflict-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final first = NoteStorage(File('${folder.path}/notes.json'));
      await first.write('[{"id":"kept"},{"id":"delete"}]');
      final stale = NoteStorage(first.file);
      stale.read(null);
      await first.write('[{"id":"kept"}]');
      await expectLater(stale.write('[{"id":"delete"}]'), throwsStateError);
      expect(jsonDecode(first.file.readAsStringSync()), [
        {'id': 'kept'},
      ]);
      expect(stale.read(null), '[{"id":"kept"}]');
      await stale.write('[]');
      await expectLater(first.write('[{"id":"kept"}]'), throwsStateError);
      expect(first.file.readAsStringSync(), '[]');
    },
  );

  test(
    'existing storage must be read before a writer can replace it',
    () async {
      final folder = await Directory.systemTemp.createTemp('memo-unread-test-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/notes.json')
        ..writeAsStringSync('[{"id":"old"}]');
      final store = NoteStorage(file);
      await expectLater(store.write('[]'), throwsStateError);
      expect(file.readAsStringSync(), '[{"id":"old"}]');
      expect(store.read('[]'), '[{"id":"old"}]');
      await store.write('[]');
      expect(store.read('[{"id":"legacy"}]'), '[]');
    },
  );

  test('invalid writes cannot replace the last valid document', () async {
    final folder = await Directory.systemTemp.createTemp(
      'memo-invalid-write-test-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final store = NoteStorage(File('${folder.path}/notes.json'));
    await store.write('[{"id":"retained"}]');
    await expectLater(store.write('{broken'), throwsFormatException);
    expect(store.file.readAsStringSync(), '[{"id":"retained"}]');
  });
}
