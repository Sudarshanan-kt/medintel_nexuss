import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/core/services/media_bytes.dart';

void main() {
  setUp(MediaBytes.resetForTest);

  group('read', () {
    test('returns bytes that were registered for a reference', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      MediaBytes.register('bloodwork.pdf', bytes);

      expect(await MediaBytes.read('bloodwork.pdf'), bytes);
    });

    test('returns null for a reference nothing can resolve', () async {
      // What a web `file_picker` reference looks like when the bytes were
      // never registered: a bare name with no file behind it. The pipelines
      // report this as "couldn't read this" rather than throwing.
      expect(await MediaBytes.read('never-registered.pdf'), isNull);
    });

    test('returns null for an empty reference', () async {
      expect(await MediaBytes.read(''), isNull);
    });

    test('reads a real file from a filesystem path', () async {
      // The mobile path: nothing registered, so it falls through to XFile.
      final file = await _tempFile([4, 5, 6]);
      expect(await MediaBytes.read(file), Uint8List.fromList([4, 5, 6]));
    });
  });

  group('forget', () {
    test('drops registered bytes', () async {
      MediaBytes.register('scan.jpg', Uint8List.fromList([7]));
      MediaBytes.forget('scan.jpg');

      expect(await MediaBytes.read('scan.jpg'), isNull);
    });
  });

  group('nameFor', () {
    test('takes the last segment of a path', () {
      expect(
        MediaBytes.nameFor('/data/user/0/cache/IMG_2201.jpg'),
        'IMG_2201.jpg',
      );
    });

    test('leaves a bare name alone', () {
      expect(MediaBytes.nameFor('bloodwork.pdf'), 'bloodwork.pdf');
    });

    test('strips a query string so an extension stays readable', () {
      expect(
        MediaBytes.nameFor('https://host/a/report.pdf?token=x'),
        'report.pdf',
      );
    });

    test('falls back to the reference when there is no last segment', () {
      expect(MediaBytes.nameFor('trailing/'), 'trailing/');
    });
  });
}

Future<String> _tempFile(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('media_bytes_test');
  final file = File('${dir.path}/capture.bin');
  await file.writeAsBytes(bytes);
  addTearDown(() => dir.delete(recursive: true));
  return file.path;
}
