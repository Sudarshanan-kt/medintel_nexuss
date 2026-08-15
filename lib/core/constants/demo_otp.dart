import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Whether caregiver sign-in shows its code on screen instead of texting it.
///
/// There is no SMS provider behind caregiver sign-in, and getting one that
/// delivers to an Indian number means DLT registration with TRAI — a
/// registered business entity, an approved header and an approved template.
/// For a demo that is the whole project's worth of paperwork to watch one
/// screen work.
///
/// Nothing about the sign-in is faked. Auth generates the code, expires it
/// and verifies it exactly as it would for a real message; a Send SMS hook
/// writes it to a table instead of handing it to a provider, and
/// [DemoOtpRepository] reads it back for display. A new code every time,
/// and a real Supabase session at the end of it.
///
/// SETUP — both halves, or the screen shows nothing:
/// 1. `.env`: `DEMO_OTP_ON_SCREEN=true`.
/// 2. The database side, once, per
///    `supabase/migrations/20260815193000_demo_otp_on_screen.sql`:
///    apply it, add each demo number to `demo_otp_phones` (digits only, no
///    `+`), then Dashboard → Authentication → Hooks → Send SMS hook →
///    Postgres → `public.send_sms_hook`. Clear the Phone provider's Test OTP
///    field while you're there: Auth checks that list first, and a number
///    listed in it never reaches the hook.
///
/// A code readable without a session is a code anyone holding the anon key
/// can read, and reading it is enough to sign in as that number. The
/// allowlist keeps that to numbers you own. Turn this off, and drop the
/// migration, before the project holds anyone's real health data.
abstract final class DemoOtpConfig {
  static bool get isEnabled {
    // Widget tests build this screen without loading .env at all.
    if (!dotenv.isInitialized) return false;
    return dotenv.env['DEMO_OTP_ON_SCREEN']?.trim().toLowerCase() == 'true';
  }
}
