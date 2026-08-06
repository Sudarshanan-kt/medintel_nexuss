import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../vitals/domain/vital_reading.dart';
import '../application/dashboard_controller.dart';
import '../application/insight_narrator.dart';
import '../domain/health_signal.dart';

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// A chronological, date-grouped view across every health-tracking
/// feature — scans, reports, wearables, the vitals journal, and
/// adherence — with cross-signal correlations from [CorrelationEngine]
/// pinned at the top of whichever day they land on.
///
/// This is the flagship view: no single-purpose competitor app (a
/// medication tracker, a lab-report app, a symptom checker) can show this,
/// because none of them hold all five of these signal sources in one
/// place the way this app already does.
class HealthTimelineScreen extends ConsumerWidget {
  const HealthTimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final dash = ref.watch(dashboardStateProvider);

    final byDay = <DateTime, List<HealthSignal>>{};
    for (final signal in dash.signals) {
      final key = _dayKey(signal.timestamp);
      (byDay[key] ??= []).add(signal);
    }
    final correlatedByDay = <DateTime, List<DashboardInsight>>{};
    for (final insight in dash.insights.where((i) => i.correlated)) {
      final ts = insight.timestamp;
      if (ts == null) continue;
      (correlatedByDay[_dayKey(ts)] ??= []).add(insight);
    }

    final days = {...byDay.keys, ...correlatedByDay.keys}.toList()
      ..sort((a, b) => b.compareTo(a));

    return GradientScaffold(
      appBar: AppBar(title: Text(t.healthTimelineTitle)),
      body: days.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.tintBlue.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Text(
                  t.healthTimelineEmptyState,
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.lg,
                AppSpacing.gutter,
                AppSpacing.xxxl,
              ),
              physics: const BouncingScrollPhysics(),
              itemCount: days.length,
              itemBuilder: (context, i) {
                final day = days[i];
                return _DayGroup(
                  day: day,
                  signals: byDay[day] ?? const [],
                  correlated: correlatedByDay[day] ?? const [],
                  t: t,
                );
              },
            ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.signals,
    required this.correlated,
    required this.t,
  });

  final DateTime day;
  final List<HealthSignal> signals;
  final List<DashboardInsight> correlated;
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final sorted = [...signals]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.yMMMd().format(day),
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final insight in correlated) ...[
            InsightCard(
              icon: insight.icon,
              title: insight.title(t),
              subtitle: insight.subtitle(t),
              tone: insight.tone,
              trailing: _CorrelatedChip(t: t),
              subtitleWidget: NarratedInsightText(
                insightId: insight.id,
                fallback: insight.subtitle(t),
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final signal in sorted) ...[
            _SignalRow(signal: signal, t: t),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _CorrelatedChip extends StatelessWidget {
  const _CorrelatedChip({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tintViolet,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_rounded, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            t.insightCorrelatedBadge,
            style: AppTypography.caption
                .copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.signal, required this.t});
  final HealthSignal signal;
  final AppLocalizations t;

  ({IconData icon, String label, String? value}) _describe() {
    switch (signal.source) {
      case HealthSignalSource.medicineRisk:
        return (
          icon: Icons.medication_rounded,
          label: signal.label ?? t.timelineLabelMedicine,
          value: null,
        );
      case HealthSignalSource.reportFinding:
        return (
          icon: Icons.description_rounded,
          label: signal.label ?? t.timelineLabelReport,
          value: null,
        );
      case HealthSignalSource.reportMetric:
        return (
          icon: Icons.science_rounded,
          label: signal.label ?? t.timelineLabelMetric,
          value: signal.numericValue?.toStringAsFixed(1),
        );
      case HealthSignalSource.wearable:
        final isSleep = signal.label == 'sleepHours';
        return (
          icon: isSleep ? Icons.bedtime_rounded : Icons.favorite_rounded,
          label: isSleep
              ? t.timelineLabelSleep
              : t.timelineLabelRestingHeartRate,
          value: signal.numericValue == null
              ? null
              : isSleep
                  ? '${signal.numericValue!.toStringAsFixed(1)}h'
                  : '${signal.numericValue!.round()} bpm',
        );
      case HealthSignalSource.vitalsJournal:
        final type = VitalType.values.firstWhere(
          (v) => v.name == signal.label,
          orElse: () => VitalType.weight,
        );
        final value = type == VitalType.bloodPressure
            ? '${signal.numericValue?.toStringAsFixed(0)}/${signal.secondaryValue?.toStringAsFixed(0)}'
            : signal.numericValue?.toStringAsFixed(1);
        return (
          icon: Icons.favorite_rounded,
          label: type.label,
          value: '$value ${type.unit}',
        );
      case HealthSignalSource.adherence:
        return (
          icon: Icons.check_circle_rounded,
          label: t.timelineLabelAdherence,
          value: signal.numericValue == null
              ? null
              : '${signal.numericValue!.round()}%',
        );
    }
  }

  Color _severityColor() {
    switch (signal.severity) {
      case SignalSeverity.alert:
        return AppColors.danger;
      case SignalSeverity.caution:
        return AppColors.warning;
      case SignalSeverity.none:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _describe();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 24,
            decoration: BoxDecoration(
              color: _severityColor(),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(d.icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              d.label,
              style: AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (d.value != null)
            Text(
              d.value!,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
