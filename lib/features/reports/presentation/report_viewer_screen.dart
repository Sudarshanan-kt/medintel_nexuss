import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../application/reports_controller.dart';
import '../data/health_advice.dart';
import '../domain/medical_report.dart';

/// Crash-proof report viewer.
///
/// Fallback logic (correct):
///   - `found == null` → report not yet in state → show demo placeholder.
///   - `status == uploading || processing` → show loading shimmer.
///   - `status == analyzed` → ALWAYS render `found`'s own data, never demo.
///     (Imaging / discharge / prescription reports may legitimately have no
///      metrics — that's fine; just those sections are absent.)
class ReportViewerScreen extends ConsumerWidget {
  const ReportViewerScreen({super.key, required this.reportId});
  final String reportId;

  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _primary = Color(0xFF2563EB);
  static const _danger = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsControllerProvider);

    MedicalReport? found;
    for (final r in reports) {
      if (r.id == reportId) {
        found = r;
        break;
      }
    }

    final bool isAnalysing = found?.status == ReportStatus.uploading ||
        found?.status == ReportStatus.processing;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(Routes.reports),
        ),
        title: Text(
          found?.typeLabel ?? 'Report',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (found != null)
            PopupMenuButton<_ViewerAction>(
              icon: const Icon(Icons.more_vert),
              onSelected: (action) => _onAction(context, ref, found!, action),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _ViewerAction.rename,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _ViewerAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                    title: Text('Delete', style: TextStyle(color: Color(0xFFDC2626))),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: found == null
          ? _buildNotFound()
          : isAnalysing
              ? _buildLoading(found)
              : _buildContent(context, ref, found),
    );
  }

  // ── Action handlers ───────────────────────────────────────────────────────

  void _onAction(
    BuildContext context,
    WidgetRef ref,
    MedicalReport report,
    _ViewerAction action,
  ) {
    switch (action) {
      case _ViewerAction.rename:
        _showRenameDialog(context, ref, report);
      case _ViewerAction.delete:
        _showDeleteDialog(context, ref, report);
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    MedicalReport report,
  ) async {
    final ctrl = TextEditingController(text: report.title);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename report'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Report name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      ref
          .read(reportsControllerProvider.notifier)
          .rename(report.id, ctrl.text.trim());
    }
    ctrl.dispose();
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    MedicalReport report,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete report?'),
        content: Text('"${report.title}" will be removed from your records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(reportsControllerProvider.notifier).delete(report.id);
      context.go(Routes.reports);
    }
  }

  // ── States ────────────────────────────────────────────────────────────────

  Widget _buildNotFound() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 48, color: Color(0xFF64748B)),
            SizedBox(height: 12),
            Text(
              'Loading report…',
              style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );

  Widget _buildLoading(MedicalReport report) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'AI analysis in progress…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0369A1),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                  'We are extracting key values and generating your summary. '
                  'This usually takes 10–15 seconds.',
                  style: TextStyle(fontSize: 13, color: _muted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    MedicalReport report,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        // ── Header card ──────────────────────────────────────────────────
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${report.typeLabel}'
                '${report.fileRef != null ? ' · ${report.fileRef!.split('/').last}' : ''}',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'Analysis Complete',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── AI Summary ───────────────────────────────────────────────────
        if ((report.summary ?? '').isNotEmpty) ...[
          _header('AI Summary'),
          _card(
            Text(
              report.summary!,
              style: const TextStyle(fontSize: 14, height: 1.5, color: _ink),
            ),
          ),
        ],

        // ── Lab Findings ─────────────────────────────────────────────────
        if (report.metrics.isNotEmpty) ...[
          _header('Lab Findings'),
          _card(
            Column(
              children: [for (final m in report.metrics) _metricRow(m)],
            ),
          ),
        ],

        // ── Risk Analysis ────────────────────────────────────────────────
        if (report.findings.isNotEmpty) ...[
          _header('Risk Analysis'),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in report.findings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: f.severity == 'caution' || f.severity == 'severe'
                              ? _danger
                              : _primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            f.text,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: _ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        // ── How to improve / reduce ──────────────────────────────────────
        if (HealthAdvice.forReport(report).isNotEmpty) ...[
          _header('How to reduce these'),
          for (final tip in HealthAdvice.forReport(report))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x142563EB),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tip.direction.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: _primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tip.headline,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tip.advice,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4, left: 4),
            child: Text(
              'General wellness guidance — always confirm with your doctor.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: _muted.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],

        // ── Insights ─────────────────────────────────────────────────────
        if (report.insights.isNotEmpty) ...[
          _header('Insights'),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in report.insights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '•  ',
                          style: TextStyle(fontSize: 14, color: _primary),
                        ),
                        Expanded(
                          child: Text(
                            i,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: _ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        // ── Empty state for reports with no extractable data ─────────────
        if ((report.summary ?? '').isEmpty &&
            report.metrics.isEmpty &&
            report.findings.isEmpty &&
            report.insights.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _card(
              const Column(
                children: [
                  Icon(Icons.info_outline_rounded, size: 40, color: Color(0xFF64748B)),
                  SizedBox(height: 12),
                  Text(
                    'No structured data extracted',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'This report type may not produce lab values. '
                    'The full document is stored in your library.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _header(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: _muted,
          ),
        ),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );

  Widget _metricRow(ReportMetric m) {
    final out = m.isOutOfRange;
    final hasLow = m.refLow.isFinite && m.refLow > -1e11;
    final hasHigh = m.refHigh.isFinite && m.refHigh < 1e11;
    String fmt(double v) {
      if (v.isInfinite) return '';
      final r = v.roundToDouble();
      return v == r ? r.toStringAsFixed(0) : v.toString();
    }

    String range;
    if (hasLow && hasHigh) {
      range = '${fmt(m.refLow)}–${fmt(m.refHigh)}';
    } else if (hasHigh) {
      range = '< ${fmt(m.refHigh)}';
    } else if (hasLow) {
      range = '> ${fmt(m.refLow)}';
    } else {
      range = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.label,
                  style: const TextStyle(fontSize: 14, color: _ink),
                ),
                if (range.isNotEmpty)
                  Text(
                    'Ref $range${m.unit.isEmpty ? '' : ' ${m.unit}'}',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${fmt(m.value)}${m.unit.isEmpty ? '' : ' ${m.unit}'}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: out ? _danger : _ink,
                ),
              ),
              if (out)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0x1FDC2626),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    m.value > m.refHigh ? 'High' : 'Low',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _danger,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ViewerAction { rename, delete }

