import 'dart:convert';

import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Memo note;
  ReminderSelection? saved;
  var cancels = 0;
  setUp(() {
    note = Memo.fromJson({'id': 'editor', 'title': '原有标题', 'body': '原有正文'});
    saved = null;
    cancels = 0;
  });
  tearDown(() => note.dispose());
  Future<void> mount(
    WidgetTester tester, {
    String language = 'zh',
    Future<void> Function(ReminderSelection)? saveAction,
  }) async {
    tester.view.physicalSize = const Size(286, 266);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: memoTheme(language: language),
        home: Scaffold(
          body: Center(
            child: ReminderEditor(
              note: note,
              onBack: () {},
              onSave: (value) async {
                if (saveAction != null) await saveAction(value);
                saved = value;
              },
              onCancel: () async {
                cancels++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('save-reminder')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'quick reminder uses a future time without clock or calendar dialogs',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('30分钟后'));
      await save(tester);
      expect(
        saved!.when.isAfter(DateTime.now().add(const Duration(minutes: 29))),
        isTrue,
      );
      expect(
        saved!.when.isBefore(DateTime.now().add(const Duration(minutes: 31))),
        isTrue,
      );
      expect(saved!.mode, 'once');
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('date and 24 hour time can be typed directly', (tester) async {
    await mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('reminder-date')),
      '2040-05-01',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reminder-time')),
      '13:37',
    );
    await save(tester);
    expect(saved!.when, DateTime(2040, 5, 1, 13, 37));
    expect(note.body, '原有正文');
  });
  testWidgets('invalid dates and times cannot create a reminder', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('reminder-date')),
      '2040-02-30',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reminder-time')),
      '25:79',
    );
    await save(tester);
    expect(saved, isNull);
    expect(find.text('如 09:30'), findsOneWidget);
  });
  testWidgets(
    'past times are rejected and cancelling does not require valid fields',
    (tester) async {
      note.reminder = DateTime.now().add(const Duration(hours: 1));
      await mount(tester);
      await tester.enterText(
        find.byKey(const ValueKey('reminder-date')),
        '2000-01-01',
      );
      await save(tester);
      expect(saved, isNull);
      expect(find.text('请选择未来时间'), findsOneWidget);
      await tester.tap(find.text('取消提醒'));
      await tester.pumpAndSettle();
      expect(cancels, 1);
    },
  );
  testWidgets('English editor translates controls without changing note text', (
    tester,
  ) async {
    await mount(tester, language: 'en');
    expect(find.text('Set reminder'), findsOneWidget);
    expect(find.text('In 1 hour'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(note.title, '原有标题');
    expect(note.body, '原有正文');
  });

  testWidgets(
    'daily reminders require an end date on or after the selected date',
    (tester) async {
      await mount(tester);
      await tester.enterText(
        find.byKey(const ValueKey('reminder-date')),
        '2040-05-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reminder-time')),
        '13:37',
      );
      await tester.tap(find.byKey(const ValueKey('reminder-mode-daily')));
      await tester.pumpAndSettle();
      final end = find.byKey(const ValueKey('reminder-until'));
      await tester.ensureVisible(end);
      await tester.pumpAndSettle();
      await tester.enterText(end, '2040-04-30');
      await save(tester);
      expect(saved, isNull);
      await tester.enterText(end, '2040-05-02');
      await save(tester);
      expect(saved!.mode, 'daily');
      expect(saved!.until, DateTime(2040, 5, 2));
    },
  );
  testWidgets('manual time edits clear the shortcut selection', (tester) async {
    await mount(tester);
    final button = find.byKey(const ValueKey('quick-reminder-30'));
    bool selected() =>
        tester
            .widget<Semantics>(
              find.ancestor(of: button, matching: find.byType(Semantics)).first,
            )
            .properties
            .selected ==
        true;
    expect(selected(), isFalse);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(selected(), isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('reminder-time')),
      '14:20',
    );
    await tester.pumpAndSettle();
    expect(selected(), isFalse);
    expect(note.body, '原有正文');
  });

  testWidgets(
    'daily end date and actions stay visible inside the small editor',
    (tester) async {
      note.reminder = DateTime(2040, 5, 1, 10);
      note.daily = true;
      await mount(tester, language: 'en');
      final end = tester.getRect(find.byKey(const ValueKey('reminder-until')));
      final action = tester.getRect(
        find.byKey(const ValueKey('save-reminder')),
      );
      expect(
        end.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(ListView)).bottom),
      );
      expect(end.bottom, lessThanOrEqualTo(action.top));
      expect(
        end.top,
        greaterThan(tester.getRect(find.byType(ReminderEditor)).top),
      );
      expect(find.text('In 30 min'), findsNothing);
      expect(find.text('Remove reminder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save failures stay visible above the action and allow retry', (
    tester,
  ) async {
    var fail = true;
    await mount(
      tester,
      saveAction: (_) async {
        if (fail) throw StateError('save unavailable');
      },
    );
    await save(tester);
    expect(saved, isNull);
    final message = find.text('保存失败，请重试');
    expect(message, findsOneWidget);
    expect(
      tester.getRect(message).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('save-reminder'))).top,
      ),
    );
    expect(note.reminder, isNull);
    fail = false;
    await save(tester);
    expect(saved, isNotNull);
    expect(message, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inline repeat choice preserves the typed date and saves recurrence',
    (tester) async {
      await mount(tester);
      await tester.enterText(
        find.byKey(const ValueKey('reminder-date')),
        '2040-05-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reminder-time')),
        '13:37',
      );
      await tester.tap(find.byKey(const ValueKey('reminder-mode-repeat')));
      await tester.pumpAndSettle();
      await save(tester);
      expect(saved!.mode, 'repeat');
      expect(saved!.when, DateTime(2040, 5, 1, 13, 37));
      expect(saved!.until, isNull);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    },
  );

  testWidgets('saved English language is restored by the application', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'ui.language': 'en',
      'notes.v1': jsonEncode([note.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MemoApp(prefs, initializePlatform: false));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close or delete note'), findsOneWidget);
    expect(find.text('Remind'), findsOneWidget);
    expect(tester.widget<MemoCard>(find.byType(MemoCard)).note.body, '原有正文');
    await tester.pumpWidget(const SizedBox());
  });
}
