import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Best-guess name/dosage read off a photographed medicine package.
class MedicineLabelScanResult {
  const MedicineLabelScanResult({required this.name, this.dosage});
  final String name;
  final String? dosage;
}

/// Reads a medicine's name and dosage straight off a photo of its box —
/// entirely on-device, via Google ML Kit's text recognizer, so it costs
/// nothing and works offline.
///
/// Why OCR instead of scanning a barcode against a lookup database: there's
/// no free, reliable barcode-to-drug-name database with real coverage of
/// Indian pharmaceutical packaging (the ones that exist — DrugsAPI,
/// DrugSetu — are paid enterprise products; the free general ones like
/// Open Food Facts / Open Products Facts / UPCitemdb are food/general-retail
/// databases with essentially no local pharma coverage). Reading the name
/// straight off the box's own printed text sidesteps needing any external
/// database at all, and works on literally every package since the name is
/// always printed on it.
///
/// This is a best-effort heuristic, not a guarantee — the result always
/// populates an editable form field rather than being trusted outright.
class MedicineLabelScanner {
  /// Scans [imagePath] and returns a best guess, or null if no usable text
  /// was found. Never throws — OCR failures are common (blur, glare, bad
  /// angle) and should just fall through to manual entry.
  Future<MedicineLabelScanResult?> scan(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);

      final lines = <TextLine>[
        for (final block in recognized.blocks) ...block.lines,
      ];
      if (lines.isEmpty) return null;

      final dosage = _findDosage(lines);
      final name = _guessName(lines);
      if (name == null) return null;

      return MedicineLabelScanResult(name: name, dosage: dosage);
    } catch (e) {
      dev.log('MedicineLabelScanner.scan failed: $e', name: 'reminders.ocr');
      return null;
    } finally {
      await recognizer.close();
    }
  }

  static final _dosagePattern = RegExp(
    r'\b\d+(\.\d+)?\s?(mg|mcg|g|ml|iu)\b',
    caseSensitive: false,
  );

  static final _junkWordPattern = RegExp(
    r'^(tablets?|capsules?|syrup|mfg|exp|batch|mrp|rx|net|wt|india)\b',
    caseSensitive: false,
  );

  String? _findDosage(List<TextLine> lines) {
    for (final line in lines) {
      final match = _dosagePattern.firstMatch(line.text);
      if (match != null) return match.group(0)?.trim();
    }
    return null;
  }

  /// Heuristic: the medicine's brand/generic name is almost always the
  /// most prominent text on the front of the box — which, since ML Kit
  /// gives no font-size field directly, is well approximated by the
  /// tallest bounding box among lines that actually look like a name
  /// (mostly letters, not a batch/expiry/weight line).
  String? _guessName(List<TextLine> lines) {
    TextLine? best;
    double bestHeight = 0;

    for (final line in lines) {
      final text = line.text.trim();
      if (text.length < 3 || text.length > 40) continue;
      if (_junkWordPattern.hasMatch(text)) continue;
      if (_dosagePattern.hasMatch(text) && text.length < 8) continue;

      final letters = text.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
      if (letters < text.length * 0.5) continue; // mostly non-letters — skip

      final height = line.boundingBox.height;
      if (height > bestHeight) {
        bestHeight = height;
        best = line;
      }
    }

    return best?.text.trim();
  }
}

final medicineLabelScannerProvider = Provider<MedicineLabelScanner>((ref) {
  return MedicineLabelScanner();
});
