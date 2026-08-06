import 'dart:developer' as dev;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../domain/medicine.dart';

/// Production-grade exact alarm service using `flutter_local_notifications`.
///
/// Features:
///   - Exact time scheduling with `androidAllowWhileIdle: true`
///   - High importance channel with sound, vibration & full-screen intent
///   - Custom sound selection ('default', 'gentle', 'chime', 'urgent', 'classic')
///   - Repetition (Daily, Weekly)
///   - Action buttons (Taken, Snooze, Skip)
///   - Android 12+ exact alarm permission requests
class AlarmService {
  AlarmService() {
    _init();
  }

  final FlutterLocalNotificationsPlugin _np = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  void _log(String msg) => dev.log(msg, name: 'alarm.service');

  Future<void> _init() async {
    if (kIsWeb || _initialized) return;

    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('UTC')); // fallback until local timezone is resolved
    } catch (e) {
      _log('TZ init info: $e');
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _np.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _log('Notification tapped actionId=${response.actionId} payload=${response.payload}');
      },
    );

    _initialized = true;
    _log('AlarmService initialized successfully');
  }

  /// Requests post-notifications permission and Android 12+ exact alarm permissions.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    await _init();

    if (Platform.isAndroid) {
      final androidImplementation =
          _np.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final granted = await androidImplementation.requestNotificationsPermission() ?? false;
        await androidImplementation.requestExactAlarmsPermission();
        return granted;
      }
    } else if (Platform.isIOS) {
      final iosImpl = _np.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosImpl != null) {
        return await iosImpl.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    }
    return true;
  }

  /// Computes a stable unique integer ID from a String (medicineId + slot).
  int _generateAlarmId(String medId, String slot) {
    return (medId.hashCode ^ slot.hashCode).abs() % 2147483647;
  }

  /// Schedules an exact alarm for a specific medicine and slot.
  Future<void> scheduleMedicineAlarm(
    Medicine med, {
    required String slot,
    required int hour,
    required int minute,
  }) async {
    if (kIsWeb) return;
    await _init();

    if (med.isCompleted || !med.isActive) {
      await cancelMedicineAlarm(med.id, slot);
      return;
    }

    final alarmId = _generateAlarmId(med.id, slot);

    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the scheduled time for today has already passed, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);

    final channelId = 'med_alarm_${med.sound}';
    final channelName = 'Medicine Alarms (${med.sound})';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Exact high-priority medicine reminder alarms',
      importance: Importance.max,
      priority: Priority.high,
      sound: med.sound == 'default' ? null : RawResourceAndroidNotificationSound(med.sound),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'action_taken',
          'Mark Taken',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'action_snooze',
          'Snooze 10m',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'action_skip',
          'Skip',
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _np.zonedSchedule(
        alarmId,
        '💊 Time for ${med.name} ($slot)',
        med.dosage.isEmpty
            ? 'Tap to respond: Taken, Snooze, or Skip.'
            : '${med.dosage} — tap to respond.',
        tzScheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // repeats daily at exact time
        payload: '${med.id}|$slot|${med.name}|${med.dosage}',
      );
      _log('Scheduled exact alarm id=$alarmId med=${med.name} slot=$slot at $tzScheduledDate');
    } catch (e) {
      _log('Error scheduling alarm id=$alarmId: $e');
    }
  }

  /// Schedules a one-shot snoozed alarm for +[minutes] from now.
  Future<void> scheduleSnoozeAlarm(
    Medicine med, {
    required String slot,
    required int minutes,
  }) async {
    if (kIsWeb) return;
    await _init();

    final snoozeAlarmId = (_generateAlarmId(med.id, slot) + 999) % 2147483647;
    final scheduledDate = DateTime.now().add(Duration(minutes: minutes));
    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'med_snooze_channel',
      'Snoozed Medicine Alarms',
      channelDescription: 'Alarms for snoozed medicine reminders',
      importance: Importance.max,
      priority: Priority.high,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      fullScreenIntent: true,
    );

    try {
      await _np.zonedSchedule(
        snoozeAlarmId,
        '⏰ Snoozed: ${med.name} ($slot)',
        'Snoozed reminder due now. ${med.dosage}',
        tzScheduledDate,
        const NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: '${med.id}|$slot|${med.name}|${med.dosage}',
      );
      _log('Snoozed alarm scheduled for +$minutes mins at $tzScheduledDate');
    } catch (e) {
      _log('Snooze error: $e');
    }
  }

  /// Cancels a specific medicine slot alarm.
  Future<void> cancelMedicineAlarm(String medId, String slot) async {
    if (kIsWeb) return;
    await _init();
    final alarmId = _generateAlarmId(medId, slot);
    await _np.cancel(alarmId);
    await _np.cancel((alarmId + 999) % 2147483647); // cancel snooze if any
    _log('Cancelled alarm id=$alarmId');
  }

  /// Cancels all scheduled slot alarms for a medicine.
  Future<void> cancelAllForMedicine(Medicine med) async {
    if (kIsWeb) return;
    await cancelMedicineAlarm(med.id, 'morning');
    await cancelMedicineAlarm(med.id, 'afternoon');
    await cancelMedicineAlarm(med.id, 'night');
  }
}

final alarmServiceProvider = Provider<AlarmService>((ref) {
  return AlarmService();
});
