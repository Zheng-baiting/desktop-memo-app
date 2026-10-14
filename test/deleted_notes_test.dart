import 'dart:async';

import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Memo deletedNote(String id) => Memo(
  id: id,
  title: '准备考试',
  body: '复习第三章，整理错题。',
  x: 0,
  y: 0,
  color: 0,
  createdAt: 0,
  deletedAt: DateTime(2026, 10, 14, 10, 30),
);

Future<void> showDeletedNotes(
  WidgetTester tester,
  List<Memo> notes,
  Future<void> Function(Memo) onRestore,
) => tester.pumpWidget(
  MaterialApp(
    theme: memoTheme(),
    home: DeletedNotesPage(notes: notes, onRestore: onRestore),
  ),
);

void main() {
  testWidgets('successful restore refreshes the shared list', (tester) async {
    final note = deletedNote('success');
    final notes = [note];
    Memo? restored;
    await showDeletedNotes(tester, notes, (item) async {
      restored = item;
      notes.remove(item);
    });

    expect(find.text('准备考试'), findsOneWidget);
    expect(find.text('复习第三章，整理错题。'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(restored, same(note));
    expect(notes, isEmpty);
    expect(find.text('准备考试'), findsNothing);
    expect(find.text('没有最近删除的便利贴'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    note.dispose();
  });

  testWidgets('restore failure keeps the note and allows retry', (
    tester,
  ) async {
    final note = deletedNote('failure');
    final notes = [note];
    var attempts = 0;
    await showDeletedNotes(tester, notes, (_) async {
      attempts++;
      throw StateError('test restore error');
    });

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(notes, [note]);
    expect(find.text('准备考试'), findsOneWidget);
    expect(find.text('恢复失败，便利贴仍保留在最近删除中，请重试。'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('restore-deleted-note-failure')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('恢复'));
    await tester.pump();
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox());
    note.dispose();
  });

  testWidgets('pending restore cannot be submitted twice', (tester) async {
    final note = deletedNote('pending');
    final notes = [note];
    final pending = Completer<void>();
    var calls = 0;
    await showDeletedNotes(tester, notes, (_) async {
      calls++;
      await pending.future;
      notes.remove(note);
    });

    final restore = find.byKey(const ValueKey('restore-deleted-note-pending'));
    await tester.tap(restore);
    await tester.pump();
    expect(find.text('恢复中'), findsOneWidget);
    expect(tester.widget<TextButton>(restore).onPressed, isNull);
    await tester.tap(restore);
    await tester.pump();
    expect(calls, 1);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('没有最近删除的便利贴'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    note.dispose();
  });

  testWidgets('empty state explains where deleted notes go', (tester) async {
    await showDeletedNotes(tester, [], (_) async {});
    expect(find.text('最近删除'), findsOneWidget);
    expect(find.text('没有最近删除的便利贴'), findsOneWidget);
    expect(find.text('删除的便利贴会保留在这里，可以随时恢复。'), findsOneWidget);
    expect(find.text('恢复'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
