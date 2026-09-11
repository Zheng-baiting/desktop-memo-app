import 'dart:async';

import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'settings fit inside the paper and route actions without OS writes',
    (tester) async {
      final calls = <bool?>[];
      var back = 0;
      var reminders = 0;
      var exits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: memoTheme(),
          home: Scaffold(
            body: Center(
              child: NoteSettingsPanel(
                color: papers.first,
                onStartup: (enabled) async {
                  calls.add(enabled);
                  return enabled ?? false;
                },
                onBack: () => back++,
                onReminder: () => reminders++,
                onExit: () async => exits++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, [null]);
      expect(
        tester.getSize(find.byType(NoteSettingsPanel)),
        const Size(270, 250),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(calls, [null, true]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.text('本张便利贴的提醒'));
      await tester.tap(find.text('保存并退出应用'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回便利贴'));
      expect([back, reminders, exits], [1, 1, 1]);
    },
  );

  testWidgets('startup failures keep the actual value and allow retry', (
    tester,
  ) async {
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteSettingsPanel(
            color: papers.first,
            onStartup: (enabled) async {
              if (fail) throw StateError('test error');
              return false;
            },
            onBack: () {},
            onReminder: () {},
            onExit: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    fail = true;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('自启动设置失败，点击重试'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('自启动设置失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('自启动设置失败，点击重试'), findsNothing);
  });

  testWidgets('a pending settings read is safe after the panel closes', (
    tester,
  ) async {
    final pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteSettingsPanel(
            color: papers.first,
            onStartup: (_) => pending.future,
            onBack: () {},
            onReminder: () {},
            onExit: () async {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings button opens settings and cannot drag the note', (
    tester,
  ) async {
    final note = Memo(
      id: 'settings',
      title: '便签',
      body: '内容',
      x: 0,
      y: 0,
      color: 0,
      createdAt: 0,
    );
    var opened = 0;
    var drags = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoCard(
            note: note,
            onChanged: () {},
            onDelete: (_) {},
            onReminder: (_) {},
            onNew: () {},
            onFront: (_) {},
            onToggleCollapsed: (_) {},
            onSettings: () => opened++,
            onDragStart: () => drags++,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('便利贴设置'));
    expect(opened, 1);
    await tester.drag(find.byTooltip('便利贴设置'), const Offset(50, 10));
    expect(drags, 0);
    expect(note.bodyController.text, '内容');
    await tester.pumpWidget(const SizedBox());
    note.dispose();
  });
}
