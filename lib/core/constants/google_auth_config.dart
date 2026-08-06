import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Google Sign-In OAuth client, loaded from the `.env` file at runtime.
///
/// SETUP REQUIRED — this is a genuinely separate credential from Supabase's
/// own keys, created in Google's own console, not Supabase's:
/// 1. Go to https://console.cloud.google.com → APIs & Services → Credentials
///    (use the same project as your Firebase project, or create one).
/// 2. Create an OAuth 2.0 Client ID of type **Web application**. This one
///    "Web" client ID is what every platform uses here — Android/iOS pass it
///    as `serverClientId` so the ID token's audience matches, and web passes
///    it directly as `clientId`. You do NOT need separate Android/iOS client
///    IDs unless you want native one-tap UI on those platforms.
///    - Authorized JavaScript origins: add your web app's origin(s)
///      (e.g. http://localhost:PORT for local dev, your deployed domain).
/// 3. Copy that Web client ID into `.env` as GOOGLE_WEB_CLIENT_ID
///    (see `.env.example`).
/// 4. In the Supabase dashboard → Authentication → Providers → Google:
///    enable it and paste the same Web client ID + its Client Secret
///    (also from the Google Cloud credential's detail page). Supabase
///    verifies the ID token's audience against this, so it must match.
/// 5. For Android, also add your debug/release keystore's SHA-1 fingerprint
///    under an Android-type OAuth client in the same Google Cloud project
///    (needed for the native picker to launch at all) — the Web client ID
///    above still stays what's passed to `serverClientId` and to Supabase.
abstract final class GoogleAuthConfig {
  static String get webClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';

  /// True once a real (non-empty, non-placeholder) client ID is present.
  static bool get isConfigured =>
      webClientId.isNotEmpty &&
      webClientId.endsWith('.apps.googleusercontent.com');
}
