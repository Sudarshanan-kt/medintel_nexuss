import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo_ocr_cache.dart';
import '../domain/medical_report.dart';

/// Persistent SHA256-keyed prescription cache stored in SharedPreferences.
///
/// Flow:
///   1. Upload image → compute sha256 of bytes.
///   2. [lookup] checks here first — if the same image was uploaded before,
///      return the previously stored result immediately (no re-analysis needed).
///   3. After any analysis (demo match or offline fallback), call [persist] so
///      the next upload of the same image is recognised instantly.
///   4. [link] replaces a stored result with a pre-registered demo entry,
///      letting the user assign the correct medicines on first upload.
class RxLocalStore {
  static const _key = 'medintel_rx_sha256_store_v1';

  Future<Map<String, dynamic>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  /// Returns a stored [DemoOcrResult] for [sha256], or `null` if unseen.
  Future<DemoOcrResult?> lookup(String sha256) async {
    final store = await _load();
    final entry = store[sha256];
    if (entry == null) return null;
    try {
      return _resultFromMap((entry as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// Saves [result] keyed by [sha256].  Safe to call multiple times (idempotent).
  Future<void> persist(String sha256, DemoOcrResult result) async {
    final store = await _load();
    store[sha256] = _resultToMap(result);
    await _save(store);
  }

  /// Replaces any existing entry for [sha256] with [newResult].
  /// Used by the "Link prescription" UI to swap an offline-fallback result
  /// with the correct pre-extracted demo data.
  Future<void> link(String sha256, DemoOcrResult newResult) =>
      persist(sha256, newResult);

  // ── Serialisation ──────────────────────────────────────────────────────

  static Map<String, dynamic> _resultToMap(DemoOcrResult r) => {
        'id': r.id,
        'title': r.title,
        'confidence': r.confidence,
        'summary': r.summary,
        'medicines': r.medicines
            .map(
              (m) => {
                'name': m.name,
                'strength': m.strength,
                'dosageLine': m.dosageLine,
                'risk': m.risk,
                'riskNote': m.riskNote,
                'confidence': m.confidence,
              },
            )
            .toList(),
        'riskAnalysis': r.riskAnalysis,
        'insights': r.insights,
        'metrics': r.metrics
            .map(
              (m) => {
                'label': m.label,
                'value': m.value,
                'unit': m.unit,
                // JSON has no Infinity — store finite sentinels.
                'refLow': m.refLow.isFinite ? m.refLow : -1e12,
                'refHigh': m.refHigh.isFinite ? m.refHigh : 1e12,
              },
            )
            .toList(),
      };

  static DemoOcrResult _resultFromMap(Map<String, dynamic> m) {
    final meds = (m['medicines'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PrescriptionMedicine.fromJson)
        .toList();
    return DemoOcrResult(
      id: (m['id'] as String?) ?? 'local',
      title: (m['title'] as String?) ?? 'Prescription',
      confidence: (m['confidence'] as num?)?.toDouble() ?? 0.9,
      summary: (m['summary'] as String?) ?? '',
      medicines: meds,
      riskAnalysis:
          ((m['riskAnalysis'] as List?) ?? const []).map((e) => '$e').toList(),
      insights:
          ((m['insights'] as List?) ?? const []).map((e) => '$e').toList(),
      metrics: DemoOcrResult.metricsFromJsonList(m['metrics'] as List?),
    );
  }
}

final rxLocalStoreProvider = Provider<RxLocalStore>((ref) => RxLocalStore());
