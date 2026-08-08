/// Centralised API endpoint registry. Base URL is environment-driven.
abstract final class ApiEndpoints {
  // Local testing default: with a USB-connected device and
  // `adb reverse tcp:8000 tcp:8000`, the phone reaches the Mac's backend at
  // localhost:8000 over the cable. Override with --dart-define=API_BASE_URL=...
  // for production (e.g. https://api.medintelnexus.app).
  static const String baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');
  static const String apiV1 = '/api/v1';

  // Auth endpoints handled by Supabase SDK directly.
  // Backend endpoints for Supabase-JWT-authenticated calls remain below.

  // Patient
  static const String me = '$apiV1/patients/me';

  // Prescriptions
  static const String prescriptions = '$apiV1/prescriptions';
  static const String prescriptionUploadUrl =
      '$apiV1/prescriptions/upload-url';
  static String prescription(String id) => '$apiV1/prescriptions/$id';

  // Prescription OCR flow (async signed-URL pipeline)
  static const String prescriptionUploads = '$apiV1/prescriptions/uploads';
  static String prescriptionUploadComplete(String uploadId) =>
      '$apiV1/prescriptions/uploads/$uploadId/complete';
  static String prescriptionMedicines(String id) =>
      '$apiV1/prescriptions/$id/medicines';
  static String prescriptionOcr(String id) => '$apiV1/prescriptions/$id/ocr';
  static String prescriptionReprocess(String id) =>
      '$apiV1/prescriptions/$id/reprocess';

  /// Records the patient's confirmation of the extracted medicines — what
  /// unlocks risk analysis for a scan the OCR wasn't confident about.
  static String prescriptionVerify(String id) =>
      '$apiV1/prescriptions/$id/verify';

  // Reports
  static const String reports = '$apiV1/reports';
  static String report(String id) => '$apiV1/reports/$id';

  // Report OCR flow (async signed-URL pipeline, mirrors prescriptions)
  static const String reportUploads = '$apiV1/reports/uploads';
  static String reportUploadComplete(String uploadId) =>
      '$apiV1/reports/uploads/$uploadId/complete';
  static String reportAnalysis(String id) => '$apiV1/reports/$id/analysis';
  static String reportReprocess(String id) => '$apiV1/reports/$id/reprocess';

  // Assistant. Inference runs on the backend against a local model, so no
  // provider key ever ships in the app.
  static const String assistantMessages = '$apiV1/assistant/messages';
  static String assistantStream(String id) =>
      '$apiV1/assistant/stream/$id';

  /// Faithfully rephrases an already-computed insight — see
  /// `dashboard/application/insight_narrator.dart`.
  static const String assistantNarrate = '$apiV1/assistant/narrate';

  /// One turn of the adaptive symptom-triage questionnaire.
  static const String assistantTriage = '$apiV1/assistant/triage';

  // Savings
  static const String savingsGenerics = '$apiV1/savings/generics';

  // Misc
  static const String interactionsCheck = '$apiV1/interactions/check';
  static const String pharmaciesNearby = '$apiV1/pharmacies/nearby';

  /// Whether the backend's local model is up. Not under [apiV1] and needs
  /// no auth — it's an infrastructure probe, not patient data.
  static const String llmHealth = '/health/llm';
}
