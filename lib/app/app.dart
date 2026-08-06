import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/profile/application/profile_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'router/app_router.dart';

/// Root widget. Wires the router, the theme system and localization.
class MedIntelNexusApp extends ConsumerWidget {
  const MedIntelNexusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Drives the app's actual UI language from the user's own in-app
    // preference (Profile → Language) instead of just the device locale —
    // that preference existed before but nothing read it.
    final language = ref.watch(
      profileControllerProvider.select((p) => p.language),
    );

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light,
      darkTheme: AppTheme.light, // dark theme isn't fully tuned yet — force light everywhere
      themeMode: ThemeMode.light,
      locale: Locale(language.code),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // English
        Locale('ta'), // Tamil
        Locale('hi'), // Hindi
      ],
      builder: (context, child) {
        // Clamp text scaling so premium layouts never break, while still
        // honouring the user's accessibility preference up to 130%.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
