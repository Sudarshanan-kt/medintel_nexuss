import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/insight_card.dart';

/// What kind of insight this is — drives which localized template
/// [DashboardInsight.title]/[DashboardInsight.subtitle] resolve to. Kept
/// separate from free-form strings so insight text can be translated
/// (en/hi/ta) instead of hardcoded, while dynamic content that's already
/// user- or AI-generated in some language (a report summary, a risk note)
/// passes straight through untouched via [params].
enum InsightKind {
  /// A risk-flagged medicine from a scan. params: name, strength, riskNote?
  medicineFlagged,

  /// A report with a flagged finding. params: reportTitle, summary?
  reportFinding,

  /// An actionable tip generated from a report finding. params: headline, advice
  reportTip,

  /// Wearable-derived elevated resting heart rate. params: bpm (int)
  wearableHeartRate,

  /// Wearable-derived short sleep. params: hours (String, 1 decimal)
  wearableSleep,

  /// Generic-swap savings available. params: count (int), savingsLabel,
  /// brandName, genericName
  genericSwap,

  /// Fallback "here's your latest scan" when no risk insights exist yet.
  /// params: medicineCount (int), capturedAtLabel?
  recentScan,

  /// Adherence dropped alongside a worsening vitals trend in the same
  /// window. params: percent (int), vitalLabel
  correlatedAdherenceVitals,

  /// A vitals trend is echoed by an out-of-range report metric uploaded in
  /// the same window. params: vitalLabel, metricLabel
  correlatedVitalsReport,

  /// A wearable signal (short sleep / elevated resting HR) coincides with a
  /// worsening vitals reading. params: vitalLabel, wearableSignalLabel
  correlatedWearableVitals,
}

/// A single insight on the dashboard feed / health timeline.
///
/// [correlated] marks insights produced by [CorrelationEngine] — ones that
/// only exist because this app has scan, report, wearable, vitals, and
/// adherence data all in one place, unlike any single-purpose competitor
/// app. The UI tags these distinctly.
class DashboardInsight {
  const DashboardInsight({
    required this.id,
    required this.icon,
    required this.kind,
    required this.tone,
    this.params = const {},
    this.correlated = false,
    this.timestamp,
  });

  final String id;
  final IconData icon;
  final InsightKind kind;
  final InsightTone tone;
  final Map<String, Object> params;
  final bool correlated;

  /// When this insight concerns a specific point in time (used by the
  /// health timeline to place it in its date group). Null for insights
  /// that describe a standing state rather than an event (e.g. "generic
  /// swap available").
  final DateTime? timestamp;

  String title(AppLocalizations t) {
    switch (kind) {
      case InsightKind.medicineFlagged:
        return t.insightMedicineFlaggedTitle(
          params['name'] as String? ?? '',
          params['strength'] as String? ?? '',
        );
      case InsightKind.reportFinding:
        return params['reportTitle'] as String? ?? '';
      case InsightKind.reportTip:
        return params['headline'] as String? ?? '';
      case InsightKind.wearableHeartRate:
        return t.insightWearableHrTitle;
      case InsightKind.wearableSleep:
        return t.insightWearableSleepTitle;
      case InsightKind.genericSwap:
        return t.insightGenericSwapTitle(params['count'] as int? ?? 1);
      case InsightKind.recentScan:
        return t.insightRecentScanTitle(params['medicineCount'] as int? ?? 0);
      case InsightKind.correlatedAdherenceVitals:
        return t.insightCorrelatedAdherenceVitalsTitle;
      case InsightKind.correlatedVitalsReport:
        return t.insightCorrelatedVitalsReportTitle;
      case InsightKind.correlatedWearableVitals:
        return t.insightCorrelatedWearableVitalsTitle;
    }
  }

  String subtitle(AppLocalizations t) {
    switch (kind) {
      case InsightKind.medicineFlagged:
        return (params['riskNote'] as String?) ??
            t.insightMedicineFlaggedDefaultSubtitle;
      case InsightKind.reportFinding:
        return (params['summary'] as String?) ??
            t.insightReportDefaultSubtitle;
      case InsightKind.reportTip:
        return params['advice'] as String? ?? '';
      case InsightKind.wearableHeartRate:
        return t.insightWearableHrSubtitle(params['bpm'] as int? ?? 0);
      case InsightKind.wearableSleep:
        return t.insightWearableSleepSubtitle(
          params['hours'] as String? ?? '0',
        );
      case InsightKind.genericSwap:
        return t.insightGenericSwapSubtitle(
          params['savingsLabel'] as String? ?? '',
          params['brandName'] as String? ?? '',
          params['genericName'] as String? ?? '',
        );
      case InsightKind.recentScan:
        final captured = params['capturedAtLabel'] as String?;
        return captured != null
            ? t.insightRecentScanSubtitleCaptured(captured)
            : t.insightRecentScanSubtitleTapToView;
      case InsightKind.correlatedAdherenceVitals:
        return t.insightCorrelatedAdherenceVitalsSubtitle(
          params['percent'] as int? ?? 0,
          params['vitalLabel'] as String? ?? '',
        );
      case InsightKind.correlatedVitalsReport:
        return t.insightCorrelatedVitalsReportSubtitle(
          params['vitalLabel'] as String? ?? '',
          params['metricLabel'] as String? ?? '',
        );
      case InsightKind.correlatedWearableVitals:
        return t.insightCorrelatedWearableVitalsSubtitle(
          params['vitalLabel'] as String? ?? '',
          params['wearableSignalLabel'] as String? ?? '',
        );
    }
  }
}
