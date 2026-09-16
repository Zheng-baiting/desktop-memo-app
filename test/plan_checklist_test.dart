import 'dart:convert';

import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const line = '20:10–20:20 英语旧词';
Memo planned() => Memo(
  id: 'checklist',
  title: '2026-09-17',
  body: '周四\n$line',
  x: 0,
  y: 0,
  color: 0,
  createdAt: 0,
  planDate: '2026-09-17',
  dailyPlan: const {'2026-09-17': '周四\n$line', '2026-09-18': '周五\n$line'},
);

void main() {
  test(
    'completed tasks survive restart and are isolated by day and content',
    () {
      final n = planned();
      n.completedTasks.add(n.taskKey(line));
      final restored = Memo.fromJson(jsonDecode(jsonEncode(n.toJson())));
      expect(restored.completedTasks.contains(restored.taskKey(line)), isTrue);
      expect(
        restored.completedTasks.contains(restored.taskKey('$line 改期')),
        isFalse,
      );
      restored.updateDailyPlan(DateTime(2026, 9, 18));
      expect(restored.completedTasks.contains(restored.taskKey(line)), isFalse);
      expect(restored.completedTasks.length, 1);
      n.dispose();
      restored.dispose();
    },
  );

  testWidgets('check button animates a row gray, saves and can undo', (
    tester,
  ) async {
    final n = planned();
    final edits = <(String, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 245,
            height: 170,
            child: PlanTaskList(
              note: n,
              onChanged: (key, done) => edits.add((key, done)),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('标记完成'), findsOneWidget);
    await tester.tap(find.byTooltip('标记完成'));
    await tester.pump();
    expect(edits.single, (n.taskKey(line), true));
    expect(n.completedTasks, contains(n.taskKey(line)));
    await tester.pump(const Duration(milliseconds: 500));
    final row = tester.widget<AnimatedContainer>(
      find.byKey(ValueKey('task-${n.taskKey(line)}')),
    );
    expect((row.decoration as BoxDecoration).color, const Color(0xFFE0E0E0));
    final style = tester.widget<AnimatedDefaultTextStyle>(
      find.byType(AnimatedDefaultTextStyle).last,
    );
    expect(style.style.color, const Color(0xFF616161));
    expect(style.style.decoration, TextDecoration.lineThrough);
    await tester.tap(find.byTooltip('撤销完成'));
    await tester.pumpAndSettle();
    expect(n.completedTasks, isEmpty);
    expect(edits.last, (n.taskKey(line), false));
    n.dispose();
  });
}
