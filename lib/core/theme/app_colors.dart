import 'package:flutter/material.dart';

/// Centralised colour tokens for MedIntel Nexus.
///
/// No widget should ever hard-code a hex value — everything resolves through
/// these tokens, which feed [AppTheme]. Changing the brand is a one-file edit.
abstract final class AppColors {
  // ── Brand ────────────────────────────────────────────────────────────────
  // Mint/emerald identity, matching the sign-in screen and the redesigned
  // home dashboard. Changing the brand really is a one-file edit: every
  // shared surface (bottom nav, FABs, primary buttons, links) reads from
  // these tokens.
  static const Color primary = Color(0xFF12A97D);
  static const Color primaryDeep = Color(0xFF0B8F63);
  static const Color primarySoft = Color(0xFFDFF6EB);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color accentViolet = Color(0xFF7C3AED);

  // ── Light surfaces ───────────────────────────────────────────────────────
  /// The page behind every card. Deliberately a cool grey-white rather than
  /// pure white: white cards need something to sit *on*, and against #FFFFFF
  /// they have no edge without a heavy border or shadow.
  static const Color canvas = Color(0xFFF3F6F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF6F8FC);
  static const Color glassFill = Color(0x99FFFFFF); // white @ 60%
  static const Color glassStroke = Color(0xB3FFFFFF); // white @ 70%

  /// The near-black used for a single hero card per screen (health score).
  /// One dark block against the light canvas is what gives the layout a
  /// focal point; use it sparingly or the effect is lost.
  static const Color heroDark = Color(0xFF0C1A18);
  static const Color heroDarkMuted = Color(0xFF16302B);

  /// Neutral steps between [surface] and [outline], for the greys screens
  /// currently reach for by hand (dividers, disabled fills, skeletons).
  static const Color neutral50 = Color(0xFFF8FAFC);
  static const Color neutral100 = Color(0xFFF1F5F9);
  static const Color neutral300 = Color(0xFFCBD5E1);

  // ── Light text ───────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  /// Muted blue-grey for captions sitting on tinted or coloured fills, where
  /// [textTertiary] washes out.
  static const Color textMuted = Color(0xFF8DA4B4);

  // ── Semantic (risk states) ───────────────────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF2563EB);

  /// Deeper variants, for text or icons that must stay legible on top of the
  /// matching tint. The base colours above are tuned for fills, and fail
  /// contrast when used as small text on their own tint.
  static const Color successDeep = Color(0xFF15803D);
  static const Color warningDeep = Color(0xFFD97706);
  static const Color dangerDeep = Color(0xFFDC2626);

  // ── Lines ────────────────────────────────────────────────────────────────
  static const Color outline = Color(0xFFE2E8F0);
  static const Color outlineSoft = Color(0xFFF1F5F9);

  // ── Dark surfaces ────────────────────────────────────────────────────────
  static const Color darkSurface = Color(0xFF0B1220);
  static const Color darkSurfaceMuted = Color(0xFF060A14);
  static const Color darkGlassFill = Color(0x1FFFFFFF);
  static const Color darkGlassStroke = Color(0x33FFFFFF);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkOutline = Color(0xFF1E293B);

  // ── Signature gradients ──────────────────────────────────────────────────
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDeep],
  );

  static const LinearGradient auroraGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentCyan, primary, accentViolet],
  );

  /// Soft tints used for quick-action medallions and insight rails.
  /// `tintBlue` is the one paired with [primary]/[primaryDeep] everywhere
  /// (status pills, insight cards, selected nav state) — kept as a mint tone
  /// so it never clashes with the teal brand color it's shown next to.
  static const Color tintBlue = Color(0xFFE3F5EF);
  static const Color tintCyan = Color(0xFFE0FBFF);
  static const Color tintGreen = Color(0xFFE7F8F1);
  static const Color tintAmber = Color(0xFFFEF3E2);
  static const Color tintRed = Color(0xFFFDECEC);
  static const Color tintViolet = Color(0xFFF1ECFE);

  /// Sky tint, completing the quick-action set (mint / violet / amber /
  /// sky). Each medallion needs a distinct hue so the row reads as four
  /// destinations rather than one repeated shape.
  static const Color tintSky = Color(0xFFE8F1FE);

  /// Backdrop for the illustrated header — a barely-there wash that lets
  /// decorative medical imagery sit behind content without competing with
  /// it. Kept as a token so the "very low opacity" intent can't drift.
  static const Color headerWash = Color(0xFFEAF3F1);
}
