import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/medical_report.dart';

/// A precomputed OCR analysis for a known demo prescription.
class DemoOcrResult {
  const DemoOcrResult({
    required this.id,
    required this.title,
    required this.confidence,
    required this.summary,
    required this.medicines,
    required this.riskAnalysis,
    required this.insights,
    this.metrics = const [],
  });

  final String id;
  final String title;
  final double confidence;
  final String summary;
  final List<PrescriptionMedicine> medicines;
  final List<String> riskAnalysis;
  final List<String> insights;

  /// Structured lab values (name, value, unit, reference range) for lab/
  /// imaging reports. Empty for prescriptions.
  final List<ReportMetric> metrics;

  static List<ReportMetric> metricsFromJsonList(List<dynamic>? raw) => [
        for (final e in (raw ?? const []).cast<Map<String, dynamic>>())
          ReportMetric(
            label: (e['label'] as String?) ?? '',
            value: (e['value'] as num?)?.toDouble() ?? 0,
            unit: (e['unit'] as String?) ?? '',
            refLow: (e['refLow'] as num?)?.toDouble() ?? double.negativeInfinity,
            refHigh: (e['refHigh'] as num?)?.toDouble() ?? double.infinity,
          ),
      ];

  /// Maps the risk-analysis lines onto [ReportFinding]s for the viewer.
  List<ReportFinding> get findings => [
        for (final line in riskAnalysis)
          ReportFinding(
            severity: medicines.any((m) => m.risk == 'severe')
                ? 'severe'
                : (medicines.any((m) => m.risk == 'moderate')
                    ? 'caution'
                    // For lab reports (no medicines), flag caution when any
                    // measured value falls outside its reference range.
                    : (metrics.any((m) => m.isOutOfRange)
                        ? 'caution'
                        : 'info')),
            text: line,
          ),
      ];

  bool get hasRisk => medicines.any((m) => m.risk != 'none');
}

/// Demo-ready OCR cache.
///
/// Loads precomputed OCR outputs (medicines, risk analysis, insights) for a
/// set of known demo prescriptions from a bundled JSON "database"
/// (`assets/demo/demo_ocr_cache.json`, mirrored in
/// `medintel-nexus-backend/demo_ocr_cache.json`). When a known demo image is
/// uploaded it returns the matching result so the flow behaves exactly like a
/// successful OCR analysis; unknown images return `null` so the caller falls
/// back to the normal pipeline.
///
/// Matching is by file name (primary — survives any re-encoding the picker
/// applies), then file-name stem, then optional sha256 / size if the caller
/// supplies them.
class DemoOcrCache {
  static const _assetPath = 'assets/demo/demo_ocr_cache.json';

  List<_Entry>? _entries;

  // [DEBUG] temporary tracing — remove after the upload flow is confirmed.
  void _log(String msg) => dev.log(msg, name: 'reports.demoCache');

  Future<List<_Entry>> _load() async {
    if (_entries != null) {
      _log('_load cache-hit entries=${_entries!.length}');
      return _entries!;
    }
    try {
      _log('_load reading asset $_assetPath');
      // Bound the bundle read so a stalled asset load can never hang the
      // analysis pipeline — fall back to an empty cache instead.
      final raw = await rootBundle
          .loadString(_assetPath)
          .timeout(const Duration(seconds: 4));
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final list = (doc['prescriptions'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      _entries = list.map(_Entry.fromJson).toList();
      _log('_load parsed entries=${_entries!.length}');
    } catch (e) {
      _log('_load ERROR (using empty cache): $e');
      _entries = const [];
    }
    return _entries!;
  }

  /// Returns all pre-registered prescriptions, for use in the "Link" UI.
  Future<List<DemoOcrResult>> listAll() async {
    final entries = await _load();
    return entries.map((e) => e.result).toList();
  }

  /// Returns the cached OCR result for a known demo prescription, or `null`.
  Future<DemoOcrResult?> lookup({
    String? fileName,
    String? sha256,
    int? sizeBytes,
  }) async {
    _log('lookup fileName=$fileName sha256=${sha256?.substring(0, sha256.length < 8 ? sha256.length : 8)}…');
    final entries = await _load();
    if (entries.isEmpty) {
      _log('lookup → empty cache, returning null');
      return null;
    }

    final name = fileName?.trim().toLowerCase();
    final stem = (name != null && name.contains('.'))
        ? name.substring(0, name.lastIndexOf('.'))
        : name;

    for (final e in entries) {
      final byHash = sha256 != null &&
          e.sha256 != null &&
          e.sha256!.toLowerCase() == sha256.toLowerCase();
      final byName = name != null && e.fileNames.contains(name);
      final byStem = stem != null && e.stems.contains(stem);
      if (byHash || byName || byStem) {
        _log('lookup MATCH id=${e.result.id} byHash=$byHash byName=$byName byStem=$byStem');
        return e.result;
      }
    }
    _log('lookup → no match across ${entries.length} entries');
    return null;
  }
}

class _Entry {
  _Entry({
    required this.fileNames,
    required this.stems,
    required this.sha256,
    required this.sizeBytes,
    required this.result,
  });

  final List<String> fileNames;
  final List<String> stems;
  final String? sha256;
  final int? sizeBytes;
  final DemoOcrResult result;

  static _Entry fromJson(Map<String, dynamic> j) {
    final match = (j['match'] as Map?)?.cast<String, dynamic>() ?? {};
    final meds = (j['medicines'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PrescriptionMedicine.fromJson)
        .toList();
    return _Entry(
      fileNames: ((match['fileNames'] as List?) ?? const [])
          .map((e) => '$e'.toLowerCase())
          .toList(),
      stems: ((match['stems'] as List?) ?? const [])
          .map((e) => '$e'.toLowerCase())
          .toList(),
      sha256: match['sha256'] as String?,
      sizeBytes: (match['sizeBytes'] as num?)?.toInt(),
      result: DemoOcrResult(
        id: (j['id'] as String?) ?? 'demo',
        title: (j['title'] as String?) ?? 'Prescription',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.9,
        summary: (j['summary'] as String?) ?? '',
        medicines: meds,
        riskAnalysis: ((j['riskAnalysis'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        insights:
            ((j['insights'] as List?) ?? const []).map((e) => '$e').toList(),
        metrics: DemoOcrResult.metricsFromJsonList(j['metrics'] as List?),
      ),
    );
  }
}

final demoOcrCacheProvider = Provider<DemoOcrCache>((ref) => DemoOcrCache());
