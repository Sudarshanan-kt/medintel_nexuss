import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../features/reminders/adherence_controller.dart';
import '../../features/reports/domain/medical_report.dart';
import '../../features/vitals/application/vitals_controller.dart';
import '../../features/vitals/domain/vital_reading.dart';

/// Builds and shares a one-page "doctor visit" PDF summary — the
/// shareable-for-appointments feature MyTherapy is known for, assembled
/// from data the app already tracks (adherence, vitals, reports). No new
/// data collection, purely a compiled export of what's already logged.
class PdfReportGenerator {
  const PdfReportGenerator._();

  static Future<Uint8List> build({
    required String patientName,
    required AdherenceState adherence,
    required VitalsState vitals,
    required List<MedicalReport> reports,
  }) async {
    final doc = pw.Document();
    final generatedAt = DateFormat.yMMMd().add_jm().format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MedIntel Nexus — Health Summary',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${patientName.isEmpty ? 'Patient' : patientName} · Generated $generatedAt',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          _sectionTitle('Vitals'),
          _vitalsTable(vitals),
          pw.SizedBox(height: 16),
          _sectionTitle('Medication adherence'),
          _adherenceBlock(adherence),
          pw.SizedBox(height: 16),
          _sectionTitle('Recent reports'),
          _reportsBlock(reports),
          pw.SizedBox(height: 16),
          pw.Text(
            'This summary reflects self-logged and app-recorded data. It is '
            'not a diagnosis — please review with a licensed clinician.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Opens the platform share/print sheet with the generated PDF — works on
  /// web (browser print dialog), mobile, and desktop via `printing`.
  static Future<void> shareOrPrint({
    required String patientName,
    required AdherenceState adherence,
    required VitalsState vitals,
    required List<MedicalReport> reports,
  }) async {
    final bytes = await build(
      patientName: patientName,
      adherence: adherence,
      vitals: vitals,
      reports: reports,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'medintel-health-summary.pdf',
    );
  }

  static pw.Widget _sectionTitle(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _vitalsTable(VitalsState vitals) {
    final rows = <List<String>>[
      for (final type in VitalType.values)
        if (vitals.latest(type) case final r?)
          [
            type.label,
            '${r.displayValue} ${type.unit}',
            DateFormat.yMMMd().format(r.timestamp),
          ],
    ];
    if (rows.isEmpty) {
      return pw.Text(
        'No vitals logged yet.',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: ['Vital', 'Latest reading', 'Logged'],
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 10),
      border: null,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  static pw.Widget _adherenceBlock(AdherenceState adherence) {
    if (!adherence.hasAnyData) {
      return pw.Text(
        'No adherence data logged yet.',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }
    final pct = adherence.weeklyPercent < 0
        ? '—'
        : '${adherence.weeklyPercent.round()}%';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Last 7 days: $pct doses taken on schedule'),
        pw.Text('Current streak: ${adherence.streakDays} day'
            '${adherence.streakDays == 1 ? '' : 's'}'),
      ],
    );
  }

  static pw.Widget _reportsBlock(List<MedicalReport> reports) {
    final recent = reports.take(5).toList();
    if (recent.isEmpty) {
      return pw.Text(
        'No reports uploaded yet.',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final r in recent)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${r.title}${r.hasRiskFinding ? '  (flagged)' : ''}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                ),
                pw.Text(
                  '${DateFormat.yMMMd().format(r.uploadedAt)}'
                  '${r.summary != null ? ' — ${r.summary}' : ''}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
