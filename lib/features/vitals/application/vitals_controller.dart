import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/vitals_repository.dart';
import '../domain/vital_reading.dart';

class VitalsState {
  const VitalsState({this.readings = const []});
  final List<VitalReading> readings;

  List<VitalReading> byType(VitalType type) =>
      readings.where((r) => r.type == type).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  /// Most recent reading of each type, or null if none logged yet.
  VitalReading? latest(VitalType type) {
    final list = byType(type);
    return list.isEmpty ? null : list.first;
  }
}

/// Manages the patient's self-logged vitals — same dual persistence
/// approach as RemindersController (local cache for instant UI, Supabase
/// for cross-device sync).
class VitalsController extends Notifier<VitalsState> {
  static const _cacheKey = 'medintel_vitals_v1';

  VitalsRepository get _repo => ref.read(vitalsRepositoryProvider);
  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  @override
  VitalsState build() {
    Future.microtask(_restore);
    return const VitalsState();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(VitalReading.fromJson)
            .toList();
        state = VitalsState(readings: list);
      }
    } catch (_) {/* fall back to empty */}

    final uid = _userId;
    if (uid == null) return;
    try {
      final remote = await _repo.fetchAll(uid);
      if (remote.isNotEmpty) {
        state = VitalsState(readings: remote);
        await _persistLocal();
      }
    } catch (_) {/* offline — local cache stands */}
  }

  Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(state.readings.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> addReading({
    required VitalType type,
    required double value,
    double? secondaryValue,
    String? note,
  }) async {
    final reading = VitalReading(
      id: 'vital_${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      value: value,
      secondaryValue: secondaryValue,
      timestamp: DateTime.now(),
      note: note,
    );
    state = VitalsState(readings: [reading, ...state.readings]);
    unawaited(_persistLocal());

    final uid = _userId;
    if (uid != null) {
      unawaited(
        _repo.upsertReading(uid, reading).catchError((_) {}),
      );
    }
  }

  Future<void> deleteReading(String id) async {
    state = VitalsState(
      readings: state.readings.where((r) => r.id != id).toList(),
    );
    unawaited(_persistLocal());
    final uid = _userId;
    if (uid != null) {
      unawaited(_repo.deleteReading(uid, id).catchError((_) {}));
    }
  }
}

final vitalsControllerProvider =
    NotifierProvider<VitalsController, VitalsState>(VitalsController.new);
