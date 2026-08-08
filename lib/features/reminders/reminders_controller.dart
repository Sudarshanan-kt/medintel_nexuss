import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/alarm_service.dart';
import 'data/medicines_repository.dart';
import 'domain/medicine.dart';
import 'notification_api.dart';

/// Combined state containing medicines list and dose history logs.
class MedicineManagerState {
  const MedicineManagerState({
    this.medicines = const [],
    this.logs = const [],
  });

  final List<Medicine> medicines;
  final List<DoseLog> logs;

  List<Medicine> get activeMedicines =>
      medicines.where((m) => m.isActive).toList();

  List<Medicine> get completedMedicines =>
      medicines.where((m) => !m.isActive).toList();

  MedicineManagerState copyWith({
    List<Medicine>? medicines,
    List<DoseLog>? logs,
  }) =>
      MedicineManagerState(
        medicines: medicines ?? this.medicines,
        logs: logs ?? this.logs,
      );
}

/// Controller for Medicine Manager — supports adding/editing medicines,
/// exact local alarm scheduling, dose logging (Taken/Missed/Snoozed),
/// active vs completed filtering, and dual persistence (SharedPreferences cache + Supabase sync).
class RemindersController extends Notifier<MedicineManagerState> {
  static const _medsCacheKey = 'medintel_medicines_v2';
  static const _logsCacheKey = 'medintel_dose_logs_v2';
  static const _legacyKey = 'medintel_reminders_v1';

  Timer? _timer;
  final Set<String> _firedKeys = {};

  @override
  MedicineManagerState build() {
    _restore();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    ref.onDispose(() => _timer?.cancel());
    return const MedicineManagerState();
  }

  void _log(String msg) => dev.log(msg, name: 'medicines.controller');

  /// The signed-in user, or null when there isn't one *or* Supabase hasn't
  /// finished initialising.
  ///
  /// Reading `Supabase.instance` before `Supabase.initialize` completes
  /// throws an assertion rather than returning null, which would take down
  /// a dose log made during cold start. Local state and the on-device cache
  /// are the source of truth here; the remote copy is a sync target, so
  /// losing it for one write is recoverable and crashing is not.
  String? get _userId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  MedicinesRepository get _repo => ref.read(medicinesRepositoryProvider);

  AlarmService get _alarmService => ref.read(alarmServiceProvider);

  // ── Restore & Persistence ──────────────────────────────────────────────────

  Future<void> _restore() async {
    await _restoreLocal();
    await _restoreRemote();
    _rescheduleAllActiveAlarms();
  }

  Future<void> _restoreLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final rawMeds = prefs.getString(_medsCacheKey);
      List<Medicine> meds = [];
      if (rawMeds != null && rawMeds.isNotEmpty) {
        meds = (jsonDecode(rawMeds) as List)
            .cast<Map<String, dynamic>>()
            .map(Medicine.fromJson)
            .toList();
      } else {
        final legacyRaw = prefs.getString(_legacyKey);
        if (legacyRaw != null && legacyRaw.isNotEmpty) {
          final legacyList = jsonDecode(legacyRaw) as List;
          for (final item in legacyList) {
            if (item is Map<String, dynamic>) {
              meds.add(
                Medicine(
                  id: (item['id'] as String?) ??
                      '${DateTime.now().microsecondsSinceEpoch}',
                  name: (item['medicine'] as String?) ?? 'Medicine',
                  dosage: (item['dosage'] as String?) ?? '',
                  startDate: DateTime.now(),
                  createdAt: DateTime.now(),
                ),
              );
            }
          }
        }
      }

      final rawLogs = prefs.getString(_logsCacheKey);
      List<DoseLog> logs = [];
      if (rawLogs != null && rawLogs.isNotEmpty) {
        logs = (jsonDecode(rawLogs) as List)
            .cast<Map<String, dynamic>>()
            .map(DoseLog.fromJson)
            .toList();
      }

      state = MedicineManagerState(medicines: meds, logs: logs);
    } catch (e) {
      _log('local restore ERROR: $e');
    }
  }

  Future<void> _restoreRemote() async {
    try {
      final userId = _userId;
      if (userId == null) return;

      final remoteMeds = await _repo.fetchAllMedicines(userId);
      final remoteLogs = await _repo.fetchAllDoseLogs(userId);

      if (remoteMeds.isEmpty && remoteLogs.isEmpty) return;

      final remoteMedIds = {for (final m in remoteMeds) m.id: m};
      final localOnlyMeds = state.medicines
          .where((m) => !remoteMedIds.containsKey(m.id))
          .toList();
      final mergedMeds = [...remoteMeds, ...localOnlyMeds];

      final remoteLogIds = {for (final l in remoteLogs) l.id: l};
      final localOnlyLogs = state.logs
          .where((l) => !remoteLogIds.containsKey(l.id))
          .toList();
      final mergedLogs = [...remoteLogs, ...localOnlyLogs];

      state = MedicineManagerState(medicines: mergedMeds, logs: mergedLogs);
      await _saveLocal();
    } catch (e) {
      _log('remote restore ERROR: $e');
    }
  }

  void _persistLocal() {
    final snap = state;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _medsCacheKey,
          jsonEncode(snap.medicines.map((m) => m.toJson()).toList()),
        );
        await prefs.setString(
          _logsCacheKey,
          jsonEncode(snap.logs.map((l) => l.toJson()).toList()),
        );
      } catch (e) {
        _log('persistLocal ERROR: $e');
      }
    }());
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _medsCacheKey,
        jsonEncode(state.medicines.map((m) => m.toJson()).toList()),
      );
      await prefs.setString(
        _logsCacheKey,
        jsonEncode(state.logs.map((l) => l.toJson()).toList()),
      );
    } catch (_) {}
  }

  void _upsertMedRemote(Medicine med) {
    final userId = _userId;
    if (userId == null) return;
    unawaited(
      _repo
          .upsertMedicine(userId, med)
          .timeout(const Duration(seconds: 8))
          .catchError((Object e) => _log('upsertMed ERROR: $e')),
    );
  }

  void _upsertLogRemote(DoseLog log) {
    final userId = _userId;
    if (userId == null) return;
    unawaited(
      _repo
          .upsertDoseLog(userId, log)
          .timeout(const Duration(seconds: 8))
          .catchError((Object e) => _log('upsertLog ERROR: $e')),
    );
  }

  // ── Alarm Rescheduling ───────────────────────────────────────────────────

  void _rescheduleAllActiveAlarms() {
    for (final med in state.activeMedicines) {
      _scheduleAlarmsForMedicine(med);
    }
  }

  void _scheduleAlarmsForMedicine(Medicine med) {
    if (!med.isActive || med.isCompleted) {
      _alarmService.cancelAllForMedicine(med);
      return;
    }
    if (med.morning) {
      _alarmService.scheduleMedicineAlarm(
        med,
        slot: 'morning',
        hour: med.morningHour,
        minute: med.morningMinute,
      );
    }
    if (med.afternoon) {
      _alarmService.scheduleMedicineAlarm(
        med,
        slot: 'afternoon',
        hour: med.afternoonHour,
        minute: med.afternoonMinute,
      );
    }
    if (med.night) {
      _alarmService.scheduleMedicineAlarm(
        med,
        slot: 'night',
        hour: med.nightHour,
        minute: med.nightMinute,
      );
    }
  }

  // ── Periodic fallback ticker ─────────────────────────────────────────────

  void _tick() {
    final now = DateTime.now();
    for (final med in state.activeMedicines) {
      if (med.morning && now.hour == med.morningHour && now.minute == med.morningMinute) {
        _fireNotification(med, 'Morning');
      } else if (med.afternoon && now.hour == med.afternoonHour && now.minute == med.afternoonMinute) {
        _fireNotification(med, 'Afternoon');
      } else if (med.night && now.hour == med.nightHour && now.minute == med.nightMinute) {
        _fireNotification(med, 'Night');
      }
    }
  }

  void _fireNotification(Medicine med, String slot) {
    final now = DateTime.now();
    final key = '${med.id}@$slot-${now.year}-${now.month}-${now.day}';
    if (_firedKeys.contains(key)) return;
    _firedKeys.add(key);

    showDeviceNotification(
      '💊 Time for ${med.name} ($slot)',
      med.dosage.isEmpty
          ? 'Tap to mark as taken.'
          : '${med.dosage} — tap to mark as taken.',
    );
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> addMedicine({
    required String name,
    required String dosage,
    required String frequency,
    required bool morning,
    int morningHour = 9,
    int morningMinute = 0,
    required bool afternoon,
    int afternoonHour = 14,
    int afternoonMinute = 0,
    required bool night,
    int nightHour = 21,
    int nightMinute = 0,
    required DateTime startDate,
    DateTime? endDate,
    required String purpose,
    String sound = 'default',
    String repeatType = 'daily',
  }) async {
    await _alarmService.requestPermissions();
    final med = Medicine(
      id: 'med_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Medicine' : name.trim(),
      dosage: dosage.trim(),
      frequency: frequency,
      morning: morning,
      morningHour: morningHour,
      morningMinute: morningMinute,
      afternoon: afternoon,
      afternoonHour: afternoonHour,
      afternoonMinute: afternoonMinute,
      night: night,
      nightHour: nightHour,
      nightMinute: nightMinute,
      startDate: startDate,
      endDate: endDate,
      purpose: purpose.trim(),
      sound: sound,
      repeatType: repeatType,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(medicines: [med, ...state.medicines]);
    _persistLocal();
    _upsertMedRemote(med);
    _scheduleAlarmsForMedicine(med);
  }

  void toggleCompleted(String id) {
    Medicine? updated;
    final meds = [
      for (final m in state.medicines)
        if (m.id == id)
          () {
            updated = m.copyWith(isCompleted: !m.isCompleted);
            return updated!;
          }()
        else
          m,
    ];
    state = state.copyWith(medicines: meds);
    _persistLocal();
    if (updated != null) {
      _upsertMedRemote(updated!);
      if (updated!.isCompleted) {
        _alarmService.cancelAllForMedicine(updated!);
      } else {
        _scheduleAlarmsForMedicine(updated!);
      }
    }
  }

  void deleteMedicine(String id) {
    final med = state.medicines.firstWhere(
      (m) => m.id == id,
      orElse: () => Medicine(
        id: id,
        name: '',
        dosage: '',
        startDate: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
    _alarmService.cancelAllForMedicine(med);

    state = state.copyWith(
      medicines: state.medicines.where((m) => m.id != id).toList(),
    );
    _persistLocal();
    final userId = _userId;
    if (userId != null) {
      unawaited(_repo.deleteMedicine(userId, id));
    }
  }

  /// Records the outcome of one scheduled dose.
  ///
  /// A dose is identified by medicine + slot + calendar day, and there can
  /// only ever be one outcome for it. Logging the same dose again *replaces*
  /// the previous entry rather than adding another.
  ///
  /// That matters because adherence is computed by counting logs: without
  /// this, tapping "Taken" twice counted two doses taken, so the percentage
  /// climbed every tap and could exceed what was actually scheduled. It also
  /// means changing your mind — marking taken after a snooze — corrects the
  /// record instead of leaving both entries in it.
  void logDose({
    required String medicineId,
    required String medicineName,
    required String dosage,
    required String scheduleSlot,
    required String status,
  }) {
    final now = DateTime.now();
    final existing = doseLogFor(
      medicineId: medicineId,
      scheduleSlot: scheduleSlot,
      day: now,
    );

    // Reuse the id so the remote row is updated rather than duplicated.
    final log = DoseLog(
      id: existing?.id ?? 'log_${now.microsecondsSinceEpoch}',
      medicineId: medicineId,
      medicineName: medicineName,
      dosage: dosage,
      scheduleSlot: scheduleSlot,
      timestamp: now,
      status: status,
    );

    state = state.copyWith(
      logs: [
        log,
        ...state.logs.where((l) => l.id != log.id),
      ],
    );
    _persistLocal();
    _upsertLogRemote(log);
  }

  /// The recorded outcome for one dose on [day], or null if it hasn't been
  /// acted on yet.
  ///
  /// Shared by every surface that shows a dose, so the dashboard and the
  /// reminders screen can't disagree about whether it's been taken.
  DoseLog? doseLogFor({
    required String medicineId,
    required String scheduleSlot,
    required DateTime day,
  }) {
    for (final log in state.logs) {
      if (log.medicineId == medicineId &&
          log.scheduleSlot == scheduleSlot &&
          log.timestamp.year == day.year &&
          log.timestamp.month == day.month &&
          log.timestamp.day == day.day) {
        return log;
      }
    }
    return null;
  }

  void snoozeDose({
    required Medicine medicine,
    required String slot,
    required int minutes,
  }) {
    logDose(
      medicineId: medicine.id,
      medicineName: medicine.name,
      dosage: medicine.dosage,
      scheduleSlot: slot,
      status: 'snoozed',
    );
    _alarmService.scheduleSnoozeAlarm(
      medicine,
      slot: slot,
      minutes: minutes,
    );
  }

  void deleteDoseLog(String id) {
    state = state.copyWith(
      logs: state.logs.where((l) => l.id != id).toList(),
    );
    _persistLocal();
    final userId = _userId;
    if (userId != null) {
      unawaited(_repo.deleteDoseLog(userId, id));
    }
  }

  Future<void> sendTest() async {
    final ok = await _alarmService.requestPermissions();
    showDeviceNotification(
      '💊 MedIntel Alarm Test',
      ok
          ? 'Exact alarms are enabled on this device.'
          : 'Exact alarm permissions are required for medicine alerts.',
    );
  }
}

final remindersControllerProvider =
    NotifierProvider<RemindersController, MedicineManagerState>(
  RemindersController.new,
);
