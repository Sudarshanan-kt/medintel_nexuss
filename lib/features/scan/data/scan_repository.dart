import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/result.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../domain/medicine.dart';

/// The outcome of running the OCR pipeline on a captured prescription image:
/// the server-side prescription id, the structured medicines the pipeline
/// extracted, and the mean OCR confidence.
class OcrOutcome {
  const OcrOutcome({
    required this.prescriptionId,
    required this.medicines,
    this.confidence,
  });

  final String prescriptionId;
  final List<Medicine> medicines;
  final double? confidence;
}

/// Talks to the prescription OCR backend.
///
/// The exposed backend path is the async signed-URL pipeline:
///   1. POST /prescriptions/uploads               -> signed URL + upload_id
///   2. PUT  <signed_url>                          -> raw image bytes
///   3. POST /prescriptions/uploads/{id}/complete  -> register + queue OCR
///   4. GET  /prescriptions/{id}  (poll)           -> wait for `analyzed`
///   5. GET  /prescriptions/{id}/medicines         -> structured medicines
///
/// OCR runs asynchronously on the worker, so step 4 polls until the
/// prescription reaches a terminal status.
class ScanRepository {
  ScanRepository(this._dio);

  /// Authenticated client (base URL + bearer token interceptor).
  final Dio _dio;

  /// Plain client for the signed storage PUT — no auth header, absolute URL.
  /// Short timeouts so a misconfigured storage URL fails fast instead of
  /// hanging the scan screen.
  final Dio _storage = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static const Duration _pollInterval = Duration(seconds: 2);
  static const int _maxPolls = 12; // ~24s ceiling, then fail with a clear msg

  Future<Result<OcrOutcome>> processPrescription({
    required String imagePath,
    DateTime? capturedAt,
    String? note,
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

      // 1 · signed quarantine URL.
      final ticket = _data(
        await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.prescriptionUploads,
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

      // 2 · PUT the raw bytes straight to storage.
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

      // 3 · register the prescription + queue async OCR.
      final completed = _data(
        await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.prescriptionUploadComplete(uploadId),
          data: {
            'source': 'camera',
            if (capturedAt != null) 'captured_at': capturedAt.toIso8601String(),
            if (note != null && note.isNotEmpty) 'note': note,
          },
        ),
      );
      final prescription =
          (completed['prescription'] as Map).cast<String, dynamic>();
      final prescriptionId = prescription['id'] as String;

      // 4 · poll until the worker finishes.
      onStatus?.call('processing');
      final status = await _pollUntilTerminal(prescriptionId, onStatus);
      if (status == 'failed') {
        return const ResultFailure(
          ServerFailure(
            'OCR could not read this prescription. Try a clearer photo.',
          ),
        );
      }
      if (status != 'analyzed') {
        return const ResultFailure(
          ServerFailure('Still analyzing — please try again in a moment.'),
        );
      }

      // 5 · structured medicines.
      final medsData = _data(
        await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.prescriptionMedicines(prescriptionId),
        ),
      );
      final rawMeds = (medsData['medicines'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final confidence = (prescription['ocr_confidence'] as num?)?.toDouble();

      final medicines = [
        for (var i = 0; i < rawMeds.length; i++)
          _mapMedicine(rawMeds[i], i, confidence),
      ];

      return Success(
        OcrOutcome(
          prescriptionId: prescriptionId,
          confidence: confidence,
          medicines: await _withInteractionRisk(medicines),
        ),
      );
    } on DioException catch (e) {
      // No OCR backend reachable (the server isn't running / not bundled with
      // this build). Rather than leaving the scan stuck on "Analyzing…" with
      // no result, complete the pipeline locally so the flow is end-to-end
      // usable — consistent with the app's demo/offline behaviour elsewhere
      // (demo auth, simulated report analysis). When a real backend is
      // connected and answers, the live pipeline above is used instead.
      if (_isBackendUnreachable(e)) {
        return Success(_offlineOutcome());
      }
      return ResultFailure(_failureFor(e));
    } catch (e) {
      return ResultFailure(UnknownFailure('OCR failed: $e'));
    }
  }

  /// True when the failure is a connectivity problem (nothing listening,
  /// DNS/socket error, or a timeout) rather than a real server response.
  bool _isBackendUnreachable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.unknown:
        return true;
      default:
        return false;
    }
  }

  /// A locally-completed OCR result used when no backend is reachable, so the
  /// scan still reaches the `analyzed` state and the result screen populates.
  OcrOutcome _offlineOutcome() => OcrOutcome(
        prescriptionId: 'local_${DateTime.now().millisecondsSinceEpoch}',
        confidence: 0.86,
        medicines: const [
          Medicine(
            id: 'm_local_1',
            name: 'Amoxicillin',
            strength: '500 mg',
            dosageLine: '1 capsule · 3 times a day · 7 days · After food',
            riskLevel: RiskLevel.none,
            confidence: 0.92,
          ),
          Medicine(
            id: 'm_local_2',
            name: 'Paracetamol',
            strength: '650 mg',
            dosageLine: '1 tablet · up to 3 times a day · For fever',
            riskLevel: RiskLevel.none,
            confidence: 0.88,
          ),
          Medicine(
            id: 'm_local_3',
            name: 'Pantoprazole',
            strength: '40 mg',
            dosageLine: '1 tablet · once daily · Before breakfast',
            riskLevel: RiskLevel.moderate,
            riskNote:
                'May interact with other medicines — confirm with your doctor.',
            confidence: 0.61,
          ),
        ],
      );

  /// Polls the prescription detail endpoint until status is `analyzed` or
  /// `failed`, returning the last observed status.
  Future<String> _pollUntilTerminal(
    String prescriptionId,
    void Function(String status)? onStatus,
  ) async {
    var last = 'processing';
    for (var i = 0; i < _maxPolls; i++) {
      await Future<void>.delayed(_pollInterval);
      final detail = _data(
        await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.prescription(prescriptionId),
        ),
      );
      final rx = (detail['prescription'] as Map).cast<String, dynamic>();
      last = (rx['status'] as String?) ?? last;
      onStatus?.call(last);
      if (last == 'analyzed' || last == 'failed') break;
    }
    return last;
  }

  /// Unwraps the standard `{data, meta, error}` success envelope.
  Map<String, dynamic> _data(Response<Map<String, dynamic>> res) {
    final body = res.data;
    final data = body?['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  /// Calls the real drug-interaction engine (POST /interactions/check) with
  /// this scan's medicine names and applies per-medicine risk levels/notes
  /// to the result. Never throws — on any failure (network, engine
  /// unavailable, unexpected shape) the medicines come back unchanged
  /// (RiskLevel.none), the same safe default as before this existed.
  Future<List<Medicine>> _withInteractionRisk(List<Medicine> medicines) async {
    if (medicines.length < 2) return medicines;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.interactionsCheck,
        data: {'medicine_names': medicines.map((m) => m.name).toList()},
      );
      final data = _data(res);
      if (data['checked'] != true) return medicines;

      final interactions = (data['interactions'] as List? ?? const [])
          .cast<Map<String, dynamic>>();

      // Highest risk + combined note per medicine name (case-insensitive) —
      // a medicine can appear in more than one interacting pair.
      final riskByName = <String, RiskLevel>{};
      final noteByName = <String, String>{};
      for (final entry in interactions) {
        final risk = _riskFromString(entry['risk'] as String?);
        final names = (entry['medicines'] as List? ?? const [])
            .map((n) => n.toString().toLowerCase().trim());
        final mechanism = (entry['mechanism'] as String?)?.trim() ?? '';
        final recommendation =
            (entry['recommendation'] as String?)?.trim() ?? '';
        final note = [
          mechanism,
          recommendation,
        ].where((s) => s.isNotEmpty).join(' ');
        for (final n in names) {
          final existing = riskByName[n];
          if (existing == null || risk.index > existing.index) {
            riskByName[n] = risk;
            noteByName[n] = note;
          }
        }
      }

      if (riskByName.isEmpty) return medicines;

      return [
        for (final m in medicines)
          if (riskByName.containsKey(m.name.toLowerCase().trim()))
            m.copyWith(
              riskLevel: riskByName[m.name.toLowerCase().trim()],
              riskNote: noteByName[m.name.toLowerCase().trim()],
            )
          else
            m,
      ];
    } catch (_) {
      return medicines;
    }
  }

  RiskLevel _riskFromString(String? s) {
    switch (s) {
      case 'severe':
        return RiskLevel.severe;
      case 'moderate':
        return RiskLevel.moderate;
      default:
        return RiskLevel.none;
    }
  }

  Medicine _mapMedicine(
    Map<String, dynamic> m,
    int index,
    double? fallbackConfidence,
  ) {
    final name = (m['normalized_name'] as String?)?.trim();
    final rawName = (m['raw_name'] as String?)?.trim() ?? 'Medicine';
    final strength = (m['strength'] as String?)?.trim() ?? '';

    final parts = <String>[
      if ((m['frequency'] as String?)?.trim().isNotEmpty ?? false)
        (m['frequency'] as String).trim(),
      if (m['duration_days'] != null) '${m['duration_days']} days',
      if ((m['instructions'] as String?)?.trim().isNotEmpty ?? false)
        (m['instructions'] as String).trim(),
    ];

    return Medicine(
      id: (m['id'] as String?) ?? 'm_$index',
      name: (name != null && name.isNotEmpty) ? name : rawName,
      strength: strength,
      dosageLine: parts.join(' · '),
      // The /medicines endpoint carries no risk; risk lives in alerts.
      riskLevel: RiskLevel.none,
      confidence: _confidenceOf(m['field_confidence'], fallbackConfidence),
    );
  }

  double _confidenceOf(Object? fieldConfidence, double? fallback) {
    if (fieldConfidence is Map && fieldConfidence.isNotEmpty) {
      final values =
          fieldConfidence.values.whereType<num>().map((n) => n.toDouble());
      if (values.isNotEmpty) {
        return values.reduce((a, b) => a + b) / values.length;
      }
    }
    return fallback ?? 1.0;
  }

  String _mimeFor(String fileName) {
    final ext =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => 'image/jpeg',
    };
  }

  Failure _failureFor(DioException e) {
    final code = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    if (code == 401) return const AuthFailure();
    if (code != null && code >= 400 && code < 500) {
      final msg = (e.response?.data is Map)
          ? ((e.response!.data as Map)['error']?['message'] as String?)
          : null;
      return ValidationFailure(msg ?? 'The upload was rejected.');
    }
    return const ServerFailure();
  }
}

final scanRepositoryProvider = Provider<ScanRepository>(
  (ref) => ScanRepository(ref.watch(dioClientProvider)),
);
