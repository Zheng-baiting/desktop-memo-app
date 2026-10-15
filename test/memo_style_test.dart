import 'dart:convert';

import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every palette keeps paper text and button labels readable', () {
    double contrast(Color a, Color b) {
      final values = [a.computeLuminance(), b.computeLuminance()]..sort();
      return (values.last + .05) / (values.first + .05);
    }

    expect(memoStyles.map((s) => s.id).toSet().length, 6);
    for (final palette in memoStyles) {
      expect(contrast(palette.paper, palette.ink), greaterThanOrEqualTo(4.5));
      expect(contrast(palette.paper, palette.muted), greaterThanOrEqualTo(4.5));
      expect(
        contrast(palette.paper, palette.accent),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(memoStyle('unknown').id, 'yellow');
    expect(memoStyle(null).id, 'yellow');
  });

  testWidgets(
    'style picker updates paper and keeps exit reachable at note size',
    (tester) async {
      tester.view.physicalSize = const Size(286, 266);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var style = 'yellow';
      var fail = false;
      var exits = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, rebuild) {
            return MaterialApp(
              theme: memoTheme(style: style),
              home: Scaffold(
                body: Center(
                  child: NoteSettingsPanel(
                    color: memoStyle(style).paper,
                    style: style,
                    onStyle: (id) async {
                      if (fail) throw StateError('unavailable');
                      rebuild(() => style = id);
                    },
                    onLanguage: (_) async {},
                    onStartup: (_) async => false,
                    onBack: () {},
                    onReminder: () {},
                    onManage: () {},
                    onExit: () async => exits++,
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并退出应用'));
      await tester.pumpAndSettle();
      expect(exits, 1);
      await tester.tap(find.byKey(const ValueKey('open-style-choices')));
      await tester.pumpAndSettle();
      for (final palette in memoStyles) {
        await tester.tap(find.byKey(ValueKey('style-${palette.id}')));
        await tester.pumpAndSettle();
        expect(style, palette.id);
        final panel = find.byType(NoteSettingsPanel);
        final material = tester.widget<Material>(
          find.descendant(of: panel, matching: find.byType(Material)).first,
        );
        expect(material.color, palette.paper);
        expect(tester.takeException(), isNull);
      }
      fail = true;
      await tester.tap(find.byKey(const ValueKey('style-pink')));
      await tester.pumpAndSettle();
      expect(style, 'ivory');
      expect(find.text('配色保存失败，请重试'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const ValueKey('style-blue')));
      await tester.pumpAndSettle();
      expect(style, 'blue');
      expect(find.text('配色保存失败，请重试'), findsNothing);
      await tester.tap(find.byTooltip('返回设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('全部便利贴'), 40);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('保存并退出应用'));
      await tester.pumpAndSettle();
      expect(exits, 2);
    },
  );

  testWidgets(
    'persisted style survives app reload without altering note records',
    (tester) async {
      final raw = jsonEncode([
        {
          'id': 'retained',
          'title': '保留标题',
          'body': 'keep this text',
          'color': 5,
          'completedTasks': ['day|task'],
        },
      ]);
      for (final id in ['pink', 'blue', 'unknown']) {
        SharedPreferences.setMockInitialValues({
          'notes.v1': raw,
          'ui.style': id,
        });
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(MemoApp(prefs, initializePlatform: false));
        await tester.pumpAndSettle();
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.theme!.colorScheme.surface, memoStyle(id).paper);
        expect(prefs.getString('notes.v1'), raw);
        expect(find.text('保留标题'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('menus and reminder editor inherit the selected paper style', (
    tester,
  ) async {
    final note = Memo.fromJson({
      'id': 'paper',
      'body': 'unchanged',
      'color': 9,
    });
    for (final palette in memoStyles) {
      await tester.pumpWidget(
        MaterialApp(
          theme: memoTheme(style: palette.id),
          home: Scaffold(
            body: MemoCard(
              note: note,
              onChanged: () {},
              onDelete: (_) {},
              onReminder: (_) {},
              onNew: () {},
              onFront: (_) {},
              onToggleCollapsed: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final menu = tester.widget<PopupMenuButton<String>>(
        find.byType(PopupMenuButton<String>),
      );
      expect(menu.color, palette.paper);
      final cardPaper = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(MemoCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(cardPaper.color, palette.paper);
      await tester.pumpWidget(
        MaterialApp(
          theme: memoTheme(style: palette.id),
          home: Scaffold(
            body: ReminderEditor(
              note: note,
              onBack: () {},
              onSave: (_) async {},
              onCancel: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reminderPaper = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(ReminderEditor),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(reminderPaper.color, palette.paper);
    }
    expect(note.bodyController.text, 'unchanged');
    expect(note.color, 9);
    await tester.pumpWidget(const SizedBox());
    note.dispose();
  });
}
