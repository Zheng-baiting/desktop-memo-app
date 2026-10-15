import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Memo> notes;
  setUp(() {
    notes = [
      Memo.fromJson({
        'id': 'a',
        'title': '英语复习',
        'body': '背诵短文',
        'createdAt': 1,
      }),
      Memo.fromJson({
        'id': 'b',
        'title': '工作',
        'body': 'Review Flutter code',
        'createdAt': 2,
      }),
    ];
  });
  tearDown(() {
    for (final note in notes) {
      note.dispose();
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    Set<String> visible = const {'b'},
    ValueChanged<Memo>? onOpen,
    VoidCallback? onNew,
    List<Memo>? saved,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: memoTheme(),
      home: NoteManager(
        notes: saved ?? notes,
        visibleIds: visible,
        toolbar: const Text('全部便利贴'),
        onOpen: onOpen ?? (_) {},
        onNew: onNew ?? () {},
      ),
    ),
  );

  testWidgets('search finds title and body, ignores case and can be cleared', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byKey(const ValueKey('note-search')), '英语');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manager-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('manager-b')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('note-search')),
      '  FLUTTER  ',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manager-a')), findsNothing);
    expect(find.byKey(const ValueKey('manager-b')), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets(
    'hidden note is clearly retained and opening selects only that note',
    (tester) async {
      final opened = <String>[];
      await mount(tester, onOpen: (note) => opened.add(note.id));
      expect(find.text('2 张便签 · 1 张显示中 · 1 张已收起'), findsOneWidget);
      final hidden = find.byKey(const ValueKey('manager-a'));
      expect(
        find.descendant(of: hidden, matching: find.text('已收起')),
        findsOneWidget,
      );
      await tester.tap(find.descendant(of: hidden, matching: find.text('打开')));
      expect(opened, ['a']);
      expect(notes.length, 2);
      expect(notes.first.body, '背诵短文');
    },
  );

  testWidgets(
    'visibility refresh keeps the search and changes open to locate',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byKey(const ValueKey('note-search')), '英语');
      await tester.pumpAndSettle();
      await mount(tester, visible: {'a', 'b'});
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-search')))
            .controller!
            .text,
        '英语',
      );
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('定位'), findsOneWidget);
      expect(find.text('2 张便签 · 2 张显示中 · 0 张已收起'), findsOneWidget);
    },
  );

  testWidgets(
    'no search match differs from an empty archive and never deletes data',
    (tester) async {
      await mount(tester);
      await tester.enterText(
        find.byKey(const ValueKey('note-search')),
        '没有的关键词',
      );
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的便利贴，试试其他关键词'), findsOneWidget);
      expect(notes.length, 2);
      await tester.pumpWidget(const SizedBox());
      var created = 0;
      await mount(tester, saved: [], visible: {}, onNew: () => created++);
      await tester.tap(find.text('创建第一张便利贴'));
      expect(created, 1);
    },
  );
}
