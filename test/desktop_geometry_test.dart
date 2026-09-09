import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'auto-hide waits for mouse exit and never hides while editing or busy',
    () {
      bool allowed({
        bool docked = true,
        bool collapsed = false,
        bool hovered = false,
        bool editing = false,
        bool busy = false,
      }) => canAutoHideNote(
        docked: docked,
        collapsed: collapsed,
        hovered: hovered,
        editing: editing,
        busy: busy,
      );
      expect(allowed(), isTrue);
      expect(allowed(hovered: true), isFalse);
      expect(allowed(editing: true), isFalse);
      expect(allowed(busy: true), isFalse);
      expect(allowed(docked: false), isFalse);
      expect(allowed(collapsed: true), isFalse);
    },
  );
  for (final edge in ['left', 'right', 'top', 'bottom']) {
    testWidgets('$edge collapsed tab has four smooth rounded corners', (
      tester,
    ) async {
      final note = Memo(
        id: 'tab',
        title: '收纳',
        body: '',
        x: 0,
        y: 0,
        color: 0,
        createdAt: 0,
        collapsed: true,
        dock: edge,
      );
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
            ),
          ),
        ),
      );
      final tab = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((w) => w.decoration is BoxDecoration);
      expect(
        (tab.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(14),
      );
      await tester.pumpWidget(const SizedBox());
      note.dispose();
    });
  }
  test(
    'deleting one native note closes its window without quitting the app',
    () async {
      const channel = MethodChannel('window_manager');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await closeDesktopNoteWindow();
      expect(calls.map((call) => call.method), ['setPreventClose', 'close']);
      expect(calls.first.arguments, {'isPreventClose': false});
    },
  );
  test(
    'desktop docking uses monitor work area, including negative origins',
    () {
      const work = Rect.fromLTWH(-1920, -200, 1920, 1040);
      expect(
        desktopDockEdge(const Rect.fromLTWH(-1918, 100, 286, 266), work),
        'left',
      );
      expect(
        desktopDockEdge(const Rect.fromLTWH(-286, 100, 286, 266), work),
        'right',
      );
      expect(
        desktopDockEdge(const Rect.fromLTWH(-1000, -200, 286, 266), work),
        'top',
      );
      expect(
        desktopDockEdge(const Rect.fromLTWH(-1000, 574, 286, 266), work),
        'bottom',
      );
      expect(
        desktopDockEdge(const Rect.fromLTWH(-1000, 100, 286, 266), work),
        isNull,
      );
      expect(
        fitDesktopNote(const Rect.fromLTWH(4000, 4000, 286, 266), work),
        const Rect.fromLTWH(-286, 574, 286, 266),
      );
    },
  );

  testWidgets('paper has soft anti-aliased corners', (tester) async {
    final note = Memo(
      id: 'shape',
      title: '圆角',
      body: '',
      x: 0,
      y: 0,
      color: 0,
      createdAt: 0,
    );
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
          ),
        ),
      ),
    );
    final paper = tester
        .widgetList<Material>(find.byType(Material))
        .firstWhere((material) => material.color == papers[0]);
    expect(paper.borderRadius, BorderRadius.circular(18));
    expect(paper.clipBehavior, Clip.antiAlias);
    await tester.pumpWidget(const SizedBox());
    note.dispose();
  });
}
