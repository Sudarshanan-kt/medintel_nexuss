import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/reminders/data/web_alarm_scheduler.dart';

void main() {
  late WebAlarmScheduler scheduler;

  setUp(() => scheduler = WebAlarmScheduler());
  tearDown(() => scheduler.cancelAll());

  test('arms an alarm under the id it was given', () {
    scheduler.schedule(
      7,
      at: DateTime.now().add(const Duration(hours: 1)),
      title: 'Metformin',
      body: '500mg',
    );

    expect(scheduler.scheduledIds, contains(7));
  });

  test('scheduling the same id again replaces rather than stacks', () {
    final at = DateTime.now().add(const Duration(hours: 1));
    scheduler.schedule(7, at: at, title: 'a', body: 'b');
    scheduler.schedule(7, at: at, title: 'c', body: 'd');

    expect(scheduler.scheduledIds.where((id) => id == 7), hasLength(1));
  });

  test('cancel drops the alarm', () {
    scheduler.schedule(
      7,
      at: DateTime.now().add(const Duration(hours: 1)),
      title: 'a',
      body: 'b',
    );
    scheduler.cancel(7);

    expect(scheduler.scheduledIds, isNot(contains(7)));
  });

  test('cancelAll drops every alarm', () {
    final at = DateTime.now().add(const Duration(hours: 1));
    scheduler.schedule(1, at: at, title: 'a', body: 'b');
    scheduler.schedule(2, at: at, title: 'c', body: 'd');
    scheduler.cancelAll();

    expect(scheduler.scheduledIds, isEmpty);
  });

  test('cancelling an id that was never armed is harmless', () {
    expect(() => scheduler.cancel(999), returnsNormally);
  });

  testWidgets('a due alarm fires and clears itself', (tester) async {
    // A dose whose time has already passed still announces itself rather
    // than being dropped — the timer is armed at zero delay.
    scheduler.schedule(
      7,
      at: DateTime.now().subtract(const Duration(minutes: 5)),
      title: 'Metformin',
      body: '500mg',
    );
    expect(scheduler.scheduledIds, contains(7));

    await tester.pump(const Duration(milliseconds: 1));

    expect(scheduler.scheduledIds, isNot(contains(7)));
  });

  testWidgets('a daily alarm re-arms after firing', (tester) async {
    scheduler.schedule(
      7,
      at: DateTime.now().subtract(const Duration(minutes: 5)),
      title: 'Metformin',
      body: '500mg',
      repeatDaily: true,
    );

    await tester.pump(const Duration(milliseconds: 1));

    expect(scheduler.scheduledIds, contains(7));

    // Cancelled here rather than in tearDown: testWidgets fails a test that
    // ends with a timer outstanding, and re-arming for tomorrow is the whole
    // point of this one.
    scheduler.cancelAll();
  });
}
