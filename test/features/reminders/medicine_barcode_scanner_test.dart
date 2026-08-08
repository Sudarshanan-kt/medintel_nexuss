import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/reminders/data/medicine_barcode_scanner.dart';

/// Payload parsing, which is where a barcode either yields a medicine name
/// or honestly admits it doesn't carry one.
void main() {
  final scanner = MedicineBarcodeScanner();

  group('India DCGI QR payloads', () {
    test('reads a JSON payload', () {
      final result = scanner.parsePayload(
        '{"genericName":"Amoxicillin","brandName":"Mox","strength":"500mg",'
        '"batchNo":"AB1234","expiry":"12/2027","manufacturer":"Cipla Ltd"}',
      );

      expect(result.source, BarcodeSource.embedded);
      expect(result.name, 'Amoxicillin');
      expect(result.strength, '500mg');
      expect(result.batch, 'AB1234');
      expect(result.manufacturer, 'Cipla Ltd');
    });

    test('reads a delimited key-value payload', () {
      final result = scanner.parsePayload(
        'GNM=Pantoprazole|STR=40mg|BNO=PZ99|EXP=06/2026',
      );

      expect(result.source, BarcodeSource.embedded);
      expect(result.name, 'Pantoprazole');
      expect(result.strength, '40mg');
      expect(result.batch, 'PZ99');
    });

    test('prefers the generic name over the brand name', () {
      // The generic is the clinically meaningful one, and it's what the
      // interaction database keys on.
      final result = scanner.parsePayload(
        '{"brandName":"Crocin","genericName":"Paracetamol"}',
      );

      expect(result.name, 'Paracetamol');
    });

    test('falls back to the brand name when no generic is given', () {
      final result = scanner.parsePayload('{"brandName":"Crocin"}');

      expect(result.name, 'Crocin');
    });

    test('an expiry month means the end of that month', () {
      // A pack marked 12/2027 is usable through 31 December.
      final result = scanner.parsePayload(
        '{"genericName":"Amoxicillin","expiry":"12/2027"}',
      );

      expect(result.expiry, DateTime(2027, 12, 31));
    });

    test('JSON carrying no name at all is not treated as identified', () {
      // Falls through to the plain branch rather than claiming an
      // "embedded" result with a null name.
      final result = scanner.parsePayload('{"batchNo":"AB1234"}');

      expect(result.hasName, isFalse);
    });
  });

  group('GS1 codes', () {
    test('reads a bracketed payload', () {
      final result = scanner.parsePayload('(01)08901234567890(17)261231(10)AB1234');

      expect(result.source, BarcodeSource.gs1);
      expect(result.rawValue, '08901234567890');
      expect(result.batch, 'AB1234');
      expect(result.expiry, DateTime(2026, 12, 31));
    });

    test('reads an unbracketed fixed-length payload', () {
      final result = scanner.parsePayload('010890123456789017261231');

      expect(result.source, BarcodeSource.gs1);
      expect(result.rawValue, '08901234567890');
      expect(result.expiry, DateTime(2026, 12, 31));
    });

    test('a GS1 day of 00 means the end of the month', () {
      final result = scanner.parsePayload('(01)08901234567890(17)261200');

      expect(result.expiry, DateTime(2026, 12, 31));
    });

    test('never claims to know the medicine', () {
      // GS1 identifies the pack exactly and says nothing about its contents.
      final result = scanner.parsePayload('(01)08901234567890(10)AB1234');

      expect(result.hasName, isFalse);
      expect(result.name, isNull);
    });
  });

  group('plain retail barcodes', () {
    test('a bare EAN-13 is just a number', () {
      final result = scanner.parsePayload('8901234567890');

      expect(result.source, BarcodeSource.plain);
      expect(result.rawValue, '8901234567890');
      expect(result.hasName, isFalse);
    });

    test('unrecognised text is kept verbatim as a lookup key', () {
      final result = scanner.parsePayload('SOMETHING-ODD-123');

      expect(result.source, BarcodeSource.plain);
      expect(result.rawValue, 'SOMETHING-ODD-123');
      expect(result.hasName, isFalse);
    });
  });

  group('malformed input is never mistaken for a medicine', () {
    test('broken JSON does not yield a name', () {
      expect(scanner.parsePayload('{"genericName":').hasName, isFalse);
    });

    test('an impossible expiry month is dropped, not clamped', () {
      final result = scanner.parsePayload(
        '{"genericName":"Amoxicillin","expiry":"13/2027"}',
      );

      expect(result.name, 'Amoxicillin');
      expect(result.expiry, isNull);
    });

    test('a truncated GS1 date is dropped', () {
      final result = scanner.parsePayload('(01)08901234567890(17)2612');

      expect(result.rawValue, '08901234567890');
      expect(result.expiry, isNull);
    });
  });
}
