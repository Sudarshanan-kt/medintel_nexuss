import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/reminders/adherence_controller.dart';
import 'package:medintel_nexus/features/reminders/domain/medicine.dart';
import 'package:medintel_nexus/features/reminders/reminders_controller.dart';

/// A dose is medicine + slot + calendar day, and it has exactly one outcome.
///
/// Before this was enforced, every tap of "Mark taken" appended another log.
/// Adherence is computed by counting logs, so the percentage climbed with
/// each tap and could report more doses taken than were ever scheduled — on
/// a screen a patient uses to decide whether they've taken their medicine.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  RemindersController controller() =>
      container.read(remindersControllerProvider.notifier);

  void markTaken({String slot = 'morning'}) {
    controller().logDose(
      medicineId: 'm1',
      medicineName: 'Paracetamol',
      dosage: '650 mg',
      scheduleSlot: slot,
      status: 'taken',
    );
  }

  group('logDose is one outcome per dose', () {
    test('marking the same dose taken twice keeps a single log', () {
      markTaken();
      markTaken();

      final logs = container.read(remindersControllerProvider).logs;
      expect(logs.where((l) => l.medicineId == 'm1'), hasLength(1));
    });

    test('five taps still only ever count as one dose', () {
      // The reported bug: the button stayed available, so a patient could
      // tap it repeatedly and watch the percentage rise.
      for (var i = 0; i < 5; i++) {
        markTaken();
      }

      expect(container.read(remindersControllerProvider).logs, hasLength(1));
    });

    test('different slots of the same medicine are separate doses', () {
      markTaken(slot: 'morning');
      markTaken(slot: 'night');

      expect(container.read(remindersControllerProvider).logs, hasLength(2));
    });

    test('changing your mind corrects the record rather than appending', () {
      controller().logDose(
        medicineId: 'm1',
        medicineName: 'Paracetamol',
        dosage: '650 mg',
        scheduleSlot: 'morning',
        status: 'skipped',
      );
      markTaken();

      final logs = container.read(remindersControllerProvider).logs;
      expect(logs, hasLength(1));
      expect(logs.single.status, 'taken');
    });

    test('the replacement reuses the id so the remote row updates', () {
      markTaken();
      final firstId = container.read(remindersControllerProvider).logs.single.id;
      markTaken();

      expect(
        container.read(remindersControllerProvider).logs.single.id,
        firstId,
        reason: 'a new id would create a duplicate row server-side',
      );
    });
  });

  group('doseLogFor', () {
    test('finds a dose logged today', () {
      markTaken();

      final found = controller().doseLogFor(
        medicineId: 'm1',
        scheduleSlot: 'morning',
        day: DateTime.now(),
      );
      expect(found, isNotNull);
      expect(found!.status, 'taken');
    });

    test('returns null for a dose that has not been acted on', () {
      markTaken(slot: 'morning');

      expect(
        controller().doseLogFor(
          medicineId: 'm1',
          scheduleSlot: 'night',
          day: DateTime.now(),
        ),
        isNull,
      );
    });

    test('does not match another day', () {
      markTaken();

      expect(
        controller().doseLogFor(
          medicineId: 'm1',
          scheduleSlot: 'morning',
          day: DateTime.now().subtract(const Duration(days: 1)),
        ),
        isNull,
        reason: 'yesterday\'s dose is a different dose',
      );
    });
  });

  group('adherence cannot be inflated', () {
    test('repeated taps do not raise the weekly percentage', () {
      markTaken();
      final afterOne =
          container.read(adherenceStateProvider).weeklyPercent;

      for (var i = 0; i < 4; i++) {
        markTaken();
      }
      final afterFive =
          container.read(adherenceStateProvider).weeklyPercent;

      expect(afterFive, afterOne);
    });

    test('a taken dose never counts as more than 100%', () {
      for (var i = 0; i < 10; i++) {
        markTaken();
      }

      expect(
        container.read(adherenceStateProvider).weeklyPercent,
        lessThanOrEqualTo(100),
      );
    });
  });

  group('Medicine slots', () {
    test('a medicine can be scheduled for more than one slot', () {
      // Guards the assumption _nextDoseSlot relies on: each enabled slot is
      // an independent dose that needs its own outcome.
      final med = Medicine(
        id: 'm1',
        name: 'Paracetamol',
        dosage: '650 mg',
        morning: true,
        night: true,
        startDate: DateTime.now(),
        createdAt: DateTime.now(),
      );

      expect(med.morning, isTrue);
      expect(med.night, isTrue);
      expect(med.afternoon, isFalse);
    });
  });
}
