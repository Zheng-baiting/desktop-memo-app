import 'dart:convert';

import 'package:desktop_memo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Memo planned() => Memo(
    id: 'plan',
    title: 'old',
    body: 'old',
    x: 0,
    y: 0,
    color: 0,
    createdAt: 0,
    dailyPlan: const {
      '2026-09-17': '22:00–22:35 英语；22:40–23:25 变量',
      '2026-09-18': '22:00–22:35 英语；22:40–23:25 输入输出',
      '2026-09-19': '22:00–22:25 轻量复习',
    },
  );
  test('preview starts tomorrow and calendar rollover updates text and controllers', () {
    final n = planned();
    expect(n.updateDailyPlan(DateTime(2026, 9, 16, 23)), isTrue);
    expect(n.title, '2026-09-17');
    expect(n.updateDailyPlan(DateTime(2026, 9, 17, 22)), isFalse);
    expect(n.updateDailyPlan(DateTime(2026, 9, 18)), isTrue);
    expect(n.titleController.text, '2026-09-18');
    expect(n.bodyController.text, contains('输入输出'));
    expect(n.updateDailyPlan(DateTime(2026, 9, 20)), isTrue);
    expect(n.title, '2026-09-19');
    expect(n.updateDailyPlan(DateTime(2026, 9, 21)), isFalse);
    n.dispose();
  });
  test('restart selects current date without creating missed-day notes', () {
    final n = planned()..updateDailyPlan(DateTime(2026, 9, 17));
    final restored = Memo.fromJson(
      jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>,
    );
    restored.updateDailyPlan(DateTime(2026, 9, 19, 23));
    expect(restored.title, '2026-09-19');
    expect(restored.dailyPlan.length, 3);
    expect(restored.body, contains('轻量复习'));
    n.dispose();
    restored.dispose();
  });
  test('ordinary notes keep their title and text', () {
    final n = Memo(
      id: 'plain',
      title: 'personal',
      body: 'keep',
      x: 0,
      y: 0,
      color: 0,
      createdAt: 0,
    );
    expect(n.updateDailyPlan(DateTime(2026, 9, 18)), isFalse);
    expect(n.title, 'personal');
    expect(n.body, 'keep');
    n.dispose();
  });
}
