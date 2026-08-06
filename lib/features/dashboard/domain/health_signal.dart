/// Where a [HealthSignal] originated. Kept distinct from each feature's own
/// domain models — this is purely a normalized shape for cross-feature
/// correlation, not a replacement for them.
enum HealthSignalSource {
  medicineRisk,
  reportFinding,
  reportMetric,
  wearable,
  vitalsJournal,
  adherence,
}

/// How concerning a signal is, on its own — independent of any correlation.
enum SignalSeverity { none, caution, alert }

/// A single normalized data point pulled from an otherwise-siloed feature
/// (scans, reports, wearables, the vitals journal, adherence logs), so
/// [CorrelationEngine] can look for patterns across all of them at once
/// instead of each feature only ever describing itself in isolation.
///
/// This never replaces a feature's own domain model — it's a read-only,
/// derived view built fresh each time `dashboardStateProvider` recomputes.
class HealthSignal {
  const HealthSignal({
    required this.source,
    required this.timestamp,
    required this.severity,
    this.numericValue,
    this.secondaryValue,
    this.label,
    this.refId,
  });

  final HealthSignalSource source;
  final DateTime timestamp;
  final SignalSeverity severity;

  /// The reading's primary value where applicable: a vital reading, an
  /// adherence day's taken count, a report metric's value, etc.
  final double? numericValue;

  /// Blood pressure's diastolic value, when [source] is
  /// [HealthSignalSource.vitalsJournal] and the reading is blood pressure.
  final double? secondaryValue;

  /// Human-readable tag identifying what this signal is about — a medicine
  /// name, a vital type name, a report metric label, etc.
  final String? label;

  /// id of the underlying record (scan id, report id, vital reading id...),
  /// so a correlated insight can link back to its source.
  final String? refId;
}
