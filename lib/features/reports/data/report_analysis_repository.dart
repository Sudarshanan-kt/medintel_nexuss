import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/result.dart';
import '../domain/medical_report.dart';

/// Real, non-demo outcome of analyzing an uploaded report image — every
/// field is grounded in what the backend's Tesseract + local-LLM pipeline actually
/// read off the image, never canned/synthetic data (see
/// `medintel-nexus-backend/app/ocr.py`).
class ReportAnalysisOutcome {
  const ReportAnalysisOutcome({
    required this.summary,
    required this.metrics,
    required this.findings,
    required this.insights,
    this.confidence,
  });

  final String summary;
  final List<ReportMetric> metrics;
  final List<ReportFinding> findings;

  /// Per-out-of-range-value advice, formatted as one readable line each —
  /// the "what to actually do about it" the metrics/findings alone don't
  /// give you.
  final List<String> insights;
  final double? confidence;

  bool get hasRiskFinding =>
      findings.any((f) => f.severity != 'info') ||
      metrics.any((m) => m.isOutOfRange);
}

/// Talks to the real report-analysis backend (mirrors
/// `ScanRepository`'s prescription pipeline exactly, just structuring into
/// lab metrics/findings/advice instead of medicines).
class ReportAnalysisRepository {
  ReportAnalysisRepository(this._dio);

  final Dio _dio;

  final Dio _storage = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static const Duration _pollInterval = Duration(seconds: 2);

  // ~3min ceiling, matching the prescription pipeline. A lab report is the
  // longest structured response the backend's local model produces, so this
  // is the flow most likely to outrun a ceiling tuned for a hosted model.
  static const int _maxPolls = 90;

  Future<Result<ReportAnalysisOutcome>> analyzeReport({
    required String imagePath,
    void Function(String status)? onStatus,
  }) async {
    try {
      final file = File(imagePath);
      if (!file.existsSync()) {
        return const ResultFailure(
          ValidationFailure('Captured image could not be read.'),
        );
      }
      final bytes = await file.readAsBytes();
      final fileName = imagePath.split('/').last;
      final mimeType = _mimeFor(fileName);

      onStatus?.call('uploading');

      final ticket = _data(
        await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.reportUploads,
          data: {
            'file_name': fileName,
            'mime_type': mimeType,
            'size_bytes': bytes.length,
          },
        ),
      );
      final uploadId = ticket['upload_id'] as String;
      final signedUrl = ticket['signed_url'] as String;
      final contentType = (ticket['content_type'] as String?) ?? mimeType;

      await _storage.put<void>(
        signedUrl,
        data: Stream<List<int>>.fromIterable([bytes]),
        options: Options(
          headers: {
            'Content-Type': contentType,
            Headers.contentLengthHeader: bytes.length,
          },
        ),
      );

      final completed = _data(
        await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.reportUploadComplete(uploadId),
          data: const {'source': 'camera'},
        ),
      );
      final reportId =
          ((completed['report'] as Map).cast<String, dynamic>())['id']
              as String;

      onStatus?.call('processing');
      final status = await _pollUntilTerminal(reportId, onStatus);
      if (status == 'failed') {
        return const ResultFailure(
          ServerFailure(
            'OCR could not read this report clearly. Try a clearer photo.',
          ),
        );
      }
      if (status != 'analyzed') {
        return const ResultFailure(
          ServerFailure('Still analyzing — please try again in a moment.'),
        );
      }

      final analysis = _data(
        await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.reportAnalysis(reportId),
        ),
      );

      return Success(_mapOutcome(analysis));
    } on DioException catch (e) {
      return ResultFailure(_failureFor(e));
    } catch (e) {
      return ResultFailure(UnknownFailure('Report analysis failed: $e'));
    }
  }

  ReportAnalysisOutcome _mapOutcome(Map<String, dynamic> data) {
    final metrics = ((data['metrics'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (m) => ReportMetric(
            label: (m['label'] as String?) ?? '',
            value: (m['value'] as num?)?.toDouble() ?? 0,
            unit: (m['unit'] as String?) ?? '',
            refLow: (m['ref_low'] as num?)?.toDouble() ?? double.negativeInfinity,
            refHigh: (m['ref_high'] as num?)?.toDouble() ?? double.infinity,
          ),
        )
        .toList();

    final findings = ((data['findings'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (f) => ReportFinding(
            severity: (f['severity'] as String?) ?? 'info',
            text: (f['text'] as String?) ?? '',
            explanation: f['explanation'] as String?,
          ),
        )
        .toList();

    final advice = ((data['advice'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((a) {
          final label = (a['label'] as String?) ?? '';
          final direction = (a['direction'] as String?) ?? '';
          final text = (a['advice'] as String?) ?? '';
          return '$direction your $label — $text';
        })
        .toList();

    return ReportAnalysisOutcome(
      summary: (data['summary'] as String?) ?? '',
      metrics: metrics,
      findings: findings,
      insights: advice,
    );
  }

  Future<String> _pollUntilTerminal(
    String reportId,
    void Function(String status)? onStatus,
  ) async {
    var last = 'processing';
    for (var i = 0; i < _maxPolls; i++) {
      await Future<void>.delayed(_pollInterval);
      final detail = _data(
        await _dio.get<Map<String, dynamic>>(ApiEndpoints.report(reportId)),
      );
      final rpt = (detail['report'] as Map).cast<String, dynamic>();
      last = (rpt['status'] as String?) ?? last;
      onStatus?.call(last);
      if (last == 'analyzed' || last == 'failed') break;
    }
    return last;
  }

  Map<String, dynamic> _data(Response<Map<String, dynamic>> res) {
    final body = res.data;
    final data = body?['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  String _mimeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Failure _failureFor(DioException e) {
    final status = e.response?.statusCode;
    final responseData = e.response?.data;
    String? message;
    if (responseData is Map) {
      final error = responseData['error'];
      if (error is Map) message = error['message'] as String?;
    }
    if (status == 401) {
      return const AuthFailure('Session expired. Please sign in again.');
    }
    return ServerFailure(
      message ?? 'Could not analyze the report. Check your connection.',
    );
  }
}

final reportAnalysisRepositoryProvider = Provider<ReportAnalysisRepository>((
  ref,
) {
  return ReportAnalysisRepository(ref.watch(dioClientProvider));
});
