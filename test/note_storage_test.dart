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
}
