import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/reports_controller.dart';
import '../domain/medical_report.dart';

/// One value of one biomarker, pulled out of a [MedicalReport]'s OCR'd
/// [ReportMetric]s and paired with the report's upload date — the unit this
/// screen plots a trend line from.
class _BiomarkerPoint {
  const _BiomarkerPoint({
    required this.date,
    required this.metric,
  });
  final DateTime date;
  final ReportMetric metric;
}

/// Groups every metric across every analyzed report by a normalized label
/// (lowercased/trimmed, to tolerate OCR case variance like "HbA1c" vs
/// "hba1c") so the same biomarker measured in different reports lines up
/// into one series.
Map<String, List<_BiomarkerPoint>> _groupByBiomarker(
  List<MedicalReport> reports,
) {
  final grouped = <String, List<_BiomarkerPoint>>{};
  for (final report in reports) {
    if (report.status != ReportStatus.analyzed) continue;
    for (final metric in report.metrics) {
      final key = metric.label.trim().toLowerCase();
      if (key.isEmpty) continue;
      grouped
          .putIfAbsent(key, () => [])
          .add(_BiomarkerPoint(date: report.uploadedAt, metric: metric));
    }
  }
  for (final points in grouped.values) {
    points.sort((a, b) => a.date.compareTo(b.date));
  }
  return grouped;
}

/// Longitudinal view of a chosen lab value (e.g. HbA1c, LDL cholesterol)
/// across every report it's appeared in — MyChart's trend-chart pattern,
/// built from OCR data this app already extracts on upload.
class BiomarkerTrendScreen extends ConsumerStatefulWidget {
  const BiomarkerTrendScreen({super.key});

  @override
  ConsumerState<BiomarkerTrendScreen> createState() =>
      _BiomarkerTrendScreenState();
}

class _BiomarkerTrendScreenState extends ConsumerState<BiomarkerTrendScreen> {
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportsControllerProvider);
    final grouped = _groupByBiomarker(reports);
    // Only biomarkers with at least two readings make a meaningful trend.
    final trendable = Map.fromEntries(
      grouped.entries.where((e) => e.value.length >= 2),
    );

    final selected = _selectedKey != null && trendable.containsKey(_selectedKey)
        ? _selectedKey
        : (trendable.isNotEmpty ? trendable.keys.first : null);

    return GradientScaffold(
      appBar: AppBar(title: const Text('Lab Trends')),
      body: trendable.isEmpty
          ? _EmptyState(hasAnyMetrics: grouped.isNotEmpty)
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.lg,
                AppSpacing.gutter,
                AppSpacing.xxxl,
              ),
              children: [
                const SectionHeader(title: 'Choose a value'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final key in trendable.keys)
                      ChoiceChip(
                        label: Text(trendable[key]!.first.metric.label),
                        selected: key == selected,
                        onSelected: (_) => setState(() => _selectedKey = key),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                if (selected != null)
                  _TrendChartCard(points: trendable[selected]!),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyMetrics});
  final bool hasAnyMetrics;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          hasAnyMetrics
              ? 'Each of your lab values has only appeared once so far — '
                  'upload another report with the same test to see a trend.'
              : 'No lab values extracted yet. Upload a lab report to start '
                  'tracking trends over time.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({required this.points});
  final List<_BiomarkerPoint> points;

  @override
  Widget build(BuildContext context) {
    final label = points.first.metric.label;
    final unit = points.first.metric.unit;
    final latest = points.last.metric;

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].metric.value),
    ];
    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * 0.2 + 1;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.titleMd
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    Text(
                      '${points.length} readings',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${latest.value.toStringAsFixed(1)} $unit',
                    style: AppTypography.bodyLg.copyWith(
                      color: latest.isOutOfRange
                          ? AppColors.danger
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Latest',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: (points.length / 4).clamp(1, double.infinity),
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat.Md().format(points[i].date),
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        final outOfRange = points[index].metric.isOutOfRange;
                        return FlDotCirclePainter(
                          radius: 4,
                          color: outOfRange ? AppColors.danger : AppColors.primary,
                          strokeWidth: 0,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (latest.refLow.isFinite && latest.refHigh.isFinite) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Reference range: ${latest.refLow.toStringAsFixed(1)}–'
              '${latest.refHigh.toStringAsFixed(1)} $unit',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
