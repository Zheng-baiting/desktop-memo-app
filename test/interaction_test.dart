import 'dart:convert';

import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> mount(
    WidgetTester tester, {
    List<Map<String, dynamic>>? saved,
  }) async {
    tester.view.physicalSize = const Size(1180, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      if (saved != null) 'notes.v1': jsonEncode(saved),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MemoApp(prefs, initializePlatform: false));
    await tester.pumpAndSettle();
    return prefs;
  }

  Finder card() => find.byType(MemoCard).first;
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('body blank space moves the note and persists on release', (
    tester,
  ) async {
    final prefs = await mount(tester);
    final before = tester.getTopLeft(card());
    final gesture = await tester.startGesture(before + const Offset(190, 155));
    await gesture.moveBy(const Offset(35, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(35, 25));
    await tester.pump();
    expect(tester.getTopLeft(card()).dx, greaterThan(before.dx + 30));
    await gesture.up();
    await tester.pumpAndSettle();
    final saved = jsonDecode(prefs.getString('notes.v1')!) as List;
    expect(saved.first['x'], greaterThan(76));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('text and all buttons do not move the note', (tester) async {
    await mount(tester);
    final before = tester.getTopLeft(card());
    await tester.dragFrom(before + const Offset(22, 28), const Offset(60, 30));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card()), before);
    for (final tooltip in ['新建便利贴', '删除']) {
      final button = find.descendant(
        of: card(),
        matching: find.byTooltip(tooltip),
      );
      await tester.drag(button, const Offset(60, 30));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(card()), before);
    }
    await tester.drag(
      find.widgetWithText(TextButton, '提醒'),
      const Offset(60, 30),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card()), before);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('resizing keeps a bottom dock reachable', (tester) async {
    await mount(tester);
    await tester.dragFrom(
      tester.getTopLeft(card()) + const Offset(7, 130),
      const Offset(0, 1500),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(850, 560);
    await tester.pumpAndSettle();
    final canvas = tester.getRect(find.byKey(const ValueKey('memo-canvas')));
    expect(
      canvas.contains(
        tester.getRect(card()).bottomRight - const Offset(.1, .1),
      ),
      isTrue,
    );
    await tester.tap(card());
    await tester.pumpAndSettle();
    expect(tester.widget<MemoCard>(card()).note.collapsed, isFalse);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'existing reminder can be cancelled and stays cancelled on reload',
    (tester) async {
      final original = Memo(
        id: 'scheduled',
        title: '取消测试',
        body: '',
        x: 76,
        y: 100,
        color: 0,
        createdAt: 1,
        persistent: true,
        reminder: DateTime.now().add(const Duration(hours: 1)),
      );
      final prefs = await mount(tester, saved: [original.toJson()]);
      original.dispose();
      await tester.tap(find.widgetWithText(TextButton, '提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消提醒'));
      await tester.pumpAndSettle();
      expect(tester.widget<MemoCard>(card()).note.reminder, isNull);
      final saved = jsonDecode(prefs.getString('notes.v1')!) as List;
      expect(saved.first['reminder'], isNull);
      expect(saved.first['persistent'], isFalse);
      await unmount(tester);
      await tester.pumpWidget(MemoApp(prefs, initializePlatform: false));
      await tester.pumpAndSettle();
      expect(tester.widget<MemoCard>(card()).note.reminder, isNull);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('dismissing reminder mode does not create a reminder', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.widgetWithText(TextButton, '提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('提醒方式'), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<MemoCard>(card()).note.reminder, isNull);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final edge in ['left', 'right', 'top', 'bottom']) {
    testWidgets('$edge docking stays inside canvas and restores', (
      tester,
    ) async {
      await mount(tester);
      final delta = switch (edge) {
        'left' => const Offset(-1500, 0),
        'right' => const Offset(1500, 0),
        'top' => const Offset(0, -1500),
        _ => const Offset(0, 1500),
      };
      await tester.dragFrom(
        tester.getTopLeft(card()) + const Offset(7, 130),
        delta,
      );
      await tester.pumpAndSettle();
      final n = tester.widget<MemoCard>(card()).note;
      expect(n.collapsed, isTrue);
      expect(n.dock, edge);
      final canvas = tester.getRect(find.byKey(const ValueKey('memo-canvas')));
      final tab = tester.getRect(card());
      expect(canvas.contains(tab.topLeft), isTrue);
      expect(canvas.contains(tab.bottomRight - const Offset(.1, .1)), isTrue);
      await tester.tap(card());
      await tester.pumpAndSettle();
      expect(n.collapsed, isFalse);
      expect(tester.getSize(card()), const Size(270, 250));
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets('reorder preserves edited title, deletion unmounts safely', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('title-welcome')),
      '已修改标题',
    );
    await tester.tap(
      find.descendant(of: card(), matching: find.byTooltip('新建便利贴')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MemoCard), findsNWidgets(2));
    final first = find.byWidgetPredicate(
      (w) => w is MemoCard && w.note.id == 'welcome',
    );
    await tester.dragFrom(
      tester.getTopLeft(first) + const Offset(6, 80),
      const Offset(45, 20),
    );
    await tester.pumpAndSettle();
    final cards = tester.widgetList<MemoCard>(find.byType(MemoCard)).toList();
    expect(cards.last.note.id, 'welcome');
    expect(cards.last.note.titleController.text, '已修改标题');
    await tester.tap(
      find.descendant(of: first, matching: find.byTooltip('删除')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MemoCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
