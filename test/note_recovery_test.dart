import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:desktop_memo/main.dart';
import 'package:desktop_memo/note_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UnwritableStorage extends NoteStorage {
  UnwritableStorage() : super(File('build/test-artifacts/not-written.json'));
  @override
  String? read(String? legacy) => legacy;
  @override
  Future<void> write(String raw) async =>
      throw StateError('test write failure');
}

class DelayedFailureStorage extends NoteStorage {
  DelayedFailureStorage()
    : super(File('build/test-artifacts/not-written.json'));
  final firstWrite = Completer<void>();
  int writes = 0;
  String? saved;
  @override
  String? read(String? legacy) => legacy;
  @override
  Future<void> write(String raw) async {
    if (writes++ == 0) await firstWrite.future;
    saved = raw;
  }
}

void main() {
  Future<SharedPreferences> mount(
    WidgetTester tester, {
    NoteStorage? storage,
  }) async {
    tester.view.physicalSize = const Size(1180, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'notes.v1': jsonEncode([
        {
          'id': 'recover-me',
          'title': '要保留的计划',
          'body': '不能丢失的正文',
          'x': 76,
          'y': 100,
          'createdAt': 1,
          'daily': true,
          'reminder': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
          'completedTasks': ['2026-10-14|学习'],
        },
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MemoApp(prefs, initializePlatform: false, storage: storage),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> delete(WidgetTester tester) async {
    await tester.tap(find.byTooltip('删除这张便利贴'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('confirm-permanent-delete')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'deletion requires confirmation and cancellation retains all data',
    (tester) async {
      final prefs = await mount(tester);
      final original = prefs.getString('notes.v1');
      await delete(tester);
      expect(find.text('彻底删除便利贴？'), findsOneWidget);
      expect(find.byType(MemoCard), findsOneWidget);
      expect(prefs.getString('notes.v1'), original);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(MemoCard), findsOneWidget);
      expect(prefs.getString('notes.v1'), original);
      await delete(tester);
      // Dismissing a confirmation is also cancellation.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('彻底删除便利贴？'), findsNothing);
      expect(prefs.getString('notes.v1'), original);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MemoApp(prefs, initializePlatform: false));
      await tester.pumpAndSettle();
      expect(find.byType(MemoCard), findsOneWidget);
      expect(prefs.getString('notes.v1'), original);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'confirmed deletion removes persisted data permanently across reload',
    (tester) async {
      final prefs = await mount(tester);
      await delete(tester);
      await confirm(tester);
      expect(find.byType(MemoCard), findsNothing);
      expect(jsonDecode(prefs.getString('notes.v1')!), isEmpty);
      expect(find.byTooltip('最近删除'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MemoApp(prefs, initializePlatform: false));
      await tester.pumpAndSettle();
      expect(find.byType(MemoCard), findsNothing);
      expect(jsonDecode(prefs.getString('notes.v1')!), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a failed deletion save leaves the original note editable', (
    tester,
  ) async {
    final prefs = await mount(tester, storage: UnwritableStorage());
    await delete(tester);
    await confirm(tester);
    expect(find.byType(MemoCard), findsOneWidget);
    expect(find.textContaining('操作未完成'), findsOneWidget);
    expect(
      (jsonDecode(prefs.getString('notes.v1')!) as List).single['deletedAt'],
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the note X only deletes after explicit confirmation', (
    tester,
  ) async {
    final n = Memo.fromJson({'id': 'hide-me', 'body': '保留正文'});
    var deleted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MemoCard(
              note: n,
              onChanged: () {},
              onDelete: (_) => deleted++,
              onReminder: (_) {},
              onNew: () {},
              onFront: (_) {},
              onToggleCollapsed: (_) {},
            ),
          ),
        ),
      ),
    );
    await delete(tester);
    expect(deleted, 0);
    expect(find.text('彻底删除便利贴？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    expect(n.body, '保留正文');
    await delete(tester);
    await confirm(tester);
    expect(deleted, 1);
    await tester.pumpWidget(const SizedBox());
    n.dispose();
  });

  testWidgets('confirmation fits a small desktop note and cancel is safe', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(286, 266);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final note = Memo.fromJson({'id': 'small', 'body': '保留'});
    var deletes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: memoTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 270,
              height: 250,
              child: MemoCard(
                note: note,
                onChanged: () {},
                onDelete: (_) => deletes++,
                onReminder: (_) {},
                onNew: () {},
                onFront: (_) {},
                onToggleCollapsed: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await delete(tester);
    final bounds = tester.getRect(find.byType(AlertDialog));
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(286));
    expect(bounds.bottom, lessThanOrEqualTo(266));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.pumpWidget(const SizedBox());
    note.dispose();
  });

  testWidgets('a queued edit cannot overwrite a failed deletion rollback', (
    tester,
  ) async {
    final storage = DelayedFailureStorage();
    await mount(tester, storage: storage);
    await delete(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-permanent-delete')));
    await tester.pumpAndSettle();
    expect(find.byType(MemoCard), findsNothing);
    // New-note saving is queued while deletion is still writing.
    await tester.tap(find.byTooltip('新建便利贴'));
    await tester.pumpAndSettle();
    storage.firstWrite.completeError(StateError('temporary write failure'));
    await tester.pumpAndSettle();
    final saved = jsonDecode(storage.saved!) as List;
    expect(saved.length, 2);
    expect(
      saved.singleWhere((n) => n['id'] == 'recover-me')['deletedAt'],
      isNull,
    );
    expect(find.byType(MemoCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'malformed note fields show a load error without replacing storage',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('memo-load-error-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final file = File('${folder.path}/notes.json');
      final raw = jsonEncode([
        {'id': 'valid', 'body': '必须保留'},
        {'id': 'bad', 'createdAt': 'invalid type'},
      ]);
      file.writeAsStringSync(raw);
      await mount(tester, storage: NoteStorage(file));
      expect(find.text('原有便利贴暂时无法读取'), findsOneWidget);
      expect(find.byType(MemoCard), findsNothing);
      expect(find.byTooltip('新建便利贴'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(file.readAsStringSync(), raw);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'old soft-deleted notes are visible again until confirmed deletion',
    (tester) async {
      final prefs = await mount(tester);
      final notes = jsonDecode(prefs.getString('notes.v1')!) as List;
      notes.single['deletedAt'] = '2026-10-14T09:00:00';
      await prefs.setString('notes.v1', jsonEncode(notes));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MemoApp(prefs, initializePlatform: false));
      await tester.pumpAndSettle();
      expect(find.byType(MemoCard), findsOneWidget);
      expect(
        tester.widget<MemoCard>(find.byType(MemoCard)).note.body,
        '不能丢失的正文',
      );
      await delete(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(MemoCard), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
