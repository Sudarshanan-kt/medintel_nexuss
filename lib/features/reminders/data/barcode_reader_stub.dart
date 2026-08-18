import 'dart:typed_data';

/// Non-web fallback. Mobile reads codes through ML Kit, so this is never
/// reached; it exists to keep the conditional import compiling.
Future<List<String>> readBarcodes(Uint8List bytes) async => const [];

/// Whether this platform can read codes without ML Kit.
Future<bool> barcodeReaderAvailable() async => false;
