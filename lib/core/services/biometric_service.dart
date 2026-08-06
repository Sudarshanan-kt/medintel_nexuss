import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../network/dio_client.dart';

/// Wraps `local_auth` and the secure-storage biometric preference.
///
/// All interaction with biometrics goes through this service so the rest of
/// the app stays decoupled from `local_auth`.
class BiometricService {
  BiometricService(this._storage);

  final FlutterSecureStorage _storage;
  final _auth = LocalAuthentication();

  static const _kBiometricEnabled = 'mn_biometric_enabled';

  // ── Capability ────────────────────────────────────────────────────────────

  /// Returns true when the device has biometrics enrolled AND the hardware
  /// supports it (Touch ID, Face ID, fingerprint, etc.).
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isDeviceSupported) return false;
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Authenticate ──────────────────────────────────────────────────────────

  /// Shows the system biometric prompt with [reason].
  ///
  /// Returns `true` on success, `false` on failure or cancellation.
  Future<bool> authenticate({
    String reason = 'Confirm your identity to continue',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow PIN/pattern fallback
          stickyAuth: true,    // keep prompt alive across app backgrounding
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ── Preference ────────────────────────────────────────────────────────────

  /// Reads the stored biometric-enabled preference.
  Future<bool> isEnabled() async {
    final v = await _storage.read(key: _kBiometricEnabled);
    return v == 'true';
  }

  /// Persists the biometric preference.
  ///
  /// Call this **only** after a successful [authenticate] call so the
  /// preference is never flipped without user verification.
  Future<void> setEnabled({required bool enabled}) async {
    await _storage.write(
      key: _kBiometricEnabled,
      value: enabled.toString(),
    );
  }

  // ── App-launch gate ───────────────────────────────────────────────────────

  /// Should be called from the Splash screen after a session is restored.
  ///
  /// Returns `true` if the app should proceed (biometric passed, or not
  /// enabled, or hardware unavailable). Returns `false` if the user failed /
  /// cancelled biometric — caller should sign out.
  Future<bool> gateForAppLaunch() async {
    final enabled = await isEnabled();
    if (!enabled) return true;
    final available = await isAvailable();
    if (!available) return true; // hardware gone — don't lock user out
    return authenticate(reason: 'Unlock MedIntel Nexus');
  }
}

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService(ref.read(secureStorageProvider));
});
