import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/insight_card.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../../reminders/adherence_controller.dart';
import '../../reports/application/reports_controller.dart';
import '../../reports/data/health_advice.dart';
import '../../reports/domain/medical_report.dart';
import '../../savings/application/savings_controller.dart';
import '../../scan/application/scans_controller.dart';
import '../../scan/domain/prescription_scan.dart';
import '../../vitals/application/vitals_controller.dart';
import '../../wearables/application/wearables_controller.dart';
import '../domain/dashboard_insight.dart';
import '../domain/health_signal.dart';
import 'correlation_engine.dart';

export '../domain/dashboard_insight.dart' show DashboardInsight, InsightKind;

/// Read-only snapshot of the dashboard, fully derived from the real scan,
/// report, vitals, and adherence stores. No fabricated demo data here.
class DashboardState {
  const DashboardState({
    required this.scansCount,
    required this.reportsCount,
    required this.medicineCount,
    required this.riskAlertCount,
    required this.recentScans,
    required this.recentReports,
    required this.insights,
    required this.signals,
  });

  final int scansCount;
  final int reportsCount;
  final int medicineCount;
  final int riskAlertCount;
  final List<PrescriptionScan> recentScans;
  final List<MedicalReport> recentReports;
  final List<DashboardInsight> insights;

  /// Every normalized signal this snapshot was derived from — the same
  /// list [CorrelationEngine] scans, and what the health timeline renders
  /// chronologically. Exposed so the timeline screen doesn't have to
  /// recompute it from five separate providers itself.
  final List<HealthSignal> signals;

  bool get isEmpty =>
      scansCount == 0 && reportsCount == 0 && medicineCount == 0;
}

/// Which "lens" the home dashboard is currently showing — the signed-in
/// user's own health, or one of the patients they care for. Purely a UI
/// toggle (like the veg/non-veg filter in food-delivery apps): it doesn't
/// change what data is fetched, only what the dashboard renders.
enum DashboardViewMode { me, caregiver }

/// Ephemeral — resets to [DashboardViewMode.me] on app restart, same as the
/// rest of the dashboard's in-memory session state.
final dashboardViewModeProvider =
    StateProvider<DashboardViewMode>((ref) => DashboardViewMode.me);

final dashboardStateProvider = Provider<DashboardState>((ref) {
  final scans = ref.watch(scansControllerProvider);
  final reports = ref.watch(reportsControllerProvider);
  final wearables = ref.watch(wearablesControllerProvider);
  final savings = ref.watch(savingsControllerProvider);
  final adherence = ref.watch(adherenceStateProvider);
  final vitals = ref.watch(vitalsControllerProvider);

  final medicineCount = scans.fold<int>(0, (a, s) => a + s.medicines.length);
  var riskAlerts = 0;
  for (final s in scans) {
    for (final m in s.medicines) {
      if (m.riskLevel != RiskLevel.none) riskAlerts++;
    }
  }
  if (reports.any((r) => r.hasRiskFinding)) riskAlerts++;

  final insights = <DashboardInsight>[];

  // ── Normalized cross-feature signal list ──────────────────────────────
  // Everything CorrelationEngine and the health timeline operate on. Built
  // once here so both consume the exact same snapshot the dashboard used.
  final signals = <HealthSignal>[
    for (final scan in scans)
      for (final m in scan.medicines)
        HealthSignal(
          source: HealthSignalSource.medicineRisk,
          timestamp: scan.capturedAt ?? DateTime.now(),
          severity: switch (m.riskLevel) {
            RiskLevel.none => SignalSeverity.none,
            RiskLevel.moderate => SignalSeverity.caution,
            RiskLevel.severe => SignalSeverity.alert,
          },
          label: m.name,
          refId: scan.id,
        ),
    for (final r in reports) ...[
      if (r.hasRiskFinding)
        HealthSignal(
          source: HealthSignalSource.reportFinding,
          timestamp: r.uploadedAt,
          severity: SignalSeverity.caution,
          label: r.title,
          refId: r.id,
        ),
      for (final metric in r.metrics)
        HealthSignal(
          source: HealthSignalSource.reportMetric,
          timestamp: r.uploadedAt,
          severity: metric.isOutOfRange
              ? SignalSeverity.caution
              : SignalSeverity.none,
          numericValue: metric.value,
          label: metric.label,
          refId: r.id,
        ),
    ],
    if (wearables.connected) ...[
      if (wearables.snapshot.restingHeartRate != null)
        HealthSignal(
          source: HealthSignalSource.wearable,
          timestamp: DateTime.now(),
          severity: wearables.snapshot.restingHeartRate! > 100
              ? SignalSeverity.caution
              : SignalSeverity.none,
          numericValue: wearables.snapshot.restingHeartRate,
          label: 'restingHeartRate',
        ),
      if (wearables.snapshot.sleepHoursLastNight != null)
        HealthSignal(
          source: HealthSignalSource.wearable,
          timestamp: DateTime.now(),
          severity: wearables.snapshot.sleepHoursLastNight! < 6
              ? SignalSeverity.caution
              : SignalSeverity.none,
          numericValue: wearables.snapshot.sleepHoursLastNight,
          label: 'sleepHours',
        ),
    ],
    for (final reading in vitals.readings)
      HealthSignal(
        source: HealthSignalSource.vitalsJournal,
        timestamp: reading.timestamp,
        severity:
            reading.isInNormalRange ? SignalSeverity.none : SignalSeverity.caution,
        numericValue: reading.value,
        secondaryValue: reading.secondaryValue,
        label: reading.type.name,
        refId: reading.id,
      ),
    for (final day in adherence.last7Days)
      if (day.hasData)
        HealthSignal(
          source: HealthSignalSource.adherence,
          timestamp: day.date,
          severity: day.isPerfect ? SignalSeverity.none : SignalSeverity.caution,
          numericValue: day.taken + day.missed == 0
              ? 0
              : 100 * day.taken / (day.taken + day.missed),
        ),
  ];

  // Risk-flagged medicines from the most recent scan.
  for (final scan in scans) {
    for (final m in scan.medicines.where(
      (m) => m.riskLevel != RiskLevel.none,
    )) {
      insights.add(
        DashboardInsight(
          id: '${scan.id}_${m.id}',
          icon: Icons.warning_amber_rounded,
          kind: InsightKind.medicineFlagged,
          params: {
            'name': m.name,
            'strength': m.strength,
            if (m.riskNote != null) 'riskNote': m.riskNote!,
          },
          tone: m.riskLevel == RiskLevel.severe
              ? InsightTone.alert
              : InsightTone.caution,
          timestamp: scan.capturedAt,
        ),
      );
    }
  }

  // Reports with findings.
  for (final r in reports.where((r) => r.hasRiskFinding)) {
    insights.add(
      DashboardInsight(
        id: 'rpt_${r.id}',
        icon: Icons.description_rounded,
        kind: InsightKind.reportFinding,
        params: {
          'reportTitle': r.title,
          if (r.summary != null) 'summary': r.summary!,
        },
        tone: InsightTone.caution,
        timestamp: r.uploadedAt,
      ),
    );

    // "How to reduce these" — actionable tips for each out-of-range value.
    for (final tip in HealthAdvice.forReport(r)) {
      insights.add(
        DashboardInsight(
          id: 'tip_${r.id}_${tip.label}',
          icon: Icons.favorite_rounded,
          kind: InsightKind.reportTip,
          params: {'headline': tip.headline, 'advice': tip.advice},
          tone: InsightTone.positive,
          timestamp: r.uploadedAt,
        ),
      );
    }
  }

  // Wearable-derived signals — only once the user has connected a device.
  // Non-diagnostic, same "visual cue, never a medical judgement" posture as
  // VitalReading.isInNormalRange.
  if (wearables.connected) {
    final snap = wearables.snapshot;
    final restingHr = snap.restingHeartRate;
    if (restingHr != null && restingHr > 100) {
      insights.add(
        DashboardInsight(
          id: 'wearable_hr',
          icon: Icons.favorite_rounded,
          kind: InsightKind.wearableHeartRate,
          params: {'bpm': restingHr.round()},
          tone: InsightTone.caution,
        ),
      );
    }
    final sleepHours = snap.sleepHoursLastNight;
    if (sleepHours != null && sleepHours < 6) {
      insights.add(
        DashboardInsight(
          id: 'wearable_sleep',
          icon: Icons.bedtime_rounded,
          kind: InsightKind.wearableSleep,
          params: {'hours': sleepHours.toStringAsFixed(1)},
          tone: InsightTone.caution,
        ),
      );
    }
  }

  // Generic-swap savings — once at least one scanned medicine has a
  // real (non-already-generic) swap available.
  final swaps = savings.actionable;
  if (swaps.isNotEmpty) {
    insights.add(
      DashboardInsight(
        id: 'savings',
        icon: Icons.savings_rounded,
        kind: InsightKind.genericSwap,
        params: {
          'count': swaps.length,
          'savingsLabel': swaps.first.savingsRangeLabel,
          'brandName': swaps.first.brandName,
          'genericName': swaps.first.genericName,
        },
        tone: InsightTone.positive,
      ),
    );
  }

  // Recent scan summary if no risk insights yet.
  if (insights.isEmpty && scans.isNotEmpty) {
    final s = scans.first;
    insights.add(
      DashboardInsight(
        id: 'scan_${s.id}',
        icon: Icons.medication_rounded,
        kind: InsightKind.recentScan,
        params: {
          'medicineCount': s.medicines.length,
          if (s.capturedAt != null)
            'capturedAtLabel': DateFormat.MMMd().add_jm().format(s.capturedAt!),
        },
        tone: InsightTone.neutral,
        timestamp: s.capturedAt,
      ),
    );
  }

  // ── Cross-signal correlations ──────────────────────────────────────────
  // The connective-tissue insights no single-purpose competitor app can
  // produce, because none of them hold scan + report + wearable + vitals +
  // adherence data in one place. Deterministic and rule-based on purpose —
  // see CorrelationEngine's own doc for why an LLM never drives this.
  insights.addAll(CorrelationEngine.detect(signals));

  return DashboardState(
    scansCount: scans.length,
    reportsCount: reports.length,
    medicineCount: medicineCount,
    riskAlertCount: riskAlerts,
    recentScans: scans.take(3).toList(),
    recentReports: reports.take(3).toList(),
    insights: insights.take(12).toList(),
    signals: signals,
  );
});
