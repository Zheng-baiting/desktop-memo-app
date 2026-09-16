import 'package:desktop_memo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Memo makeNote() => Memo(
    id: 'daily',
    title: '学习',
    body: '',
    x: 0,
    y: 0,
    color: 0,
    createdAt: 0,
    daily: true,
    reminder: DateTime(2026, 9, 17, 22),
    repeatUntil: DateTime(2027, 3, 16),
  );

  test('daily repeats at the selected time across month boundaries', () {
    final n = makeNote();
    expect(
      n.nextReminderAfter(DateTime(2026, 9, 30, 22, 5)),
      DateTime(2026, 10, 1, 22),
    );
    expect(
      n.nextReminderAfter(DateTime(2026, 12, 31, 23)),
      DateTime(2027, 1, 1, 22),
    );
    n.dispose();
  });
  test('missed days are not replayed and the time does not drift', () {
    final n = makeNote();
    expect(
      n.nextReminderAfter(DateTime(2026, 9, 20, 8)),
      DateTime(2026, 9, 20, 22),
    );
    expect(
      n.nextReminderAfter(DateTime(2026, 9, 20, 23)),
      DateTime(2026, 9, 21, 22),
    );
    n.dispose();
  });
  test('end date includes the last day and prevents later catch-up', () {
    final n = makeNote();
    expect(
      n.nextReminderAfter(DateTime(2027, 3, 15, 23)),
      DateTime(2027, 3, 16, 22),
    );
    expect(n.expiredAt(DateTime(2027, 3, 16, 23)), isFalse);
    expect(n.nextReminderAfter(DateTime(2027, 3, 16, 22)), isNull);
    expect(n.expiredAt(DateTime(2027, 3, 17)), isTrue);
    n.dispose();
  });
  test('daily settings survive storage; legacy notes keep their behavior', () {
    final n = makeNote();
    final copy = Memo.fromJson(n.toJson());
    expect(copy.daily, isTrue);
    expect(copy.repeatUntil, DateTime(2027, 3, 16));
    final legacy = n.toJson()
      ..remove('daily')
      ..remove('repeatUntil');
    final old = Memo.fromJson(legacy);
    expect(old.daily, isFalse);
    expect(old.nextReminderAfter(DateTime(2026, 9, 17, 22)), isNull);
    old.persistent = true;
    expect(
      old.nextReminderAfter(DateTime(2026, 9, 17, 22)),
      DateTime(2026, 9, 17, 22, 10),
    );
    n.dispose();
    copy.dispose();
    old.dispose();
  });
}
