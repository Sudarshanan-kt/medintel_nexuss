import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/pdf_report_generator.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../dashboard/application/insight_narrator.dart';
import '../../profile/application/profile_controller.dart';
import '../../reminders/adherence_controller.dart';
import '../../reports/application/reports_controller.dart';
import '../../wearables/application/wearables_controller.dart';
import '../application/vitals_controller.dart';
import '../domain/vital_reading.dart';

/// "Health Risk Insights" — the screen the home dashboard's quick action
/// used to point nowhere ("coming soon"). Combines the already-computed
/// risk insights feed (previously orphaned after the dashboard redesign
/// dropped its own insights section) with a new self-logged vitals
/// journal (blood pressure / weight / blood sugar) and a compiled summary
/// for doctor visits — MyTherapy's proven differentiator.
class HealthInsightsScreen extends ConsumerWidget {
  const HealthInsightsScreen({super.key});

  Future<void> _openAddSheet(BuildContext context, WidgetRef ref, VitalType type) {
    return showAppSheet<void>(
      context: context,
      builder: (_) => _AddVitalSheet(type: type),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final dash = ref.watch(dashboardStateProvider);
    final vitals = ref.watch(vitalsControllerProvider);
    final wearables = ref.watch(wearablesControllerProvider);

    return GradientScaffold(
      appBar: AppBar(title: const Text('Health Risk Insights')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.xxxl,
        ),
        physics: const BouncingScrollPhysics(),
        children: [
          SectionHeader(
            title: 'AI insights',
            actionLabel: t.healthTimelineViewFullLink,
            onAction: () => context.go(Routes.healthTimeline),
          ),
          const SizedBox(height: AppSpacing.md),
          if (dash.insights.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.tintBlue.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.outline),
              ),
              child: Text(
                'No insights yet. Scan a prescription or upload a report to get personalised risk analysis.',
                style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            for (final ins in dash.insights) ...[
              InsightCard(
                icon: ins.icon,
                title: ins.title(t),
                subtitle: ins.subtitle(t),
                tone: ins.tone,
                trailing: ins.correlated ? _CorrelatedBadge(t: t) : null,
                subtitleWidget: ins.correlated
                    ? NarratedInsightText(
                        insightId: ins.id,
                        fallback: ins.subtitle(t),
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.textSecondary),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
            ],

          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Vitals journal'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Log your own readings between checkups — trends here are shared with your doctor summary below.',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),

          for (final type in VitalType.values) ...[
            _VitalTypeCard(
              type: type,
              readings: vitals.byType(type),
              onAdd: () => _openAddSheet(context, ref, type),
              onDelete: (id) =>
                  ref.read(vitalsControllerProvider.notifier).deleteReading(id),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Wearable data'),
          const SizedBox(height: AppSpacing.md),
          _WearableCard(state: wearables),

          const SizedBox(height: AppSpacing.md),
          _DoctorSummaryCard(vitals: vitals),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// "Correlated" badge — marks insights CorrelationEngine derived from more
// than one data source, distinct from single-source insights.
// ─────────────────────────────────────────────────────────────────────────

class _CorrelatedBadge extends StatelessWidget {
  const _CorrelatedBadge({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
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
            style: AppTypography.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Per-vital-type card: latest reading + mini trend + add button
// ─────────────────────────────────────────────────────────────────────────

class _VitalTypeCard extends StatelessWidget {
  const _VitalTypeCard({
    required this.type,
    required this.readings,
    required this.onAdd,
    required this.onDelete,
  });

  final VitalType type;
  final List<VitalReading> readings;
  final VoidCallback onAdd;
  final ValueChanged<String> onDelete;

  IconData get _icon {
    switch (type) {
      case VitalType.bloodPressure:
        return Icons.favorite_rounded;
      case VitalType.weight:
        return Icons.monitor_weight_rounded;
      case VitalType.bloodSugar:
        return Icons.water_drop_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = readings.isEmpty ? null : readings.first;
    final recent = readings.take(7).toList().reversed.toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.tintRed,
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: AppColors.danger, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: AppTypography.bodyLg.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      latest != null
                          ? '${latest.displayValue} ${type.unit} · ${DateFormat.MMMd().add_jm().format(latest.timestamp)}'
                          : 'No readings yet',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
                onPressed: onAdd,
              ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 40,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final r in recent)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Tooltip(
                          message: '${r.displayValue} ${type.unit}',
                          child: Container(
                            height: r.isInNormalRange ? 16 : 32,
                            decoration: BoxDecoration(
                              color: r.isInNormalRange
                                  ? AppColors.success
                                  : AppColors.warning,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Add-reading bottom sheet
// ─────────────────────────────────────────────────────────────────────────

class _AddVitalSheet extends ConsumerStatefulWidget {
  const _AddVitalSheet({required this.type});
  final VitalType type;

  @override
  ConsumerState<_AddVitalSheet> createState() => _AddVitalSheetState();
}

class _AddVitalSheetState extends ConsumerState<_AddVitalSheet> {
  final _primaryCtrl = TextEditingController();
  final _secondaryCtrl = TextEditingController();

  @override
  void dispose() {
    _primaryCtrl.dispose();
    _secondaryCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_primaryCtrl.text.trim());
    if (value == null) return;
    final secondary = widget.type == VitalType.bloodPressure
        ? double.tryParse(_secondaryCtrl.text.trim())
        : null;

    ref.read(vitalsControllerProvider.notifier).addReading(
          type: widget.type,
          value: value,
          secondaryValue: secondary,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isBp = widget.type == VitalType.bloodPressure;
    // Sheets are expected to supply their own surface (showAppSheet doesn't
    // wrap content in a card) — same rounded-sheet pattern used elsewhere
    // (e.g. profile_sheets.dart's _SheetShell).
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Log ${widget.type.label.toLowerCase()}',
              style: AppTypography.titleMd.copyWith(color: AppColors.textPrimary, fontSize: 20),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (isBp)
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _primaryCtrl,
                      label: 'Systolic',
                      hint: '120',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppTextField(
                      controller: _secondaryCtrl,
                      label: 'Diastolic',
                      hint: '80',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              )
            else
              AppTextField(
                controller: _primaryCtrl,
                label: '${widget.type.label} (${widget.type.unit})',
                hint: widget.type == VitalType.weight ? '68' : '95',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save reading', onPressed: _save),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Wearable data — Health Connect (Android) / HealthKit. Opt-in, never
// silent: nothing is fetched until the user explicitly taps Connect.
// ─────────────────────────────────────────────────────────────────────────

class _WearableCard extends ConsumerWidget {
  const _WearableCard({required this.state});
  final WearablesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(wearablesControllerProvider.notifier);

    if (!state.connected) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect a wearable',
                    style: AppTypography.bodyLg.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Steps, resting heart rate and sleep from Health Connect feed into your risk picture.',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            IntrinsicWidth(
              child: SecondaryButton(
                label: state.loading ? '...' : 'Connect',
                expand: false,
                onPressed: state.loading ? null : notifier.connect,
              ),
            ),
          ],
        ),
      );
    }

    final snap = state.snapshot;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Today',
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: state.loading ? null : notifier.refresh,
              ),
            ],
          ),
          if (!snap.hasAnyData)
            Text(
              'No data available yet from Health Connect.',
              style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
            )
          else
            Row(
              children: [
                _WearableStat(
                  icon: Icons.directions_walk_rounded,
                  label: 'Steps',
                  value: snap.stepsToday?.toString() ?? '—',
                ),
                _WearableStat(
                  icon: Icons.favorite_rounded,
                  label: 'Resting HR',
                  value: snap.restingHeartRate != null
                      ? '${snap.restingHeartRate!.round()} bpm'
                      : '—',
                ),
                _WearableStat(
                  icon: Icons.bedtime_rounded,
                  label: 'Sleep',
                  value: snap.sleepHoursLastNight != null
                      ? '${snap.sleepHoursLastNight!.toStringAsFixed(1)}h'
                      : '—',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WearableStat extends StatelessWidget {
  const _WearableStat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.bodyLg.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Doctor-visit summary — compiled from the latest reading of each type
// ─────────────────────────────────────────────────────────────────────────

class _DoctorSummaryCard extends ConsumerStatefulWidget {
  const _DoctorSummaryCard({required this.vitals});
  final VitalsState vitals;

  @override
  ConsumerState<_DoctorSummaryCard> createState() => _DoctorSummaryCardState();
}

class _DoctorSummaryCardState extends ConsumerState<_DoctorSummaryCard> {
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final profile = ref.read(profileControllerProvider);
      await PdfReportGenerator.shareOrPrint(
        patientName: profile.personal.fullName,
        adherence: ref.read(adherenceStateProvider),
        vitals: widget.vitals,
        reports: ref.read(reportsControllerProvider),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate the summary. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vitals = widget.vitals;
    final hasAny = VitalType.values.any((t) => vitals.latest(t) != null);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.14), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize_rounded, color: AppColors.textPrimary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Summary for your doctor',
                style: AppTypography.titleMd.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasAny)
            Text(
              'Log at least one reading to build a shareable summary.',
              style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
            )
          else
            for (final type in VitalType.values)
              if (vitals.latest(type) case final r?)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          type.label,
                          style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      Text(
                        '${r.displayValue} ${type.unit}',
                        style: AppTypography.bodyLg.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: _sharing ? 'Preparing…' : 'Share with doctor (PDF)',
            icon: Icons.picture_as_pdf_rounded,
            onPressed: _sharing ? null : _share,
          ),
        ],
      ),
    );
  }
}
