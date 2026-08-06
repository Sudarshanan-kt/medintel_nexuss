import 'package:flutter/material.dart';

/// Soft elevation tokens. The design language never uses harsh shadows —
/// large blur, low opacity, slight downward offset.
abstract final class AppShadows {
  /// Resting elevation for standard cards.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0F1E293B),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// Raised elevation for pressed / focused interactive surfaces.
  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x141E293B),
      blurRadius: 36,
      offset: Offset(0, 14),
    ),
  ];

  /// Dedicated glassmorphism shadow — wide, feathered, barely-there.
  static const List<BoxShadow> glass = [
    BoxShadow(
      color: Color(0x1A2563EB),
      blurRadius: 40,
      spreadRadius: -8,
      offset: Offset(0, 18),
    ),
  ];

  /// Glow used behind the AI orb and gradient CTAs.
  static const List<BoxShadow> brandGlow = [
    BoxShadow(
      color: Color(0x4D2563EB),
      blurRadius: 32,
      spreadRadius: -4,
      offset: Offset(0, 12),
    ),
  ];
}
