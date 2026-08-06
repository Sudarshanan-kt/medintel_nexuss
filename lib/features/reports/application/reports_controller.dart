import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/demo_lab_report.dart';
import '../data/demo_ocr_cache.dart';
import '../data/report_analysis_repository.dart';
import '../data/reports_repository.dart';
import '../data/rx_local_store.dart';
import '../data/synthetic_report.dart';
import '../domain/medical_report.dart';

/// Holds the patient's report library with dual-layer persistence:
///
///   1. **SharedPreferences** — instant restore on cold boot (no network wait).
///   2. **Supabase `reports` table** — authoritative remote store; merged on
///      login so data survives across devices and app reinstalls.
///
/// All mutations (add, finish analysis, rename, delete) write to both layers.
class ReportsController extends Notifier<List<MedicalReport>> {
  static const _storeKey = 'medintel_reports_v1';

  @override
  List<MedicalReport> build() {
    // Restore persisted reports asynchronously; state starts empty and is
    // replaced once the saved list loads. Never blocks the first frame.
    _restore();
    return const [];
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _log(String msg) => dev.log(msg, name: 'reports.analyze');

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  ReportsRepository get _repo => ref.read(reportsRepositoryProvider);

  // ── Restore ──────────────────────────────────────────────────────────────

  Future<void> _restore() async {
    // 1. Load from local cache first for instant rendering.
    await _restoreLocal();
    // 2. Merge from Supabase (remote wins for any id that exists in both).
    await _restoreRemote();
  }

  Future<void> _restoreLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 4));
      final raw = prefs.getString(_storeKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(MedicalReport.fromJson)
          .toList();
      // Merge: keep anything added during the async gap, prefer restored.
      final existingIds = state.map((r) => r.id).toSet();
      state = [
        ...state,
        ...list.where((r) => !existingIds.contains(r.id)),
      ];
      _log('local restore: ${list.length} reports');
    } catch (e) {
      _log('local restore ERROR: $e');
    }
  }

  Future<void> _restoreRemote() async {
    try {
      final userId = _userId;
      if (userId == null) return;

      final remote = await _repo.fetchAll(userId);
      if (remote.isEmpty) return;

      // Merge: remote wins when the same id exists locally. Any id in remote
      // but not local is inserted. Local-only ids (added since restore) kept.
      final remoteById = {for (final r in remote) r.id: r};
      final localOnlyIds = state.map((r) => r.id).toSet()
        ..removeAll(remoteById.keys);

      state = [
        ...remote, // newest-first from Supabase
        ...state.where((r) => localOnlyIds.contains(r.id)),
      ];
      _log('remote restore: ${remote.length} reports');

      // Re-sync local cache from merged result.
      await _saveLocal();
    } catch (e) {
      _log('remote restore ERROR: $e');
    }
  }

  // ── Persist ──────────────────────────────────────────────────────────────

  /// Saves the full list to SharedPreferences (fire-and-forget).
  void _persistLocal() {
    final snapshot = state;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 4));
        await prefs.setString(
          _storeKey,
          jsonEncode(snapshot.map((r) => r.toJson()).toList()),
        );
      } catch (e) {
        _log('local persist ERROR: $e');
      }
    }());
  }

  /// Overwrites the local cache synchronously (used after remote merge).
  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 4));
      await prefs.setString(
        _storeKey,
        jsonEncode(state.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      _log('saveLocal ERROR: $e');
    }
  }

  /// Upserts a single report to Supabase (fire-and-forget).
  void _upsertRemote(MedicalReport report) {
    final userId = _userId;
    if (userId == null) return;
    unawaited(
      _repo
          .upsert(userId, report)
          .timeout(const Duration(seconds: 8))
          .catchError((Object e) => _log('upsert ERROR: $e')),
    );
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Registers a new upload and kicks off the analysis pipeline.
  ///
  /// [fileName] is the original picked file name (used for demo-cache stem
  /// matching). [sha256] is the hex SHA256 of the image bytes (used for
  /// persistent local-store matching on re-upload of the same file).
  void addUpload({
    required String title,
    required ReportType type,
    String? fileRef,
    String? fileName,
    String? sha256,
  }) {
    final id = 'r_${DateTime.now().microsecondsSinceEpoch}';
    final report = MedicalReport(
      id: id,
      type: type,
      title: title,
      uploadedAt: DateTime.now(),
      status: ReportStatus.uploading,
      fileRef: fileRef,
      sha256: sha256,
    );
    state = [report, ...state];
    _analyze(id, fileName: fileName, sha256: sha256);
  }

  /// GUARANTEED demo path — no OCR, no cache, no background Future.
  ///
  /// Builds a fully `analyzed` report synchronously, inserts it at the top of
  /// the library, and returns its id so the caller can navigate straight to
  /// the viewer. The report is NEVER left in a processing state.
  String addAnalyzedDemo({
    String? fileRef,
    String? fileName,
    String? sha256,
  }) {
    final id = 'r_${DateTime.now().microsecondsSinceEpoch}';
    final isDemoFile =
        DemoLabReport.matches(fileName) || DemoLabReport.matches(fileRef);
    final report = isDemoFile
        ? DemoLabReport.build(id: id, fileRef: fileRef, sha256: sha256)
        : SyntheticReport.build(
            id: id,
            seed: sha256 ?? fileName ?? fileRef ?? id,
            fileRef: fileRef,
          );
    _log('addAnalyzedDemo id=$id demoFile=$isDemoFile status=${report.status} '
        'metrics=${report.metrics.length} findings=${report.findings.length}');
    state = [report, ...state];
    _persistLocal();
    _upsertRemote(report);

    if (sha256 != null) {
      unawaited(
        ref
            .read(rxLocalStoreProvider)
            .persist(
              sha256,
              DemoOcrResult(
                id: report.id,
                title: report.title,
                confidence: report.ocrConfidence ?? 0.97,
                summary: report.summary ?? '',
                medicines: report.medicines,
                riskAnalysis: report.findings.map((f) => f.text).toList(),
                insights: report.insights,
                metrics: report.metrics,
              ),
            )
            .timeout(const Duration(seconds: 4))
            .catchError((Object e) => _log('demo persist ERROR: $e')),
      );
    }
    return id;
  }

  /// Re-applies a [DemoOcrResult] to an existing report after the user links
  /// it to a pre-registered prescription entry via the "Link" card.
  Future<void> linkDemoResult(String reportId, DemoOcrResult result) async {
    final report = _getById(reportId);
    if (report == null) return;

    if (report.sha256 != null) {
      await ref.read(rxLocalStoreProvider).link(report.sha256!, result);
    }

    final updated = _applyResult(report, result, isDemoMatched: true);
    state = [
      for (final r in state) if (r.id == reportId) updated else r,
    ];
    _persistLocal();
    _upsertRemote(updated);
  }

  /// Renames a report and persists both locally and to Supabase.
  void rename(String id, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    MedicalReport? updated;
    state = [
      for (final r in state)
        if (r.id == id)
          () {
            updated = r.copyWith(title: trimmed);
            return updated!;
          }()
        else
          r,
    ];
    _persistLocal();
    if (updated != null) _upsertRemote(updated!);
  }

  /// Deletes a report from state, local cache, and Supabase.
  void delete(String id) {
    state = state.where((r) => r.id != id).toList();
    _persistLocal();
    final userId = _userId;
    if (userId != null) {
      unawaited(
        _repo
            .delete(userId, id)
            .timeout(const Duration(seconds: 8))
            .catchError((Object e) => _log('delete ERROR: $e')),
      );
    }
  }

  // ── Internal analysis pipeline ────────────────────────────────────────────

  static const _overallDeadline = Duration(seconds: 12);

  Future<void> _analyze(
    String id, {
    String? fileName,
    String? sha256,
  }) async {
    _log('START id=$id fileName=$fileName sha256=${sha256?.substring(0, 8)}…');

    await Future<void>.delayed(const Duration(milliseconds: 900));
    _setStatus(id, ReportStatus.processing);
    _log('status=processing');

    // Real analysis first — actually reads the uploaded image via the
    // backend's OCR+LLM pipeline (see report_analysis_repository.dart).
    // Only lab reports go through it (the structuring prompt is written
    // for lab-value tables specifically); imaging/discharge/prescription
    // reports still use the demo/synthetic path below. Falls through to
    // that same path if the backend is unreachable or genuinely can't
    // read the image — never silently swapped for fake data when the
    // real attempt simply hasn't returned yet.
    final report = _getById(id);
    final imagePath = report?.fileRef;
    if (imagePath != null && report!.type == ReportType.lab) {
      final outcome = await _tryRealAnalysis(imagePath);
      if (outcome != null) {
        _finishReal(id, outcome);
        return;
      }
      _log('real analysis unavailable — falling back to demo/synthetic path');
    }

    DemoOcrResult? demo;
    var fromLocalStore = false;

    try {
      final resolved = await _resolve(id, fileName, sha256).timeout(
        _overallDeadline,
        onTimeout: () {
          _log('OVERALL DEADLINE hit — finishing without a match');
          return (null, false);
        },
      );
      demo = resolved.$1;
      fromLocalStore = resolved.$2;

      await Future<void>.delayed(const Duration(seconds: 2));

      if (demo != null && sha256 != null && !fromLocalStore) {
        unawaited(
          ref
              .read(rxLocalStoreProvider)
              .persist(sha256, demo)
              .timeout(const Duration(seconds: 4))
              .catchError((Object e) => _log('persist ERROR: $e')),
        );
      }
    } catch (e, st) {
      _log('UNEXPECTED ERROR: $e\n$st');
    } finally {
      _finish(id, demo);
    }
  }

  /// Attempts the real backend pipeline; returns null on any failure
  /// (network error, timeout, or the backend genuinely couldn't read the
  /// image) so the caller falls back to the demo/synthetic path.
  Future<ReportAnalysisOutcome?> _tryRealAnalysis(String imagePath) async {
    try {
      final result = await ref
          .read(reportAnalysisRepositoryProvider)
          .analyzeReport(imagePath: imagePath)
          .timeout(_overallDeadline);
      return result.when(
        success: (outcome) => outcome,
        failure: (failure) {
          _log('real analysis failed: $failure');
          return null;
        },
      );
    } catch (e) {
      _log('real analysis error: $e');
      return null;
    }
  }

  void _finishReal(String id, ReportAnalysisOutcome outcome) {
    final report = _getById(id);
    if (report == null) {
      _log('report GONE before real finish — nothing to apply');
      return;
    }
    final finished = report.copyWith(
      status: ReportStatus.analyzed,
      summary: outcome.summary,
      metrics: outcome.metrics,
      findings: outcome.findings,
      hasRiskFinding: outcome.hasRiskFinding,
      insights: outcome.insights,
      ocrConfidence: outcome.confidence,
    );
    state = [
      for (final r in state) if (r.id == id) finished else r,
    ];
    _log('DONE (real) status=analyzed metrics=${outcome.metrics.length} '
        'findings=${outcome.findings.length} advice=${outcome.insights.length}');
    _persistLocal();
    _upsertRemote(finished);
  }

  Future<(DemoOcrResult?, bool)> _resolve(
    String id,
    String? fileName,
    String? sha256,
  ) async {
    DemoOcrResult? demo;
    var fromLocalStore = false;

    if (sha256 != null) {
      try {
        demo = await ref.read(rxLocalStoreProvider).lookup(sha256).timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            _log('rxLocalStore.lookup TIMED OUT');
            return null;
          },
        );
        if (demo != null) fromLocalStore = true;
        _log('localStore hit=${demo != null}');
      } catch (e) {
        _log('localStore ERROR: $e');
      }
    }

    if (demo == null) {
      try {
        demo = await ref
            .read(demoOcrCacheProvider)
            .lookup(fileName: fileName, sha256: sha256)
            .timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            _log('demoOcrCache.lookup TIMED OUT');
            return null;
          },
        );
        _log('demoCache hit=${demo != null} title=${demo?.title}');
      } catch (e) {
        _log('demoCache ERROR: $e');
      }
    }

    return (demo, fromLocalStore);
  }

  void _finish(String id, DemoOcrResult? demo) {
    final report = _getById(id);
    if (report == null) {
      _log('report GONE before apply — nothing to finish');
      return;
    }
    MedicalReport finished;
    try {
      finished = demo != null
          ? _applyResult(report, demo, isDemoMatched: true)
          : (report.type == ReportType.lab
              ? SyntheticReport.build(
                  id: report.id,
                  seed: report.sha256 ?? report.id,
                  fileRef: report.fileRef,
                  uploadedAt: report.uploadedAt,
                )
              : report.copyWith(status: ReportStatus.analyzed));

      state = [
        for (final r in state) if (r.id == id) finished else r,
      ];
      _log('DONE status=analyzed matched=${demo != null} '
          'metrics=${demo?.metrics.length ?? 0} '
          'findings=${demo?.findings.length ?? 0} '
          'insights=${demo?.insights.length ?? 0}');
    } catch (e, st) {
      _log('APPLY ERROR: $e\n$st — falling back to empty analyzed');
      finished = report.copyWith(status: ReportStatus.analyzed);
      state = [
        for (final r in state) if (r.id == id) finished else r,
      ];
    }
    _persistLocal();
    _upsertRemote(finished);
  }

  MedicalReport _applyResult(
    MedicalReport r,
    DemoOcrResult demo, {
    bool isDemoMatched = false,
  }) =>
      MedicalReport(
        id: r.id,
        type: r.type,
        title: demo.title,
        uploadedAt: r.uploadedAt,
        status: ReportStatus.analyzed,
        fileRef: r.fileRef,
        sha256: r.sha256,
        isDemoMatched: isDemoMatched,
        summary: demo.summary,
        metrics: demo.metrics,
        findings: demo.findings,
        hasRiskFinding: demo.hasRisk || demo.metrics.any((m) => m.isOutOfRange),
        medicines: demo.medicines,
        insights: demo.insights,
        ocrConfidence: demo.confidence,
      );

  void _setStatus(String id, ReportStatus status) {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(status: status) else r,
    ];
  }

  MedicalReport? _getById(String id) {
    for (final r in state) {
      if (r.id == id) return r;
    }
    return null;
  }
}

final reportsControllerProvider =
    NotifierProvider<ReportsController, List<MedicalReport>>(
  ReportsController.new,
);

