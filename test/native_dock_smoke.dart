// Test-only inspection channels; never loaded by the normal app entry point.
import 'dart:convert';
import 'dart:io';

import 'package:desktop_memo/main.dart' as app;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

WindowMethodChannel inspection(String id) =>
    WindowMethodChannel('dock-smoke-$id', mode: ChannelMode.unidirectional);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await WindowController.fromCurrentEngine();
  if (controller.arguments.isNotEmpty) {
    await app.main(args);
    await inspection(controller.windowId).setMethodCallHandler((_) async {
      app.MemoCard? card;
      RenderBox? box;
      void visit(Element element) {
        if (element.widget is app.MemoCard) {
          card = element.widget as app.MemoCard;
          box = element.findRenderObject() as RenderBox;
        }
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      if (card == null || box == null) throw StateError('No paper rendered');
      final window = await windowManager.getBounds();
      final paper = box!.localToGlobal(Offset.zero) & box!.size;
      return {
        'window': [window.left, window.top, window.width, window.height],
        'paper': [paper.left, paper.top, paper.width, paper.height],
        'collapsed': card!.note.collapsed,
      };
    });
    return;
  }
  final display = (await screenRetriever.getAllDisplays()).first;
  final work =
      (display.visiblePosition ?? Offset.zero) &
      (display.visibleSize ?? display.size);
  SharedPreferences.setMockInitialValues({
    'notes.v1': jsonEncode([
      for (final edge in ['left', 'right', 'top', 'bottom'])
        {
          'id': 'dock-$edge',
          'title': '收纳测试 $edge',
          'body': '临时测试，不使用真实备忘录',
          'x': work.left + 300,
          'y': work.top + 300,
          'color': 0,
          'collapsed': true,
          'dock': edge,
          'createdAt': 1,
        },
    ]),
  });
  await app.main(args);
  Rect rect(dynamic values) {
    final v = (values as List).cast<num>();
    return Rect.fromLTWH(
      v[0].toDouble(),
      v[1].toDouble(),
      v[2].toDouble(),
      v[3].toDouble(),
    );
  }

  Future<void> check(WindowController window, String edge) async {
    final data = (await inspection(window.windowId)
        .invokeMethod<Map>('inspect'))!;
    final bounds = rect(data['window']);
    final paper = rect(data['paper']).shift(bounds.topLeft);
    stdout.writeln('DOCK $edge: native=$bounds, paper=$paper');
    if (data['collapsed'] != true) {
      throw StateError(
        '$edge did not collapse; keep the pointer away from test notes',
      );
    }
    if (!work.inflate(1).contains(paper.topLeft) ||
        !work.inflate(1).contains(paper.bottomRight)) {
      throw StateError('$edge paper is clipped outside the screen');
    }
    final gap = switch (edge) {
      'left' => paper.left - work.left,
      'right' => work.right - paper.right,
      'top' => paper.top - work.top,
      _ => work.bottom - paper.bottom,
    };
    final expected = edge == 'left' || edge == 'right'
        ? const Size(34, 150)
        : const Size(150, 34);
    if ((gap - 8).abs() > 1 || paper.size != expected) {
      throw StateError(
        '$edge tab has inconsistent edge gap or size: $gap, ${paper.size}',
      );
    }
  }

  try {
    List<WindowController> windows = [];
    for (var i = 0; i < 100; i++) {
      windows = (await WindowController.getAll())
          .where((w) => w.arguments.isNotEmpty)
          .toList();
      if (windows.length == 4) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (windows.length != 4) throw StateError('Missing dock test windows');
    await Future<void>.delayed(const Duration(seconds: 2));
    for (final window in windows) {
      final edge =
          (jsonDecode(window.arguments)['note'] as Map)['dock'] as String;
      await check(window, edge);
      await window.invokeMethod('reveal');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final expanded = (await inspection(window.windowId)
          .invokeMethod<Map>('inspect'))!;
      if (expanded['collapsed'] != false ||
          rect(expanded['paper']).size != const Size(270, 250)) {
        throw StateError('$edge failed to expand fully');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      await check(window, edge);
    }
    stdout.writeln(
      'NATIVE_DOCK_PASS: all four tabs fully visible and edge-aligned before and after expansion.',
    );
  } catch (error, stack) {
    stderr.writeln('NATIVE_DOCK_FAIL: $error\n$stack');
    exitCode = 1;
  } finally {
    await windowManager.destroy();
  }
}
