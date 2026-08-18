import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Chrome's Barcode Detection API. Not in `package:web`, so it is bound here.
///
/// Shipped in Chrome and Edge (desktop and Android). Firefox and Safari do
/// not implement it, which is why every entry point checks
/// [barcodeReaderAvailable] first and the caller treats "no codes" as the
/// ordinary outcome it already is on a blurred pack.
@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector();
  external JSPromise<JSArray<JSObject>> detect(JSObject image);
}

bool get _supported => web.window.has('BarcodeDetector');

Future<bool> barcodeReaderAvailable() async => _supported;

/// Every code found in [bytes], as raw payload strings.
///
/// Returns empty rather than throwing: a pack with no code, an unreadable
/// photo and a browser without the API are all the same outcome to the
/// caller — fall through to OCR or manual entry.
Future<List<String>> readBarcodes(Uint8List bytes) async {
  if (!_supported) return const [];

  web.ImageBitmap? bitmap;
  try {
    final blob = web.Blob(
      <JSUint8Array>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/jpeg'),
    );
    // Decoded off the DOM: the detector takes an ImageBitmap directly, so
    // nothing has to be attached to the page to read a code from bytes.
    bitmap = await web.window.createImageBitmap(blob).toDart;

    final detected = await _BarcodeDetector().detect(bitmap).toDart;

    final values = <String>[];
    for (var i = 0; i < detected.length; i++) {
      final raw = detected[i].getProperty<JSString?>('rawValue'.toJS);
      final value = raw?.toDart.trim();
      if (value != null && value.isNotEmpty) values.add(value);
    }
    return values;
  } catch (_) {
    return const [];
  } finally {
    // The bitmap holds decoded pixels; a scan loop that leaked one per frame
    // would grow without bound.
    bitmap?.close();
  }
}
