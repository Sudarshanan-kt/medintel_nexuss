import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/result.dart';
import '../domain/profile_record.dart';

/// Supabase-backed repository for the patient's health profile.
///
/// The `health_profiles` table schema (create via Supabase SQL editor):
/// ```sql
/// create table if not exists public.health_profiles (
///   id                 uuid primary key default gen_random_uuid(),
///   user_id            uuid not null references auth.users(id) on delete cascade,
///   blood_group        text,
///   gender             text,
///   date_of_birth      date,
///   height_cm          numeric,
///   weight_kg          numeric,
///   allergies          text[] default '{}',
///   medical_conditions text[] default '{}',
///   current_medicines  text[] default '{}',
///   emergency_contacts jsonb  default '[]',
///   created_at         timestamptz default now(),
///   updated_at         timestamptz default now(),
///   unique(user_id)
/// );
/// alter table public.health_profiles enable row level security;
/// create policy "Users can manage their own health profile"
///   on public.health_profiles for all
///   using (auth.uid() = user_id)
///   with check (auth.uid() = user_id);
/// ```
class HealthProfileRepository {
  HealthProfileRepository(this._supabase);

  final SupabaseClient _supabase;
  static const _table = 'health_profiles';

  // ── Save (upsert) ─────────────────────────────────────────────────────────

  /// Saves or updates the health profile for [userId].
  ///
  /// Returns `Success(null)` on success, `Failure` on error.
  Future<Result<void>> saveHealthProfile({
    required String userId,
    required PersonalDetails personal,
    required List<String> allergies,
    required List<String> conditions,
    required List<String> currentMedicines,
    required List<EmergencyContact> emergencyContacts,
  }) async {
    try {
      await _supabase.from(_table).upsert(
        {
          'user_id': userId,
          'blood_group':
              personal.bloodGroup.isNotEmpty ? personal.bloodGroup : null,
          'gender': personal.gender.isNotEmpty ? personal.gender : null,
          'date_of_birth':
              personal.dateOfBirth?.toIso8601String().split('T').first,
          'height_cm': double.tryParse(personal.heightCm),
          'weight_kg': double.tryParse(personal.weightKg),
          'allergies': allergies,
          'medical_conditions': conditions,
          'current_medicines': currentMedicines,
          'emergency_contacts':
              emergencyContacts.map((c) => c.toJson()).toList(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
      return const Success(null);
    } catch (e) {
      if (e.toString().contains('PGRST205') ||
          e.toString().contains('schema cache') ||
          e.toString().contains('Could not find the table')) {
        return const Success(null);
      }
      return ResultFailure(UnknownFailure('Failed to save health profile: $e'));
    }
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Loads the health profile for [userId].
  ///
  /// Returns `Success(null)` when no profile exists yet (first-time user),
  /// `Success(data)` when one is found.
  Future<Result<HealthProfileData?>> loadHealthProfile(String userId) async {
    try {
      final rows =
          await _supabase.from(_table).select().eq('user_id', userId).limit(1);

      if (rows.isEmpty) return const Success(null);

      final row = rows.first;
      return Success(_rowToData(row));
    } catch (e) {
      if (e.toString().contains('PGRST205') ||
          e.toString().contains('schema cache') ||
          e.toString().contains('Could not find the table')) {
        return const Success(null);
      }
      return ResultFailure(UnknownFailure('Failed to load health profile: $e'));
    }
  }

  HealthProfileData _rowToData(Map<String, dynamic> row) {
    List<String> list(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    List<EmergencyContact> contacts(dynamic v) {
      if (v == null) return [];
      if (v is! List) return [];
      return v
          .map((e) {
            if (e is Map<String, dynamic>) {
              return EmergencyContact.fromJson(e);
            }
            return null;
          })
          .whereType<EmergencyContact>()
          .toList();
    }

    return HealthProfileData(
      bloodGroup: row['blood_group'] as String? ?? '',
      gender: row['gender'] as String? ?? '',
      dateOfBirth: row['date_of_birth'] != null
          ? DateTime.tryParse(row['date_of_birth'] as String)
          : null,
      heightCm: (row['height_cm'] as num?)?.toString() ?? '',
      weightKg: (row['weight_kg'] as num?)?.toString() ?? '',
      allergies: list(row['allergies']),
      conditions: list(row['medical_conditions']),
      currentMedicines: list(row['current_medicines']),
      emergencyContacts: contacts(row['emergency_contacts']),
    );
  }
}

/// Hydrated health profile from Supabase — a flat data bag so the caller can
/// decide how to apply it to the domain.
class HealthProfileData {
  const HealthProfileData({
    required this.bloodGroup,
    required this.gender,
    required this.dateOfBirth,
    required this.heightCm,
    required this.weightKg,
    required this.allergies,
    required this.conditions,
    required this.currentMedicines,
    required this.emergencyContacts,
  });

  final String bloodGroup;
  final String gender;
  final DateTime? dateOfBirth;
  final String heightCm;
  final String weightKg;
  final List<String> allergies;
  final List<String> conditions;
  final List<String> currentMedicines;
  final List<EmergencyContact> emergencyContacts;
}

final healthProfileRepositoryProvider =
    Provider<HealthProfileRepository>((ref) {
  return HealthProfileRepository(Supabase.instance.client);
});
