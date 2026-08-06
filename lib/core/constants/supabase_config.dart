import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase project credentials, loaded from the `.env` file at runtime.
///
/// SETUP REQUIRED:
/// 1. Go to https://supabase.com and create / open your project.
/// 2. Navigate to Project Settings → API.
/// 3. Copy the "Project URL" and "anon public" key into `.env`
///    (see `.env.example` for the expected keys).
/// 4. `.env` is already gitignored — never commit real keys.
abstract final class SupabaseConfig {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// True once `.env` has been loaded and both values look like real
  /// Supabase credentials rather than empty/placeholder strings.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      supabaseUrl.startsWith('http') &&
      !supabaseUrl.contains('your-project-ref');

  /// Deep-link redirect scheme registered in AndroidManifest.xml & Info.plist.
  /// Must match what you set in the Supabase dashboard → Auth → URL Configuration.
  static const String redirectScheme = 'medintel-nexus://login-callback';
}
