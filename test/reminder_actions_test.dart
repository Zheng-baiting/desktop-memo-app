import 'dart:async';

import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> showActions(
  WidgetTester tester, {
  required Future<void> Function(int?) onAction,
  bool daily = false,
  double width = 260,
}) => tester.pumpWidget(
  MaterialApp(
    theme: memoTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: ReminderActions(daily: daily, onAction: onAction),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('buttons route 10, 30 and acknowledgement actions', (
    tester,
  ) async {
    final calls = <int?>[];
    await showActions(tester, onAction: (minutes) async => calls.add(minutes));
    await tester.tap(find.text('10分钟后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30分钟后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我知道了，停止提醒'));
    await tester.pumpAndSettle();
    expect(calls, [10, 30, null]);
  });

  testWidgets('daily acknowledgement preserves the daily reminder intent', (
    tester,
  ) async {
    final calls = <int?>[];
    await showActions(
      tester,
      daily: true,
      onAction: (minutes) async => calls.add(minutes),
    );
    await tester.tap(find.text('今天已读 · 保留每天提醒'));
    await tester.pumpAndSettle();
    expect(calls, [null]);
    expect(find.text('我知道了，停止提醒'), findsNothing);
  });

  testWidgets('pending action disables every button and prevents duplicates', (
    tester,
  ) async {
    final pending = Completer<void>();
    final calls = <int?>[];
    await showActions(
      tester,
      onAction: (minutes) async {
        calls.add(minutes);
        await pending.future;
      },
    );

    await tester.tap(find.text('10分钟后'));
    await tester.pump();
    expect(find.text('正在处理…'), findsOneWidget);
    for (final button in tester.widgetList<TextButton>(
      find.byType(TextButton),
    )) {
      expect(button.onPressed, isNull);
    }
    await tester.tap(find.text('10分钟后'));
    await tester.tap(find.text('30分钟后'));
    await tester.tap(find.text('我知道了，停止提醒'));
    await tester.pump();
    expect(calls, [10]);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('正在处理…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure keeps actions available for a retry', (tester) async {
    var attempts = 0;
    await showActions(
      tester,
      onAction: (_) async {
        attempts++;
        if (attempts == 1) throw StateError('test action error');
      },
    );

    await tester.tap(find.text('30分钟后'));
    await tester.pumpAndSettle();
    expect(find.text('操作失败，请重试'), findsOneWidget);
    for (final button in tester.widgetList<TextButton>(
      find.byType(TextButton),
    )) {
      expect(button.onPressed, isNotNull);
    }
    await tester.tap(find.text('30分钟后'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('操作失败，请重试'), findsNothing);
  });

  testWidgets('daily actions fit a narrow note without overflow', (
    tester,
  ) async {
    await showActions(
      tester,
      daily: true,
      width: 180,
      onAction: (_) async => throw StateError('test action error'),
    );
    final normal = tester.getSize(find.byType(ReminderActions));
    expect(normal.width, 180);
    expect(normal.height, lessThanOrEqualTo(100));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('10分钟后'));
    await tester.pumpAndSettle();
    expect(find.text('操作失败，请重试'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ReminderActions)).height,
      lessThanOrEqualTo(100),
    );
    expect(tester.takeException(), isNull);
  });
}
