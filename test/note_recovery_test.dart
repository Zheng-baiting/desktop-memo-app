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
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移到最近删除'));
    await tester.pumpAndSettle();
  }

  testWidgets('deletion survives reload and restoration preserves note data', (
    tester,
  ) async {
    final prefs = await mount(tester);
    await delete(tester);
    expect(find.byType(MemoCard), findsNothing);
    final deleted = (jsonDecode(prefs.getString('notes.v1')!) as List).single;
    expect(deleted['deletedAt'], isNotNull);
    expect(deleted['body'], '不能丢失的正文');
    expect(deleted['daily'], isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MemoApp(prefs, initializePlatform: false));
    await tester.pumpAndSettle();
    expect(find.byType(MemoCard), findsNothing);
    await tester.tap(find.byTooltip('最近删除'));
    await tester.pumpAndSettle();
    expect(find.text('要保留的计划'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('没有最近删除的便利贴'), findsOneWidget);
    final restored = (jsonDecode(prefs.getString('notes.v1')!) as List).single;
    expect(restored.containsKey('deletedAt'), isFalse);
    expect(restored['body'], '不能丢失的正文');
    expect(restored['completedTasks'], ['2026-10-14|学习']);
    expect(restored['daily'], isTrue);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(MemoCard), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed deletion save leaves the original note editable', (
    tester,
  ) async {
    final prefs = await mount(tester, storage: UnwritableStorage());
    await delete(tester);
    expect(find.byType(MemoCard), findsOneWidget);
    expect(find.textContaining('操作未完成'), findsOneWidget);
    expect(
      (jsonDecode(prefs.getString('notes.v1')!) as List).single['deletedAt'],
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the close button hides a note without invoking deletion', (
    tester,
  ) async {
    final n = Memo.fromJson({'id': 'hide-me', 'body': '保留正文'});
    var hidden = 0;
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
              onClose: () => hidden++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('收起便利贴'));
    expect(hidden, 1);
    expect(deleted, 0);
    expect(n.deletedAt, isNull);
    expect(n.body, '保留正文');
    await tester.pumpWidget(const SizedBox());
    n.dispose();
  });

  testWidgets('a queued edit cannot overwrite a failed deletion rollback', (
    tester,
  ) async {
    final storage = DelayedFailureStorage();
    await mount(tester, storage: storage);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移到最近删除'));
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
}
