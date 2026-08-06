import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

/// A day's worth of wearable data, or null fields when unavailable.
class WearableSnapshot {
  const WearableSnapshot({
    this.stepsToday,
    this.restingHeartRate,
    this.sleepHoursLastNight,
  });

  final int? stepsToday;
  final double? restingHeartRate;
  final double? sleepHoursLastNight;

  bool get hasAnyData =>
      stepsToday != null || restingHeartRate != null || sleepHoursLastNight != null;

  static const empty = WearableSnapshot();
}

/// Thin wrapper around Health Connect (Android) / HealthKit (iOS — not yet
/// a platform in this project). Every method is best-effort: if the
/// platform doesn't support it, permission is denied, or Health Connect
/// isn't installed, calls fail silently rather than crashing the app —
/// same philosophy as PushService.
class HealthConnectService {
  final Health _health = Health();

  static const _types = [
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_ASLEEP,
  ];

  void _log(String msg) => dev.log(msg, name: 'health_connect.service');

  Future<bool> requestPermissions() async {
    try {
      await _health.configure();
      final has = await _health.hasPermissions(_types) ?? false;
      if (has) return true;
      return await _health.requestAuthorization(_types);
    } catch (e) {
      _log('requestPermissions failed (Health Connect unavailable?): $e');
      return false;
    }
  }

  Future<WearableSnapshot> fetchTodaySnapshot() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final steps = await _health.getTotalStepsInInterval(startOfDay, now);

      final points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: startOfDay.subtract(const Duration(hours: 12)), // catch overnight sleep
        endTime: now,
      );

      double? restingHr;
      final hrPoints = points
          .where((p) => p.type == HealthDataType.RESTING_HEART_RATE)
          .toList()
        ..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
      if (hrPoints.isNotEmpty) restingHr = _numeric(hrPoints.first.value);

      double? sleepHours;
      final sleepPoints =
          points.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
      if (sleepPoints.isNotEmpty) {
        final totalMinutes =
            sleepPoints.fold<double>(0, (a, p) => a + _numeric(p.value));
        sleepHours = totalMinutes / 60;
      }

      return WearableSnapshot(
        stepsToday: steps,
        restingHeartRate: restingHr,
        sleepHoursLastNight: sleepHours,
      );
    } catch (e) {
      _log('fetchTodaySnapshot failed: $e');
      return WearableSnapshot.empty;
    }
  }

  double _numeric(HealthValue v) =>
      v is NumericHealthValue ? v.numericValue.toDouble() : 0;
}

final healthConnectServiceProvider =
    Provider<HealthConnectService>((ref) => HealthConnectService());
