import 'package:flutter/material.dart';

import '../../../shared/widgets/insight_card.dart';
import '../../vitals/domain/vital_reading.dart';
import '../domain/dashboard_insight.dart';
import '../domain/health_signal.dart';

/// Detects patterns across scan, report, wearable, vitals, and adherence
/// data that no single one of those features could see on its own — the
/// actual differentiator over single-purpose competitor apps (a medication
/// tracker only sees adherence; a lab-report app only sees one report at a
/// time; neither sees the other).
///
/// Deliberately **deterministic and rule-based, never LLM-driven**. An
/// LLM may only ever *phrase* an already-detected, already-verified
/// correlation more readably (see `insight_narrator.dart`) — it must never
/// be the thing deciding whether a correlation exists, since a
/// hallucinated causal claim about someone's medication and vitals is a
/// real safety risk, not a cosmetic bug.
abstract final class CorrelationEngine {
  static const _adherenceWindow = Duration(days: 14);
  static const _reportWindow = Duration(days: 30);
  static const _wearableWindow = Duration(days: 3);

  /// A later-vs-earlier rise of more than this fraction counts as a
  /// "worsening" trend. Deliberately conservative — this only ever flags a
  /// pattern for the user to mention to their doctor, never a diagnosis.
  static const _worseningThreshold = 0.08;

  static List<DashboardInsight> detect(List<HealthSignal> signals) {
    final now = DateTime.now();
    return [
      _adherenceVitalsCorrelation(signals, now),
      _vitalsReportCorrelation(signals, now),
      _wearableVitalsCorrelation(signals, now),
    ].whereType<DashboardInsight>().toList();
  }

  // ── Rule A: adherence dropped alongside a worsening vitals trend ───────

  static DashboardInsight? _adherenceVitalsCorrelation(
    List<HealthSignal> signals,
    DateTime now,
  ) {
    final adherenceReadings = signals
        .where(
          (s) =>
              s.source == HealthSignalSource.adherence &&
              now.difference(s.timestamp) <= _adherenceWindow,
        )
        .toList();
    // Fewer than 3 tracked days isn't enough to call anything a trend.
    if (adherenceReadings.length < 3) return null;

    final avgPercent = adherenceReadings.fold<double>(
          0,
          (a, s) => a + (s.numericValue ?? 0),
        ) /
        adherenceReadings.length;
    if (avgPercent >= 70) return null;

    for (final type in const [VitalType.bloodPressure, VitalType.bloodSugar]) {
      if (_isWorsening(signals, type.name, now, _adherenceWindow) == true) {
        return DashboardInsight(
          id: 'corr_adherence_${type.name}',
          icon: Icons.link_rounded,
          kind: InsightKind.correlatedAdherenceVitals,
          tone: InsightTone.alert,
          correlated: true,
          timestamp: now,
          params: {'percent': avgPercent.round(), 'vitalLabel': type.label},
        );
      }
    }
    return null;
  }

  // ── Rule B: a vitals trend echoed by an out-of-range lab metric ────────

  static DashboardInsight? _vitalsReportCorrelation(
    List<HealthSignal> signals,
    DateTime now,
  ) {
    if (_isWorsening(
          signals,
          VitalType.bloodSugar.name,
          now,
          _adherenceWindow,
        ) !=
        true) {
      return null;
    }

    const glucoseKeywords = ['gluc', 'sugar', 'a1c'];
    final match = signals.where(
      (s) =>
          s.source == HealthSignalSource.reportMetric &&
          s.severity != SignalSeverity.none &&
          now.difference(s.timestamp) <= _reportWindow &&
          glucoseKeywords.any(
            (k) => (s.label ?? '').toLowerCase().contains(k),
          ),
    );
    if (match.isEmpty) return null;

    return DashboardInsight(
      id: 'corr_vitals_report_${match.first.refId}',
      icon: Icons.link_rounded,
      kind: InsightKind.correlatedVitalsReport,
      tone: InsightTone.caution,
      correlated: true,
      timestamp: now,
      params: {
        'vitalLabel': VitalType.bloodSugar.label,
        'metricLabel': match.first.label ?? '',
      },
    );
  }

  // ── Rule C: a wearable signal coinciding with a worsening vital ────────

  static DashboardInsight? _wearableVitalsCorrelation(
    List<HealthSignal> signals,
    DateTime now,
  ) {
    final shortSleep = signals.any(
      (s) =>
          s.source == HealthSignalSource.wearable &&
          s.label == 'sleepHours' &&
          s.severity != SignalSeverity.none &&
          now.difference(s.timestamp) <= _wearableWindow,
    );
    final elevatedHr = signals.any(
      (s) =>
          s.source == HealthSignalSource.wearable &&
          s.label == 'restingHeartRate' &&
          s.severity != SignalSeverity.none &&
          now.difference(s.timestamp) <= _wearableWindow,
    );
    if (!shortSleep && !elevatedHr) return null;

    final bpOutOfRange = signals.any(
      (s) =>
          s.source == HealthSignalSource.vitalsJournal &&
          s.label == VitalType.bloodPressure.name &&
          s.severity != SignalSeverity.none &&
          now.difference(s.timestamp) <= _wearableWindow,
    );
    if (!bpOutOfRange) return null;

    return DashboardInsight(
      id: 'corr_wearable_vitals',
      icon: Icons.link_rounded,
      kind: InsightKind.correlatedWearableVitals,
      tone: InsightTone.caution,
      correlated: true,
      timestamp: now,
      params: {
        'vitalLabel': VitalType.bloodPressure.label,
        'wearableSignalLabel': shortSleep ? 'sleep' : 'heartRate',
      },
    );
  }

  // ── Shared trend helper ─────────────────────────────────────────────────

  /// True when [label]'s vitals readings within [window] show a rising
  /// trend (the later half of the window averages higher than the earlier
  /// half by more than [_worseningThreshold], relatively). Null when
  /// there isn't enough data (fewer than 2 readings) to judge a trend.
  static bool? _isWorsening(
    List<HealthSignal> signals,
    String label,
    DateTime now,
    Duration window,
  ) {
    final readings = signals
        .where(
          (s) =>
              s.source == HealthSignalSource.vitalsJournal &&
              s.label == label &&
              now.difference(s.timestamp) <= window,
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (readings.length < 2) return null;

    final mid = readings.length ~/ 2;
    final earlier = readings.sublist(0, mid);
    final later = readings.sublist(mid);
    final earlierAvg =
        earlier.fold<double>(0, (a, s) => a + (s.numericValue ?? 0)) /
            earlier.length;
    final laterAvg =
        later.fold<double>(0, (a, s) => a + (s.numericValue ?? 0)) /
            later.length;
    if (earlierAvg == 0) return null;
    return (laterAvg - earlierAvg) / earlierAvg > _worseningThreshold;
  }
}
