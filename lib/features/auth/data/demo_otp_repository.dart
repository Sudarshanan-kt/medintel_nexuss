import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads back the code Auth just generated, so the sign-in screen can show it
/// instead of a text message arriving.
///
/// The code is Supabase's own — generated, expired and verified by Auth
/// exactly as it would be for a real SMS. A Send SMS hook
/// (`supabase/migrations/20260815193000_demo_otp_on_screen.sql`) writes it to
/// `demo_otp_codes` in place of handing it to a provider, and this reads the
/// row. Different every sign-in, because Auth generates a new one every time.
///
/// Only numbers listed in `demo_otp_phones` are readable, and the hook
/// refuses to send for anything else. That allowlist is the only thing
/// standing between this and "anyone with the anon key can sign in as
/// anyone", so it matters — see the migration's header.
class DemoOtpRepository {
  DemoOtpRepository(this._supabase);

  final SupabaseClient _supabase;

  /// A code older than this is treated as absent. Auth expires SMS codes on
  /// its own schedule; showing a superseded one would have the caregiver
  /// typing something that cannot work.
  static const _freshFor = Duration(minutes: 2);

  /// The current code for [phoneE164], or null if there isn't a usable one.
  ///
  /// Never throws: this is a demo affordance layered on a sign-in that has
  /// already succeeded, and a failure to display the code must not look like
  /// a failure to send it.
  Future<String?> latestCodeFor(String phoneE164) async {
    // Auth stores the number the way `formatPhoneNumber` leaves it — digits
    // only, no leading "+".
    final digits = phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
    try {
      final row = await _supabase
          .from('demo_otp_codes')
          .select('code, created_at')
          .eq('phone', digits)
          .maybeSingle();
      if (row == null) return null;

      final created = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (created == null) return null;
      if (DateTime.now().toUtc().difference(created.toUtc()) > _freshFor) {
        return null;
      }
      final code = row['code'] as String?;
      return (code == null || code.isEmpty) ? null : code;
    } catch (e) {
      debugPrint('Demo OTP lookup failed: $e');
      return null;
    }
  }
}

final demoOtpRepositoryProvider = Provider<DemoOtpRepository>(
  (ref) => DemoOtpRepository(Supabase.instance.client),
);
