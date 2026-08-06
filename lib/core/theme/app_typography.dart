import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography system for MedIntel Nexus.
///
/// Uses the platform default font. (Previously loaded Sora / Plus Jakarta Sans
/// via google_fonts at runtime, but on web a failed font fetch threw mid-build
/// — "Unexpected null value" — and blanked the report viewer. Using the system
/// font removes all network dependency and can never throw.)
abstract final class AppTypography {
  static TextStyle _display(double size, FontWeight weight) => TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.5,
        height: 1.25,
      );

  static TextStyle _body(double size, FontWeight weight) => TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: 1.5,
      );

  static final TextStyle displayLg = _display(32, FontWeight.w700);
  static final TextStyle headlineMd = _display(24, FontWeight.w700);
  static final TextStyle titleMd = _display(18, FontWeight.w600);

  static final TextStyle bodyLg = _body(16, FontWeight.w500);
  static final TextStyle bodyMd = _body(14, FontWeight.w500);

  static const TextStyle labelMd = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.2,
  );

  static const TextStyle labelLg = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.2,
  );

  static final TextStyle caption = _body(12, FontWeight.w500);

  /// Builds the Material 3 [TextTheme] for a given base text colour.
  static TextTheme textTheme(Color primary, Color secondary) => TextTheme(
        displayLarge: displayLg.copyWith(color: primary),
        headlineMedium: headlineMd.copyWith(color: primary),
        titleMedium: titleMd.copyWith(color: primary),
        bodyLarge: bodyLg.copyWith(color: primary),
        bodyMedium: bodyMd.copyWith(color: secondary),
        labelMedium: labelMd.copyWith(color: primary),
        bodySmall: caption.copyWith(color: secondary),
      );

  static TextTheme get lightTextTheme =>
      textTheme(AppColors.textPrimary, AppColors.textSecondary);

  static TextTheme get darkTextTheme =>
      textTheme(AppColors.darkTextPrimary, AppColors.darkTextSecondary);
}
