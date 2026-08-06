import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/medicine.dart';
import 'reminders_controller.dart';

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// One calendar day's taken/missed outcome, derived purely from logged
/// [DoseLog] entries. Snoozed logs don't count either way — they're a
/// pending state, not a completed outcome. A day with zero taken/missed
/// logs is left untracked rather than treated as 0%, since there's no
/// separate "expected doses" model to say whether anything was even due.
class DayAdherence {
  const DayAdherence({
    required this.date,
    required this.taken,
    required this.missed,
  });

  final DateTime date;
  final int taken;
  final int missed;

  bool get hasData => taken + missed > 0;
  bool get isPerfect => hasData && missed == 0;
}

class AdherenceState {
  const AdherenceState({
    required this.weeklyPercent,
    required this.streakDays,
    required this.last7Days,
    required this.hasAnyData,
  });

  /// -1 when there are no tracked days in the last 7 to compute a % from.
  final double weeklyPercent;
  final int streakDays;

  /// Always length 7, oldest first, ending today.
  final List<DayAdherence> last7Days;
  final bool hasAnyData;

  static const empty = AdherenceState(
    weeklyPercent: -1,
    streakDays: 0,
    last7Days: [],
    hasAnyData: false,
  );
}

/// Pure adherence computation from a raw dose-log list — no Riverpod
/// dependency, so it can be reused for a caregiver viewing a linked
/// patient's logs (fetched remotely), not just the signed-in user's own.
AdherenceState computeAdherenceState(List<DoseLog> logs) {
  if (logs.isEmpty) return AdherenceState.empty;

  final today = _dayKey(DateTime.now());

  final byDay = <DateTime, DayAdherence>{};
  for (final log in logs) {
    if (log.status != 'taken' && log.status != 'missed') continue;
    final key = _dayKey(log.timestamp);
    final existing = byDay[key];
    byDay[key] = DayAdherence(
      date: key,
      taken: (existing?.taken ?? 0) + (log.status == 'taken' ? 1 : 0),
      missed: (existing?.missed ?? 0) + (log.status == 'missed' ? 1 : 0),
    );
  }
  if (byDay.isEmpty) return AdherenceState.empty;

  final last7 = [
    for (var i = 6; i >= 0; i--)
      byDay[today.subtract(Duration(days: i))] ??
          DayAdherence(
            date: today.subtract(Duration(days: i)),
            taken: 0,
            missed: 0,
          ),
  ];

  final tracked7 = last7.where((d) => d.hasData).toList();
  final weeklyPercent = tracked7.isEmpty
      ? -1.0
      : 100 *
          tracked7.fold<int>(0, (a, d) => a + d.taken) /
          tracked7.fold<int>(0, (a, d) => a + d.taken + d.missed);

  // Streak walks backward through the FULL log history (not capped at the
  // 7-day chart window), so a long streak is actually reflected. Today is
  // skipped if it has no data yet — a day still in progress shouldn't zero
  // out a streak built on prior days.
  var streak = 0;
  var cursor = today;
  while (true) {
    final day = byDay[cursor];
    if (day == null) {
      if (cursor == today) {
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }
      break;
    }
    if (!day.isPerfect) break;
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  return AdherenceState(
    weeklyPercent: weeklyPercent,
    streakDays: streak,
    last7Days: last7,
    hasAnyData: true,
  );
}

/// Derives real adherence stats from [remindersControllerProvider]'s dose
/// log history — no new data collection, same derivation pattern as
/// dashboard_controller.dart's DashboardState.
final adherenceStateProvider = Provider<AdherenceState>((ref) {
  final logs = ref.watch(remindersControllerProvider).logs;
  return computeAdherenceState(logs);
});
