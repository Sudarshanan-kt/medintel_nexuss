import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/constants/supabase_config.dart';
import 'firebase_options.dart';
import 'core/theme/app_colors.dart';

/// Entry point for MedIntel Nexus.
///
/// Runs the app inside a guarded zone so uncaught errors are captured for
/// telemetry. No PHI is ever logged — only error metadata.
Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Load Supabase credentials from `.env` — must happen before reading
      // SupabaseConfig or initialising the client.
      await dotenv.load(fileName: '.env');

      if (!SupabaseConfig.isConfigured) {
        // Fail loudly but *legibly* — this is a setup error, not a runtime
        // auth error, so show it directly instead of surfacing a raw HTTP
        // failure the first time a screen calls Supabase.
        runApp(const _ConfigErrorApp());
        return;
      }

      // Initialise Supabase — must complete before any auth call.
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
        debug: kDebugMode,
      );

      // Push notifications are an enhancement, not a hard dependency — a
      // Firebase misconfiguration must never block the rest of the app.
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        debugPrint('Firebase init failed (push notifications disabled): $e');
      }

      // The on-device AI model the assistant runs on. Like Firebase, this
      // is an enhancement rather than a hard dependency: without it the
      // assistant falls back to the backend, and then to its own curated
      // replies, so a failure here must not stop the app from starting.
      try {
        // The core registers no inference engine by itself — MediaPipe is
        // the one that runs the `.task` model format we ship.
        await FlutterGemma.initialize(
          inferenceEngines: const [MediaPipeEngine()],
        );
      } catch (e) {
        debugPrint('On-device AI init failed (assistant will use backend): $e');
      }

      // DEMO STABILITY: never fetch fonts at runtime. Without bundled font
      // files, google_fonts otherwise hits fonts.gstatic.com on first use of
      // each weight; a failed fetch surfaces as "Unexpected null value" mid
      // build and trips the mouse_tracker assertion. Falling back to the
      // platform font is harmless and keeps the report viewer from crashing.
      GoogleFonts.config.allowRuntimeFetching = false;

      // DEMO STABILITY: intl's DateFormat throws "LocaleData has not been
      // initialized" for any non-en_US locale (e.g. en_IN / ta_IN). That throw
      // happened inside the report card's date formatting and blanked the
      // viewer. Pin the locale to en_US AND load symbol data so date
      // formatting can never throw.
      Intl.defaultLocale = 'en_US';
      initializeDateFormatting('en_US');

      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        // TODO: forward to crash reporting (no PHI).
        debugPrint('FlutterError: ${details.exceptionAsString()}');
      };

      runApp(
        const ProviderScope(
          child: MedIntelNexusApp(),
        ),
      );
    },
    (error, stack) {
      // TODO: forward to crash reporting (no PHI).
      debugPrint('Uncaught zone error: $error');
    },
  );
}

/// Shown instead of the app when `.env` is missing/unfilled, so a broken
/// Supabase setup fails with a clear message instead of raw HTTP errors the
/// first time the user tries to sign up or sign in.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.textPrimary,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.settings_suggest_rounded,
                  color: Colors.white70,
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  'Supabase is not configured',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Copy .env.example to .env and set SUPABASE_URL and '
                  'SUPABASE_ANON_KEY from your Supabase project '
                  '(Project Settings → API), then restart the app.',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
