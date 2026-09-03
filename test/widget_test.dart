import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_memo/main.dart';

void main() {
  test('memo round-trips through JSON', () {
    final original = Memo(
      id: '1',
      title: '买牛奶',
      body: '今天 18:00',
      x: 12,
      y: 24,
      color: 2,
      createdAt: 123,
      z: 4,
      collapsed: true,
      dock: 'right',
      reminder: DateTime(2026, 9, 3, 18, 0),
    );
    final copy = Memo.fromJson(original.toJson());
    expect(copy.title, '买牛奶');
    expect(copy.body, '今天 18:00');
    expect(copy.z, 4);
    expect(copy.collapsed, isTrue);
    expect(copy.dock, 'right');
    expect(copy.reminder, DateTime(2026, 9, 3, 18, 0));
    original.dispose();
    copy.dispose();
  });
}
