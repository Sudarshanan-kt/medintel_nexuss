import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A medicine the patient has previously identified for a given barcode.
class RememberedMedicine {
  const RememberedMedicine({
    required this.name,
    this.strength,
    required this.savedAt,
  });

  final String name;
  final String? strength;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'strength': strength,
        'savedAt': savedAt.toIso8601String(),
      };

  static RememberedMedicine? fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    return RememberedMedicine(
      name: name,
      strength: (json['strength'] as String?)?.trim(),
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Remembers which medicine a barcode belongs to, so a pack only has to be
/// identified once.
///
/// This exists because most medicine barcodes are just a product number,
/// and there's no free database mapping those to Indian drug names. Rather
/// than that being a dead end, the first scan of an unknown pack asks the
/// patient what it is and the answer is kept — every scan after that is
/// instant.
///
/// Two deliberate constraints:
///
/// * **Only what the patient confirmed is stored.** Nothing is written from
///   an OCR guess or an unverified reading, because a wrong name here would
///   be silently reapplied to every future scan of that pack.
/// * **Nothing is shared between users.** A mapping is one person's note
///   about their own medicine cabinet. Pooling them would mean one person's
///   mistake could put the wrong drug name in someone else's reminder.
class BarcodeMemory {
  static const _key = 'medintel_barcode_medicines_v1';

  Future<Map<String, RememberedMedicine>> _readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return {};

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};

      final out = <String, RememberedMedicine>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final remembered =
            RememberedMedicine.fromJson(value.cast<String, dynamic>());
        if (remembered != null) out[entry.key.toString()] = remembered;
      }
      return out;
    } catch (e) {
      dev.log('BarcodeMemory read failed: $e', name: 'reminders.barcode');
      return {};
    }
  }

  /// What this barcode was last confirmed to be, or null if it's new.
  Future<RememberedMedicine?> lookup(String barcode) async {
    final key = _normalize(barcode);
    if (key.isEmpty) return null;
    return (await _readAll())[key];
  }

  /// Records the patient's own identification of [barcode].
  ///
  /// Call this only once they have confirmed the name — see the class doc.
  Future<void> remember(
    String barcode, {
    required String name,
    String? strength,
  }) async {
    final key = _normalize(barcode);
    if (key.isEmpty || name.trim().isEmpty) return;

    try {
      final all = await _readAll();
      all[key] = RememberedMedicine(
        name: name.trim(),
        strength: strength?.trim().isEmpty ?? true ? null : strength!.trim(),
        savedAt: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
      );
    } catch (e) {
      dev.log('BarcodeMemory write failed: $e', name: 'reminders.barcode');
    }
  }

  /// Drops a mapping — for when a barcode was saved against the wrong name.
  Future<void> forget(String barcode) async {
    final key = _normalize(barcode);
    if (key.isEmpty) return;
    try {
      final all = await _readAll()..remove(key);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
      );
    } catch (e) {
      dev.log('BarcodeMemory forget failed: $e', name: 'reminders.barcode');
    }
  }

  /// Barcodes carry stray whitespace and, on some symbologies, a leading
  /// zero that comes and goes between readers. Normalising both keeps the
  /// same physical pack from being remembered twice.
  String _normalize(String barcode) {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return '';
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      final withoutLeadingZeros = trimmed.replaceFirst(RegExp(r'^0+'), '');
      return withoutLeadingZeros.isEmpty ? trimmed : withoutLeadingZeros;
    }
    return trimmed;
  }
}

final barcodeMemoryProvider = Provider<BarcodeMemory>((ref) => BarcodeMemory());
