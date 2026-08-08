import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// What a scanned code turned out to contain.
enum BarcodeSource {
  /// The code carried the drug's own details — nothing had to be looked up.
  ///
  /// India's DCGI mandate (Drugs Rules, in force since August 2023) requires
  /// the top 300 drug brands to print a QR code carrying the generic name,
  /// brand name, manufacturer, batch and expiry. Those packs identify
  /// themselves.
  embedded,

  /// A GS1 code — a product number plus optionally batch/expiry, but no
  /// name. Identifies the pack exactly; says nothing about what's in it.
  gs1,

  /// A plain retail barcode (EAN-13/UPC). A number and nothing else.
  plain,
}

/// A medicine identified from a barcode.
///
/// [name] is null whenever the code didn't actually carry one — which is
/// most codes. The caller is expected to resolve that from remembered
/// mappings or ask the patient, never to invent it.
class BarcodeScanResult {
  const BarcodeScanResult({
    required this.rawValue,
    required this.source,
    this.name,
    this.strength,
    this.batch,
    this.expiry,
    this.manufacturer,
  });

  /// Exactly what was encoded, used as the key for remembered mappings.
  final String rawValue;
  final BarcodeSource source;

  final String? name;
  final String? strength;
  final String? batch;
  final DateTime? expiry;
  final String? manufacturer;

  bool get hasName => (name ?? '').trim().isNotEmpty;
}

/// Reads a medicine's identity from the barcode or QR code on its pack,
/// entirely on-device via Google ML Kit.
///
/// The honest limitation, and why this doesn't replace the OCR label
/// scanner: a barcode is a number, and turning a number into a drug name
/// needs a database. There is no free barcode-to-drug database with real
/// coverage of Indian pharmaceutical packaging — the general ones
/// (Open Food Facts, UPCitemdb) are retail/food catalogues, and the pharma
/// ones are paid enterprise products.
///
/// So this extracts a name only when the code genuinely contains one, and
/// otherwise hands back the code so the caller can look it up in what the
/// patient has already confirmed before. Between the two, plus OCR as the
/// backstop, every pack is covered by something.
class MedicineBarcodeScanner {
  /// Scans [imagePath]. Returns null when no code was found — a common,
  /// unremarkable outcome (blur, glare, no code on the pack) that should
  /// fall through to OCR or manual entry rather than read as an error.
  Future<BarcodeScanResult?> scan(String imagePath) async {
    final scanner = BarcodeScanner();
    try {
      final barcodes = await scanner.processImage(
        InputImage.fromFilePath(imagePath),
      );
      if (barcodes.isEmpty) return null;

      // Prefer whichever code carries the most information: a QR with the
      // drug's details beats a bare retail number printed alongside it.
      BarcodeScanResult? best;
      for (final barcode in barcodes) {
        final value = barcode.rawValue?.trim();
        if (value == null || value.isEmpty) continue;
        final parsed = parsePayload(value);
        if (best == null || _rank(parsed) > _rank(best)) best = parsed;
      }
      return best;
    } catch (e) {
      dev.log(
        'MedicineBarcodeScanner.scan failed: $e',
        name: 'reminders.barcode',
      );
      return null;
    } finally {
      await scanner.close();
    }
  }

  int _rank(BarcodeScanResult r) => switch (r.source) {
        BarcodeSource.embedded => r.hasName ? 3 : 2,
        BarcodeSource.gs1 => 1,
        BarcodeSource.plain => 0,
      };

  /// Interprets a raw code payload. Exposed for testing.
  BarcodeScanResult parsePayload(String raw) {
    final value = raw.trim();
    return _tryJson(value) ?? _tryKeyValue(value) ?? _tryGs1(value) ?? _plain(value);
  }

  // ── India DCGI QR payloads ────────────────────────────────────────────
  //
  // The rule mandates the fields but not an encoding, so manufacturers ship
  // whichever they like. The two shapes seen in practice are a JSON object
  // and a delimited key-value string; both are handled.

  static const _nameKeys = [
    'genericname', 'generic_name', 'generic', 'gnm',
    'drugname', 'drug_name', 'medicinename', 'medicine_name',
    'brandname', 'brand_name', 'brand', 'product', 'productname',
    'product_name', 'name', 'pnm',
  ];
  static const _strengthKeys = ['strength', 'dosage', 'dose', 'str'];
  static const _batchKeys = ['batch', 'batchno', 'batch_no', 'bno', 'lot'];
  static const _expiryKeys = ['expiry', 'exp', 'expdate', 'exp_date', 'expiryDate'];
  static const _manufacturerKeys = [
    'manufacturer', 'mfr', 'mfg', 'mfgby', 'company', 'marketedby',
  ];

  String? _pick(Map<String, String> fields, List<String> keys) {
    for (final key in keys) {
      final value = fields[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  BarcodeScanResult _fromFields(String raw, Map<String, String> fields) {
    // Generic name first: it's the clinically meaningful one, and it's what
    // the interaction database and the rest of the app key on. A brand name
    // is a fallback, not a preference.
    return BarcodeScanResult(
      rawValue: raw,
      source: BarcodeSource.embedded,
      name: _pick(fields, _nameKeys),
      strength: _pick(fields, _strengthKeys),
      batch: _pick(fields, _batchKeys),
      expiry: _parseDate(_pick(fields, _expiryKeys)),
      manufacturer: _pick(fields, _manufacturerKeys),
    );
  }

  BarcodeScanResult? _tryJson(String raw) {
    if (!raw.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final fields = <String, String>{
        for (final entry in decoded.entries)
          _normalizeKey(entry.key.toString()): entry.value?.toString() ?? '',
      };
      final result = _fromFields(raw, fields);
      return result.hasName ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// Handles `key=value` pairs separated by `|`, `;`, `,` or newlines.
  BarcodeScanResult? _tryKeyValue(String raw) {
    if (!raw.contains('=')) return null;
    final fields = <String, String>{};
    for (final part in raw.split(RegExp(r'[|;\n\r]+'))) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      fields[_normalizeKey(part.substring(0, index))] =
          part.substring(index + 1).trim();
    }
    if (fields.isEmpty) return null;
    final result = _fromFields(raw, fields);
    return result.hasName ? result : null;
  }

  String _normalizeKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');

  // ── GS1 Application Identifiers ───────────────────────────────────────
  //
  // "(01)08901234567890(17)261231(10)AB1234" — or the same without
  // brackets, using fixed field lengths. Carries identity and provenance,
  // never a product name.

  static final _bracketedAi = RegExp(r'\((\d{2,4})\)([^(]*)');

  BarcodeScanResult? _tryGs1(String raw) {
    final normalized = raw.startsWith(']') ? raw.substring(3) : raw;

    final fields = <String, String>{};
    if (normalized.contains('(')) {
      for (final match in _bracketedAi.allMatches(normalized)) {
        fields[match.group(1)!] = match.group(2)!.trim();
      }
    } else if (normalized.startsWith('01') && normalized.length >= 16) {
      // Fixed-length GTIN, then whatever follows.
      fields['01'] = normalized.substring(2, 16);
      var rest = normalized.substring(16);
      while (rest.length >= 2) {
        final ai = rest.substring(0, 2);
        if (ai == '17' && rest.length >= 8) {
          fields['17'] = rest.substring(2, 8);
          rest = rest.substring(8);
        } else if (ai == '10') {
          fields['10'] = rest.substring(2);
          break;
        } else {
          break;
        }
      }
    }

    if (!fields.containsKey('01')) return null;
    return BarcodeScanResult(
      rawValue: fields['01']!,
      source: BarcodeSource.gs1,
      batch: fields['10'],
      expiry: _parseGs1Date(fields['17']),
    );
  }

  BarcodeScanResult _plain(String raw) =>
      BarcodeScanResult(rawValue: raw, source: BarcodeSource.plain);

  // ── Dates ─────────────────────────────────────────────────────────────

  /// GS1 dates are YYMMDD; a day of `00` means "end of month".
  DateTime? _parseGs1Date(String? value) {
    if (value == null || value.length != 6) return null;
    final year = int.tryParse(value.substring(0, 2));
    final month = int.tryParse(value.substring(2, 4));
    final day = int.tryParse(value.substring(4, 6));
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12) return null;
    // Two-digit years in GS1 are within ±50 years; medicine expiries are
    // always ahead, so 2000s throughout.
    return day == 0
        ? DateTime(2000 + year, month + 1, 0)
        : DateTime(2000 + year, month, day);
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final text = value.trim();

    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;

    // MM/YYYY or MM-YY, the usual form on a pharmaceutical pack.
    final short = RegExp(r'^(\d{1,2})[/-](\d{2,4})$').firstMatch(text);
    if (short != null) {
      final month = int.parse(short.group(1)!);
      var year = int.parse(short.group(2)!);
      if (year < 100) year += 2000;
      if (month < 1 || month > 12) return null;
      // An expiry month means the end of that month.
      return DateTime(year, month + 1, 0);
    }

    final gs1 = _parseGs1Date(text);
    if (gs1 != null) return gs1;

    return null;
  }
}

final medicineBarcodeScannerProvider = Provider<MedicineBarcodeScanner>((ref) {
  return MedicineBarcodeScanner();
});
