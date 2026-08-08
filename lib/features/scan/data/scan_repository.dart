import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/result.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../domain/dosage_format.dart';
import '../domain/medicine.dart';

/// The outcome of running the OCR pipeline on a captured prescription image:
/// the server-side prescription id, the structured medicines the pipeline
/// extracted, and the mean OCR confidence.
class OcrOutcome {
  const OcrOutcome({
    required this.prescriptionId,
    required this.medicines,
    this.confidence,
    this.verified = false,
  });

  final String prescriptionId;
  final List<Medicine> medicines;
  final double? confidence;

  /// False when the pipeline wasn't confident enough about a drug name or
  /// strength to stand behind it. Risk analysis is withheld until the
  /// patient confirms — see [ScanRepository.verifyMedicines].
  final bool verified;
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

  // ~3min ceiling. Sized for the backend's local model rather than a hosted
  // one: Tesseract is fast, but structuring a page of OCR text through a 7B
  // model on CPU takes tens of seconds, and timing out mid-analysis would
  // show the patient a "couldn't read this" error for a scan that was
  // working fine.
  static const int _maxPolls = 90;

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

      // 4 · poll until the worker finishes. The summary that comes back
      // carries the confidence and the review verdict, which only exist
      // once processing has actually run — the response to step 3 predates
      // both.
      onStatus?.call('processing');
      final analyzed = await _pollUntilTerminal(prescriptionId, onStatus);
      final status = (analyzed['status'] as String?) ?? 'processing';
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
      final confidence = (analyzed['ocr_confidence'] as num?)?.toDouble();
      final verified = analyzed['verified'] == true;

      final medicines = [
        for (var i = 0; i < rawMeds.length; i++)
          _mapMedicine(rawMeds[i], i, confidence),
      ];

      return Success(
        OcrOutcome(
          prescriptionId: prescriptionId,
          confidence: confidence,
          verified: verified,
          // Withheld until the patient has confirmed an uncertain read: a
          // risk verdict computed from a misread drug name is worse than no
          // verdict, because it looks authoritative.
          medicines: verified
              ? await _withInteractionRisk(medicines, prescriptionId)
              : medicines,
        ),
      );
    } on DioException catch (e) {
      // No OCR backend reachable. This used to return a canned list of
      // medicines so the flow stayed "usable" offline — which meant a
      // patient could be shown Amoxicillin, Paracetamol and Pantoprazole
      // that were never on their prescription, indistinguishable from a
      // real read. Nothing here is worth that; an unreachable analyser is
      // reported as exactly that.
      if (_isBackendUnreachable(e)) {
        return const ResultFailure(
          NetworkFailure(
            "Couldn't reach the prescription analyser. Check your "
            'connection and try again, or add the medicines manually.',
          ),
        );
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

  /// Polls the prescription detail endpoint until status is `analyzed` or
  /// `failed`, returning the last summary it saw.
  Future<Map<String, dynamic>> _pollUntilTerminal(
    String prescriptionId,
    void Function(String status)? onStatus,
  ) async {
    var last = <String, dynamic>{'status': 'processing'};
    for (var i = 0; i < _maxPolls; i++) {
      await Future<void>.delayed(_pollInterval);
      final detail = _data(
        await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.prescription(prescriptionId),
        ),
      );
      last = (detail['prescription'] as Map).cast<String, dynamic>();
      final status = (last['status'] as String?) ?? 'processing';
      onStatus?.call(status);
      if (status == 'analyzed' || status == 'failed') break;
    }
    return last;
  }

  /// Sends the patient's confirmation of [medicines] for [prescriptionId],
  /// then runs the risk analysis that was withheld until now.
  ///
  /// The full confirmed list goes up, not a diff — anything the patient
  /// removed is removed server-side too, which is how they throw out a
  /// medicine the OCR invented.
  Future<Result<OcrOutcome>> verifyMedicines({
    required String prescriptionId,
    required List<Medicine> medicines,
  }) async {
    // Scans completed offline have no server record to confirm against, so
    // the confirmation is simply taken at face value locally.
    if (prescriptionId.startsWith('local_')) {
      return Success(
        OcrOutcome(
          prescriptionId: prescriptionId,
          verified: true,
          medicines: [for (final m in medicines) m.confirmed()],
        ),
      );
    }

    try {
      final data = _data(
        await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.prescriptionVerify(prescriptionId),
          data: {
            'medicines': [
              for (final m in medicines)
                {
                  'id': m.id,
                  'raw_name': _fullName(m),
                  'normalized_name': m.name,
                  if (m.strength.isNotEmpty) 'strength': m.strength,
                  if (m.dosageLine.isNotEmpty) 'instructions': m.dosageLine,
                },
            ],
          },
        ),
      );

      final rx = (data['prescription'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final confidence = (rx['ocr_confidence'] as num?)?.toDouble();
      final confirmed = [for (final m in medicines) m.confirmed()];

      return Success(
        OcrOutcome(
          prescriptionId: prescriptionId,
          confidence: confidence,
          verified: true,
          medicines: await _withInteractionRisk(confirmed, prescriptionId),
        ),
      );
    } on DioException catch (e) {
      // Confirming is the patient's own correction; if the server can't be
      // reached there's nothing to reconcile with, so honour it locally
      // rather than trapping them behind the gate. Same offline stance the
      // capture path takes.
      if (_isBackendUnreachable(e)) {
        return Success(
          OcrOutcome(
            prescriptionId: prescriptionId,
            verified: true,
            medicines: [for (final m in medicines) m.confirmed()],
          ),
        );
      }
      return ResultFailure(_failureFor(e));
    } catch (e) {
      return ResultFailure(UnknownFailure('Could not save your changes: $e'));
    }
  }

  /// "Amoxicillin 500 mg" — the name as it would read on the page.
  String _fullName(Medicine m) =>
      m.strength.isEmpty ? m.name : '${m.name} ${m.strength}';

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
  ///
  /// [prescriptionId] is sent so the engine scores the confirmed names it
  /// holds rather than trusting this client's copy; it answers 409 if the
  /// prescription hasn't been confirmed, which lands in the catch below and
  /// leaves every medicine unflagged.
  Future<List<Medicine>> _withInteractionRisk(
    List<Medicine> medicines, [
    String? prescriptionId,
  ]) async {
    if (medicines.length < 2) return medicines;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.interactionsCheck,
        data: {
          'medicine_names': medicines.map((m) => m.name).toList(),
          if (prescriptionId != null && !prescriptionId.startsWith('local_'))
            'prescription_id': prescriptionId,
        },
      );
      final data = _data(res);
      if (data['checked'] != true) return medicines;

      // Drugs the interaction database has never heard of. Nothing was
      // checked for these, and leaving them at RiskLevel.none would render
      // a green "No interaction" badge over an all-clear that was never
      // given.
      final unrecognized = {
        for (final n in (data['unrecognized'] as List? ?? const []))
          n.toString().toLowerCase().trim(),
      };

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

      return [
        for (final m in medicines)
          if (riskByName.containsKey(m.name.toLowerCase().trim()))
            m.copyWith(
              riskLevel: riskByName[m.name.toLowerCase().trim()],
              riskNote: noteByName[m.name.toLowerCase().trim()],
              interactionsChecked: true,
            )
          else
            m.copyWith(
              interactionsChecked:
                  !unrecognized.contains(m.name.toLowerCase().trim()),
            ),
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

    return Medicine(
      id: (m['id'] as String?) ?? 'm_$index',
      name: (name != null && name.isNotEmpty) ? name : rawName,
      strength: strength,
      // The server stores the rhythm as the page writes it ("BD", "1-0-1")
      // so field confidence can be measured against the OCR words; it's
      // expanded into plain language only here, for the patient to read.
      dosageLine: formatDosageLine(
        frequency: m['frequency'] as String?,
        durationDays: (m['duration_days'] as num?)?.toInt(),
        instructions: m['instructions'] as String?,
      ),
      // The /medicines endpoint carries no risk; risk lives in alerts.
      riskLevel: RiskLevel.none,
      confidence: _confidenceOf(m['field_confidence'], fallbackConfidence),
      uncertainFields: _fieldsFrom(m['low_confidence_fields']),
      blockingFields: _fieldsFrom(m['blocking_fields']),
      userCorrected: m['user_corrected'] == true,
    );
  }

  /// Collapses the backend's field keys onto the boxes the patient edits.
  Set<MedicineField> _fieldsFrom(Object? raw) {
    if (raw is! List) return const {};
    return {
      for (final key in raw)
        if (MedicineField.fromApiKey(key.toString()) case final field?) field,
    };
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
