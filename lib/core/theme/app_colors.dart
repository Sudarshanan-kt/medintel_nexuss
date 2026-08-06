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
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF6F8FC);
  static const Color glassFill = Color(0x99FFFFFF); // white @ 60%
  static const Color glassStroke = Color(0xB3FFFFFF); // white @ 70%

  // ── Light text ───────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);

  // ── Semantic (risk states) ───────────────────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // ── Lines ────────────────────────────────────────────────────────────────
  static const Color outline = Color(0xFFE2E8F0);

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
}
