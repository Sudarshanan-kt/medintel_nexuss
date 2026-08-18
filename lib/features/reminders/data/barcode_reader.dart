import 'dart:typed_data';

import 'barcode_reader_stub.dart'
    if (dart.library.js_interop) 'barcode_reader_web.dart' as impl;

/// Reads raw barcode/QR payloads from image bytes without ML Kit.
///
/// Exists because `google_mlkit_barcode_scanning` is Android/iOS only, so on
/// web the scanner had no way to see a code at all. Interpreting the payload
/// is unchanged and shared — see `MedicineBarcodeScanner.parsePayload`, which
/// is pure Dart and already platform-agnostic.
Future<List<String>> readBarcodes(Uint8List bytes) => impl.readBarcodes(bytes);

/// Whether this platform can read codes this way. False on mobile (which
/// uses ML Kit) and in browsers without the Barcode Detection API.
Future<bool> barcodeReaderAvailable() => impl.barcodeReaderAvailable();
