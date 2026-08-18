import 'dart:async';
import 'dart:developer' as dev;

import '../../../core/services/notification_api.dart';

/// Fires medicine reminders in a browser, where there is no alarm manager.
///
/// On Android an alarm is handed to the OS and survives the app being closed;
/// `flutter_local_notifications` has no web implementation, so on web the
/// reminders feature simply did nothing — every scheduling call returned
/// early and no dose was ever announced.
///
/// This is the closest a page can get: a timer per alarm that shows a browser
/// notification when it comes due, re-arming itself a day later for a daily
/// reminder. Timers are keyed by the same alarm id the mobile path uses, so
/// cancelling works the same way on both.
///
/// The honest limit: **this only runs while the app is open.** A closed tab
/// has no timers, and a backgrounded one is throttled by the browser, so a
/// dose due overnight is not announced. Reminders that have to arrive with
/// the app shut need the server to send them — the push path — rather than
/// anything a page can schedule for itself. Nothing here pretends otherwise:
/// see `requestPermission`, which reports the real permission state so the UI
/// can say whether notifications will appear at all.
class WebAlarmScheduler {
  final Map<int, Timer> _timers = {};

  void _log(String msg) => dev.log(msg, name: 'alarm.web');

  /// Asks the browser for notification permission. Returns whether reminders
  /// can actually be shown.
  Future<bool> requestPermission() => ensureNotificationPermission();

  /// Shows [title]/[body] at [at], replacing any alarm already held under
  /// [id]. When [repeatDaily] is set the alarm re-arms 24 hours on.
  ///
  /// An [at] in the past fires on the next tick rather than being dropped, so
  /// a reminder scheduled for a moment ago still announces itself.
  void schedule(
    int id, {
    required DateTime at,
    required String title,
    required String body,
    bool repeatDaily = false,
  }) {
    cancel(id);

    final delay = at.difference(DateTime.now());
    _timers[id] = Timer(delay.isNegative ? Duration.zero : delay, () {
      showDeviceNotification(title, body);
      _timers.remove(id);
      if (repeatDaily) {
        schedule(
          id,
          at: at.add(const Duration(days: 1)),
          title: title,
          body: body,
          repeatDaily: true,
        );
      }
    });
    _log('scheduled id=$id in ${delay.inSeconds}s repeatDaily=$repeatDaily');
  }

  /// Drops the alarm held under [id], if any.
  void cancel(int id) {
    _timers.remove(id)?.cancel();
  }

  /// Drops every alarm. For sign-out, and for tests.
  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// Visible for tests: the alarm ids currently armed.
  Iterable<int> get scheduledIds => _timers.keys;
}
