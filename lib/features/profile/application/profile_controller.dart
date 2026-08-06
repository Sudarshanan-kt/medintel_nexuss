import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/utils/result.dart';
import '../../auth/application/auth_controller.dart';
import '../data/health_profile_repository.dart';
import '../domain/profile_record.dart';

/// In-memory + secure-storage-backed profile state, with Supabase as the
/// remote source of truth.
///
/// **Hydration order** (cold boot / login):
///   1. Return `ProfileRecord.initial` immediately so the UI never blanks.
///   2. Read secure-storage cache for instant local rendering.
///   3. Fetch from Supabase and merge — remote wins for all medical fields.
///   4. Re-populate the secure-storage cache from the merged result.
///
/// **Sync on every mutation**: every method that changes medical data also
/// fires `_syncToSupabase()` so Profile-screen edits are always persisted
/// to the cloud.
class ProfileController extends Notifier<ProfileRecord> {
  static const _kPersonal = 'mn_profile_personal';
  static const _kAllergies = 'mn_profile_allergies';
  static const _kConditions = 'mn_profile_conditions';
  static const _kMedicines = 'mn_profile_medicines';
  static const _kContacts = 'mn_profile_contacts';
  static const _kBiometric = 'mn_profile_biometric';
  static const _kNotifications = 'mn_profile_notifications';
  static const _kLanguage = 'mn_profile_language';

  FlutterSecureStorage get _storage => ref.read(secureStorageProvider);
  BiometricService get _biometric => ref.read(biometricServiceProvider);
  HealthProfileRepository get _hpRepo =>
      ref.read(healthProfileRepositoryProvider);

  @override
  ProfileRecord build() {
    // Async hydrate; until storage answers, render initial state so the UI
    // never blanks.
    Future.microtask(_hydrate);
    return ProfileRecord.initial;
  }

  Future<void> _hydrate() async {
    try {
      // ── 1. Read local cache ─────────────────────────────────────────────
      final personalRaw = await _storage.read(key: _kPersonal);
      final allergiesRaw = await _storage.read(key: _kAllergies);
      final conditionsRaw = await _storage.read(key: _kConditions);
      final medicinesRaw = await _storage.read(key: _kMedicines);
      final contactsRaw = await _storage.read(key: _kContacts);
      final biometricRaw = await _storage.read(key: _kBiometric);
      final notificationsRaw = await _storage.read(key: _kNotifications);
      final languageRaw = await _storage.read(key: _kLanguage);

      // Personal block: restore from cache, or seed from the signed-in user
      // the first time (and persist that seed so it is stable thereafter).
      PersonalDetails personal;
      if (personalRaw != null) {
        personal = PersonalDetails.fromJson(
          (jsonDecode(personalRaw) as Map).cast<String, dynamic>(),
        );
      } else {
        personal = _seedFromAuth();
        if (personal.fullName.isNotEmpty ||
            personal.phone.isNotEmpty ||
            personal.email.isNotEmpty) {
          await _storage.write(
            key: _kPersonal,
            value: jsonEncode(personal.toJson()),
          );
        }
      }

      // Apply cached values immediately so UI is responsive while Supabase loads.
      state = ProfileRecord(
        personal: personal,
        allergies: allergiesRaw != null
            ? (jsonDecode(allergiesRaw) as List).cast<String>()
            : state.allergies,
        conditions: conditionsRaw != null
            ? (jsonDecode(conditionsRaw) as List).cast<String>()
            : state.conditions,
        currentMedicines: medicinesRaw != null
            ? (jsonDecode(medicinesRaw) as List).cast<String>()
            : state.currentMedicines,
        emergencyContacts: contactsRaw != null
            ? (jsonDecode(contactsRaw) as List)
                .map(
                  (e) => EmergencyContact.fromJson(e as Map<String, dynamic>),
                )
                .toList()
            : state.emergencyContacts,
        biometricEnabled: biometricRaw != null
            ? biometricRaw == 'true'
            : state.biometricEnabled,
        notifications: notificationsRaw != null
            ? NotificationLevel.values.byName(notificationsRaw)
            : state.notifications,
        language: languageRaw != null
            ? AppLanguage.fromCode(languageRaw)
            : state.language,
      );

      // ── 2. Fetch from Supabase and merge (remote wins for medical data) ──
      await _hydrateFromSupabase();
    } catch (_) {/* ignore hydrate errors — fall back to initial */}
  }

  /// Fetches the health profile row from Supabase and merges it into state.
  ///
  /// Supabase is authoritative for all medical fields (allergies, conditions,
  /// medicines, contacts, personal metrics). Preferences (biometric, language,
  /// notifications) are device-local and are not overwritten.
  Future<void> _hydrateFromSupabase() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;

      final result = await _hpRepo.loadHealthProfile(userId);

      // Unpack imperatively so the async cache writes are properly awaited.
      if (result is! Success<HealthProfileData?>) return;
      final data = result.value;
      if (data == null) return; // No profile yet — onboarding not done.


      // Merge remote data into local state.
      final merged = state.copyWith(
        personal: state.personal.copyWith(
          gender: data.gender.isNotEmpty ? data.gender : null,
          bloodGroup: data.bloodGroup.isNotEmpty ? data.bloodGroup : null,
          dateOfBirth: data.dateOfBirth,
          heightCm: data.heightCm.isNotEmpty ? data.heightCm : null,
          weightKg: data.weightKg.isNotEmpty ? data.weightKg : null,
        ),
        allergies: List.unmodifiable(data.allergies),
        conditions: List.unmodifiable(data.conditions),
        currentMedicines: List.unmodifiable(data.currentMedicines),
        emergencyContacts: data.emergencyContacts,
      );
      state = merged;

      // Refresh local cache from the merged result so the next cold boot
      // is instant and consistent with what Supabase returned.
      await _storage.write(
        key: _kPersonal,
        value: jsonEncode(merged.personal.toJson()),
      );
      await _storage.write(
        key: _kAllergies,
        value: jsonEncode(merged.allergies.toList()),
      );
      await _storage.write(
        key: _kConditions,
        value: jsonEncode(merged.conditions.toList()),
      );
      await _storage.write(
        key: _kMedicines,
        value: jsonEncode(merged.currentMedicines.toList()),
      );
      await _storage.write(
        key: _kContacts,
        value: jsonEncode(
          merged.emergencyContacts.map((c) => c.toJson()).toList(),
        ),
      );
    } catch (_) {/* ignore — local cache is still valid */}
  }


  /// Builds an initial personal block from the authenticated user.
  PersonalDetails _seedFromAuth() {
    final user = ref.read(authControllerProvider).valueOrNull?.user;
    if (user == null) return PersonalDetails.empty;
    return PersonalDetails(
      fullName: user.fullName ?? '',
      phone: user.phone ?? '',
      email: user.email ?? '',
    );
  }

  String? get _currentUserId =>
      ref.read(authControllerProvider).valueOrNull?.user?.id;

  // ── Supabase sync helper ─────────────────────────────────────────────────

  /// Writes the current [state] to Supabase. Called after every local
  /// mutation so the remote row stays in sync with the device.
  ///
  /// Errors are silently swallowed — local state is already updated and
  /// the user's UX must not be disrupted by a transient network issue.
  Future<void> _syncToSupabase() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;
      await _hpRepo.saveHealthProfile(
        userId: userId,
        personal: state.personal,
        allergies: state.allergies.toList(),
        conditions: state.conditions.toList(),
        currentMedicines: state.currentMedicines.toList(),
        emergencyContacts: state.emergencyContacts,
      );
    } catch (_) {/* silent — local state is the source of truth for UX */}
  }

  // ── Personal details ─────────────────────────────────────────────────────

  Future<void> savePersonalDetails(PersonalDetails next) async {
    state = state.copyWith(personal: next);
    await _storage.write(
      key: _kPersonal,
      value: jsonEncode(next.toJson()),
    );
    await _syncToSupabase();
  }

  // ── Allergies ────────────────────────────────────────────────────────────

  Future<void> setAllergies(List<String> next) async {
    state = state.copyWith(allergies: List.unmodifiable(next));
    await _storage.write(key: _kAllergies, value: jsonEncode(next));
    await _syncToSupabase();
  }

  // ── Conditions ───────────────────────────────────────────────────────────

  Future<void> setConditions(List<String> next) async {
    state = state.copyWith(conditions: List.unmodifiable(next));
    await _storage.write(key: _kConditions, value: jsonEncode(next));
    await _syncToSupabase();
  }

  // ── Current medicines ────────────────────────────────────────────────────

  Future<void> setCurrentMedicines(List<String> next) async {
    state = state.copyWith(currentMedicines: List.unmodifiable(next));
    await _storage.write(key: _kMedicines, value: jsonEncode(next));
    await _syncToSupabase();
  }

  // ── Emergency contacts ───────────────────────────────────────────────────

  Future<void> addEmergencyContact(EmergencyContact c) async {
    final next = [...state.emergencyContacts, c];
    state = state.copyWith(emergencyContacts: next);
    await _persistContacts();
    await _syncToSupabase();
  }

  Future<void> updateEmergencyContact(EmergencyContact c) async {
    final next = [
      for (final existing in state.emergencyContacts)
        if (existing.id == c.id) c else existing,
    ];
    state = state.copyWith(emergencyContacts: next);
    await _persistContacts();
    await _syncToSupabase();
  }

  Future<void> removeEmergencyContact(String id) async {
    final next = state.emergencyContacts.where((c) => c.id != id).toList();
    state = state.copyWith(emergencyContacts: next);
    await _persistContacts();
    await _syncToSupabase();
  }

  Future<void> _persistContacts() async {
    await _storage.write(
      key: _kContacts,
      value: jsonEncode(
        state.emergencyContacts.map((c) => c.toJson()).toList(),
      ),
    );
  }

  // ── Biometric ────────────────────────────────────────────────────────────

  /// Enables or disables biometric unlock.
  ///
  /// When enabling: triggers a real biometric prompt first — preference is
  /// only persisted if the user passes. Returns the error message if
  /// unavailable or authentication failed, or null on success.
  Future<String?> setBiometric(bool enabled) async {
    if (enabled) {
      final available = await _biometric.isAvailable();
      if (!available) {
        return 'No biometrics enrolled on this device. '
            'Set up fingerprint or Face ID in device Settings first.';
      }
      final passed = await _biometric.authenticate(
        reason: 'Confirm your identity to enable biometric unlock',
      );
      if (!passed) {
        return 'Biometric authentication failed. '
            'Biometric unlock was not enabled.';
      }
    }
    await _biometric.setEnabled(enabled: enabled);
    state = state.copyWith(biometricEnabled: enabled);
    await _storage.write(key: _kBiometric, value: enabled.toString());
    return null;
  }

  // ── Preferences (local-only, not synced to Supabase) ────────────────────

  Future<void> setNotifications(NotificationLevel level) async {
    state = state.copyWith(notifications: level);
    await _storage.write(key: _kNotifications, value: level.name);
  }

  Future<void> setLanguage(AppLanguage lang) async {
    state = state.copyWith(language: lang);
    await _storage.write(key: _kLanguage, value: lang.code);
  }
}

final profileControllerProvider =
    NotifierProvider<ProfileController, ProfileRecord>(
  ProfileController.new,
);



