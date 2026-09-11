import 'package:desktop_memo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual native minimum size stays inside every dock edge', () {
    for (final origin in [Offset.zero, const Offset(-1920, -200)]) {
      final work = origin & const Size(1920, 1040);
      final right = desktopNoteBounds(
        Rect.fromLTWH(work.right - 50, work.top + 300, 135, 166),
        work,
        dock: 'right',
      );
      expect(right.right, work.right);
      expect(right.width, 135);
      for (final edge in ['left', 'right', 'top', 'bottom']) {
        final bounds = desktopNoteBounds(
          Rect.fromLTWH(work.right - 50, work.bottom - 50, 135, 166),
          work,
          dock: edge,
        );
        expect(work.intersect(bounds), bounds);
      }
    }
  });
  for (final edge in ['left', 'right', 'top', 'bottom']) {
    testWidgets('$edge tab aligns to its edge in an oversized native window', (
      tester,
    ) async {
      final outer = GlobalKey();
      final inner = GlobalKey();
      final vertical = edge == 'left' || edge == 'right';
      final size = vertical ? const Size(50, 166) : const Size(166, 50);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: outer,
              width: 200,
              height: 200,
              child: OverflowBox(
                alignment: desktopDockAlignment(edge),
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: SizedBox(
                  key: inner,
                  width: size.width,
                  height: size.height,
                ),
              ),
            ),
          ),
        ),
      );
      final host = tester.getRect(find.byKey(outer));
      final tab = tester.getRect(find.byKey(inner));
      expect(host.intersect(tab), tab);
      switch (edge) {
        case 'left':
          expect(tab.left, host.left);
        case 'right':
          expect(tab.right, host.right);
        case 'top':
          expect(tab.top, host.top);
        case 'bottom':
          expect(tab.bottom, host.bottom);
      }
    });
  }
  test('paper slides toward the matching screen edge', () {
    expect(dockSlideOffset('left'), const Offset(-1, 0));
    expect(dockSlideOffset('right'), const Offset(1, 0));
    expect(dockSlideOffset('top'), const Offset(0, -1));
    expect(dockSlideOffset('bottom'), const Offset(0, 1));
  });
  testWidgets('collapse keeps full paper visible until the slide finishes', (
    tester,
  ) async {
    final note = Memo(
      id: 'slide',
      title: '内容保留',
      body: '滑动途中',
      x: 0,
      y: 0,
      color: 0,
      createdAt: 0,
      collapsed: true,
    );
    Widget frame(bool collapsed) => MaterialApp(
      home: Scaffold(
        body: MemoCard(
          note: note,
          collapsedOverride: collapsed,
          onChanged: () {},
          onDelete: (_) {},
          onReminder: (_) {},
          onNew: () {},
          onFront: (_) {},
          onToggleCollapsed: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(frame(false));
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.getSize(find.byType(MemoCard)), const Size(270, 250));
    await tester.pumpWidget(frame(true));
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(frame(false));
    expect(note.bodyController.text, '滑动途中');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    note.dispose();
  });
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

  test('crossing an edge still docks, including negative monitor origins', () {
    for (final origin in [Offset.zero, const Offset(-1920, -200)]) {
      final work = origin & const Size(1920, 1040);
      for (final overshoot in [0.0, 14.0, 30.0, 100.0]) {
        expect(
          desktopDockEdge(
            Rect.fromLTWH(work.left - overshoot, work.top + 300, 286, 266),
            work,
          ),
          'left',
        );
        expect(
          desktopDockEdge(
            Rect.fromLTWH(
              work.right - 286 + overshoot,
              work.top + 300,
              286,
              266,
            ),
            work,
          ),
          'right',
        );
        expect(
          desktopDockEdge(
            Rect.fromLTWH(work.left + 500, work.top - overshoot, 286, 266),
            work,
          ),
          'top',
        );
        expect(
          desktopDockEdge(
            Rect.fromLTWH(
              work.left + 500,
              work.bottom - 266 + overshoot,
              286,
              266,
            ),
            work,
          ),
          'bottom',
        );
      }
    }
  });

  test('docking retains the inside threshold and releases away from edges', () {
    const work = Rect.fromLTWH(0, 0, 1920, 1040);
    for (final gap in [14.0, 15.0, 100.0]) {
      final bounds = {
        'left': Rect.fromLTWH(gap, 300, 286, 266),
        'right': Rect.fromLTWH(1920 - 286 - gap, 300, 286, 266),
        'top': Rect.fromLTWH(500, gap, 286, 266),
        'bottom': Rect.fromLTWH(500, 1040 - 266 - gap, 286, 266),
      };
      for (final entry in bounds.entries) {
        expect(
          desktopDockEdge(entry.value, work),
          gap <= 14 ? entry.key : null,
        );
      }
    }
    // At a corner, prefer the crossed edge over an edge merely nearby.
    expect(
      desktopDockEdge(const Rect.fromLTWH(1664, 2, 286, 266), work),
      'right',
    );
  });

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
