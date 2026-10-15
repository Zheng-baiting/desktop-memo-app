import 'package:desktop_memo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Memo note({
    DateTime? reminder,
    bool daily = false,
    bool persistent = false,
  }) => Memo(
    id: 'snooze',
    title: '稍后提醒',
    body: '',
    x: 0,
    y: 0,
    color: 0,
    createdAt: 0,
    reminder: reminder,
    daily: daily,
    persistent: persistent,
  );

  test('old notes have no snooze or deletion date and keep compact JSON', () {
    final n = Memo.fromJson({'id': 'legacy'});
    expect(n.snoozedUntil, isNull);
    expect(n.toJson().containsKey('snoozedUntil'), isFalse);
    expect(n.toJson().containsKey('deletedAt'), isFalse);
    n.dispose();
  });

  test('a fired one-time reminder can be snoozed and survives restart', () {
    final now = DateTime(2026, 10, 14, 9);
    final n = note(); // The original one-time reminder was already consumed.
    n.snoozeReminder(const Duration(minutes: 30), now: now);
    final copy = Memo.fromJson(n.toJson());
    expect(copy.reminder, isNull);
    expect(copy.nextAlertAt, DateTime(2026, 10, 14, 9, 30));
    expect(copy.reminderDueAt(now.add(const Duration(minutes: 29))), isFalse);
    expect(copy.reminderDueAt(now.add(const Duration(minutes: 30))), isTrue);
    copy.consumeReminder(now.add(const Duration(minutes: 30)));
    expect(copy.nextAlertAt, isNull);
    expect(copy.snoozedUntil, isNull);
    n.dispose();
    copy.dispose();
  });

  test('daily snooze does not shift tomorrow selected clock time', () {
    final now = DateTime(2026, 10, 14, 9);
    final nextDay = DateTime(2026, 10, 15, 9);
    final n = note(reminder: nextDay, daily: true);
    n.snoozeReminder(const Duration(minutes: 10), now: now);
    final copy = Memo.fromJson(n.toJson());
    copy.consumeReminder(now.add(const Duration(minutes: 10)));
    expect(copy.snoozedUntil, isNull);
    expect(copy.reminder, nextDay);
    expect(copy.nextReminderAfter(nextDay), DateTime(2026, 10, 16, 9));
    n.dispose();
    copy.dispose();
  });

  test(
    'snooze consumes an overlapping daily occurrence without clock drift',
    () {
      final now = DateTime(2026, 10, 15, 8, 50);
      final n = note(reminder: DateTime(2026, 10, 15, 9), daily: true);
      n.snoozeReminder(const Duration(minutes: 30), now: now);
      expect(n.reminderDueAt(DateTime(2026, 10, 15, 9)), isFalse);
      n.consumeReminder(DateTime(2026, 10, 15, 9, 20));
      expect(n.reminder, DateTime(2026, 10, 16, 9));
      n.dispose();
    },
  );

  test('30-minute snooze suppresses the intervening 10-minute repeat', () {
    final now = DateTime(2026, 10, 14, 9);
    final n = note(
      reminder: now.add(const Duration(minutes: 10)),
      persistent: true,
    );
    n.snoozeReminder(const Duration(minutes: 30), now: now);
    expect(n.reminderDueAt(now.add(const Duration(minutes: 10))), isFalse);
    n.consumeReminder(now.add(const Duration(minutes: 10)));
    expect(n.snoozedUntil, now.add(const Duration(minutes: 30)));
    n.consumeReminder(now.add(const Duration(minutes: 30)));
    expect(n.reminder, now.add(const Duration(minutes: 40)));
    expect(n.persistent, isTrue);
    n.dispose();
  });

  test('user snooze can alert outside the study calendar and its end date', () {
    final n = Memo.fromJson({
      'id': 'calendar',
      'daily': true,
      'reminder': '2026-10-14T09:00:00',
      'repeatUntil': '2026-10-14',
      'reminderTimes': {'2026-10-14': '09:00'},
      'dailyPlan': {'2026-10-14': '09:00–10:00 学习'},
    });
    final now = DateTime(2026, 10, 14, 23, 50);
    n.snoozeReminder(const Duration(minutes: 30), now: now);
    final due = DateTime(2026, 10, 15, 0, 20);
    expect(n.calendarAllowsAlert(due), isFalse);
    expect(n.expiredAt(due), isTrue);
    expect(n.allowsReminderAlert(due), isTrue);
    n.consumeReminder(due);
    expect(n.nextAlertAt, isNull);
    n.dispose();
  });

  test('legacy soft-delete markers no longer hide retained records', () {
    final n = Memo.fromJson({
      'id': 'legacy-hidden',
      'body': '保留内容',
      'deletedAt': '2026-10-14T09:00:00',
    });
    expect(n.body, '保留内容');
    expect(n.toJson().containsKey('deletedAt'), isFalse);
    n.dispose();
  });

  test('only exact 10- and 30-minute snoozes are accepted', () {
    final n = note();
    for (final delay in [
      Duration.zero,
      const Duration(minutes: -10),
      const Duration(minutes: 20),
      const Duration(minutes: 10, seconds: 1),
    ]) {
      expect(() => n.snoozeReminder(delay), throwsArgumentError);
      expect(n.snoozedUntil, isNull);
    }
    n.snoozeReminder(const Duration(minutes: 10));
    expect(n.snoozedUntil, isNotNull);
    n.snoozeReminder(const Duration(minutes: 30));
    expect(n.snoozedUntil, isNotNull);
    n.dispose();
  });
}
