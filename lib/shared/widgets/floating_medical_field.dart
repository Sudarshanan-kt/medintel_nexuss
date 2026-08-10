import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The medical objects scattered behind the sign-in screen.
///
/// These are drawn as vector paths rather than pulled from the Material icon
/// font because the font has no stethoscope, syringe, capsule or DNA helix —
/// the four shapes that carry most of the identity here. Drawing them also
/// keeps every motif in one visual language (soft mint fill, rounded joints)
/// instead of mixing icon families.
enum MedicalGlyph {
  stethoscope,
  heartEcg,
  capsule,
  shieldCross,
  pillBottle,
  syringe,
  dna,
  clipboard,
  hospital,
  firstAidKit,
  mortarPestle,
  flask,
  pills,
  sparkle,
  dot,
}

/// One motif placed on the field.
///
/// Positions are fractions of the canvas so the arrangement survives every
/// screen size, and [size] is a fraction of the canvas *width* so the motifs
/// scale with the phone rather than staying a fixed pixel size on a tablet.
@immutable
class MedicalGlyphSpec {
  const MedicalGlyphSpec(
    this.glyph, {
    required this.x,
    required this.y,
    required this.size,
    this.rotation = 0,
    this.alpha = 1,
    this.drift = 1,
    this.phase = 0,
  });

  final MedicalGlyph glyph;
  final double x; // 0..1 across
  final double y; // 0..1 down
  final double size; // fraction of canvas width
  final double rotation; // radians, at rest
  final double alpha; // 0..1, scaled by the field's opacity
  final double drift; // multiplier on the float distance
  final double phase; // 0..1 offset into the float cycle
}

/// A field of medical motifs floating gently behind a screen's content.
///
/// Purely decorative: no pointer, no semantics. Honours reduce-motion, in
/// which case every motif is painted at its rest position.
class FloatingMedicalField extends StatefulWidget {
  const FloatingMedicalField({
    super.key,
    required this.specs,
    this.color = const Color(0xFF7FCBA4),
    this.opacity = 0.26,
    this.period = const Duration(seconds: 14),
  });

  /// Where the motifs sit. [defaultSignInField] is the arrangement used by
  /// the sign-in screen.
  final List<MedicalGlyphSpec> specs;

  /// Mint by default — the motifs read as tinted glass on a pale background.
  final Color color;

  /// Ceiling on how solid any motif gets, before its own
  /// [MedicalGlyphSpec.alpha]. Kept low: the motifs sit behind a translucent
  /// card on the sign-in screen, and anything stronger shows through it as
  /// clutter behind the form fields.
  final double opacity;

  final Duration period;

  /// The sign-in arrangement: motifs ring the edges of the screen so they
  /// frame the card in the middle rather than sitting behind it.
  ///
  /// Every position is inset far enough from the edges that no motif is
  /// clipped by the screen bounds — they are all meant to be seen whole.
  static const List<MedicalGlyphSpec> defaultSignInField = [
    // ── Top band ─────────────────────────────────────────────────────────
    MedicalGlyphSpec(
      MedicalGlyph.stethoscope,
      x: 0.15,
      y: 0.075,
      size: 0.135,
      rotation: -0.05,
      phase: 0.0,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.heartEcg,
      x: 0.49,
      y: 0.055,
      size: 0.115,
      alpha: 0.95,
      phase: 0.35,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.capsule,
      x: 0.70,
      y: 0.072,
      size: 0.10,
      rotation: -0.7,
      phase: 0.6,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.shieldCross,
      x: 0.915,
      y: 0.115,
      size: 0.115,
      rotation: 0.06,
      phase: 0.15,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.sparkle,
      x: 0.31,
      y: 0.145,
      size: 0.055,
      alpha: 0.8,
      phase: 0.5,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.pillBottle,
      x: 0.735,
      y: 0.165,
      size: 0.105,
      rotation: 0.08,
      phase: 0.8,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.syringe,
      x: 0.125,
      y: 0.215,
      size: 0.14,
      rotation: -0.35,
      phase: 0.25,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.dna,
      x: 0.930,
      y: 0.215,
      size: 0.095,
      rotation: 0.2,
      phase: 0.7,
    ),

    // ── Upper middle, hugging the edges around the card ───────────────────
    MedicalGlyphSpec(
      MedicalGlyph.hospital,
      x: 0.072,
      y: 0.355,
      size: 0.115,
      phase: 0.45,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.clipboard,
      x: 0.928,
      y: 0.305,
      size: 0.105,
      rotation: 0.05,
      phase: 0.05,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.sparkle,
      x: 0.20,
      y: 0.27,
      size: 0.035,
      alpha: 0.7,
      phase: 0.9,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.dot,
      x: 0.62,
      y: 0.26,
      size: 0.016,
      alpha: 0.55,
      drift: 0.6,
      phase: 0.3,
    ),

    // ── Sides, level with the card ───────────────────────────────────────
    MedicalGlyphSpec(
      MedicalGlyph.firstAidKit,
      x: 0.928,
      y: 0.455,
      size: 0.11,
      rotation: -0.04,
      phase: 0.55,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.pills,
      x: 0.070,
      y: 0.495,
      size: 0.10,
      rotation: 0.15,
      phase: 0.2,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.mortarPestle,
      x: 0.075,
      y: 0.625,
      size: 0.11,
      phase: 0.75,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.capsule,
      x: 0.930,
      y: 0.675,
      size: 0.085,
      rotation: 0.5,
      phase: 0.4,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.flask,
      x: 0.072,
      y: 0.735,
      size: 0.10,
      rotation: -0.06,
      phase: 0.1,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.capsule,
      x: 0.935,
      y: 0.79,
      size: 0.075,
      rotation: -0.4,
      phase: 0.85,
    ),

    // ── Behind the card ──────────────────────────────────────────────────
    // Deliberately faint: these read through the translucent card, so they
    // have to stay well under the form text sitting on top of them.
    MedicalGlyphSpec(
      MedicalGlyph.capsule,
      x: 0.34,
      y: 0.545,
      size: 0.085,
      rotation: -0.55,
      alpha: 0.9,
      phase: 0.42,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.sparkle,
      x: 0.63,
      y: 0.445,
      size: 0.038,
      alpha: 0.85,
      phase: 0.18,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.pills,
      x: 0.58,
      y: 0.70,
      size: 0.08,
      rotation: 0.2,
      alpha: 0.85,
      phase: 0.72,
    ),

    // ── Bottom band ──────────────────────────────────────────────────────
    MedicalGlyphSpec(
      MedicalGlyph.heartEcg,
      x: 0.13,
      y: 0.875,
      size: 0.105,
      phase: 0.65,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.capsule,
      x: 0.825,
      y: 0.885,
      size: 0.085,
      rotation: 0.35,
      phase: 0.3,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.sparkle,
      x: 0.40,
      y: 0.815,
      size: 0.032,
      alpha: 0.6,
      phase: 0.95,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.dot,
      x: 0.22,
      y: 0.955,
      size: 0.014,
      alpha: 0.5,
      drift: 0.6,
      phase: 0.15,
    ),
    MedicalGlyphSpec(
      MedicalGlyph.dot,
      x: 0.70,
      y: 0.945,
      size: 0.012,
      alpha: 0.5,
      drift: 0.6,
      phase: 0.6,
    ),
  ];

  @override
  State<FloatingMedicalField> createState() => _FloatingMedicalFieldState();
}

class _FloatingMedicalFieldState extends State<FloatingMedicalField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }

    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _float,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _FieldPainter(
                specs: widget.specs,
                time: reduceMotion ? 0 : _float.value,
                color: widget.color,
                opacity: widget.opacity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldPainter extends CustomPainter {
  _FieldPainter({
    required this.specs,
    required this.time,
    required this.color,
    required this.opacity,
  });

  final List<MedicalGlyphSpec> specs;
  final double time;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    for (final spec in specs) {
      final t = (time + spec.phase) * 2 * math.pi;
      final side = size.width * spec.size;
      // Float distance scales with the motif, so big objects drift further
      // than specks and the field doesn't look like it's vibrating.
      final travel = side * 0.16 * spec.drift;

      final centre = Offset(
        spec.x * size.width + math.cos(t * 0.6) * travel * 0.45,
        spec.y * size.height + math.sin(t) * travel,
      );

      final a = (opacity * spec.alpha).clamp(0.0, 1.0);
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: a * 0.55);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        // Unit-space width: the canvas is scaled by `side` below, which is
        // what turns this into side * 0.075 device pixels.
        ..strokeWidth = 0.075
        ..color = color.withValues(alpha: a);

      canvas
        ..save()
        ..translate(centre.dx, centre.dy)
        ..rotate(spec.rotation + math.sin(t * 0.5) * 0.06)
        ..scale(side)
        // Every glyph is authored in a 0..1 box centred on the origin.
        ..translate(-0.5, -0.5);
      _drawGlyph(canvas, spec.glyph, fill, stroke);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.time != time ||
      old.color != color ||
      old.opacity != opacity ||
      !identical(old.specs, specs);
}

// ─────────────────────────────────────────────────────────────────────────────
// Glyph geometry. Each routine draws inside the unit square (0,0)–(1,1); the
// painter handles placement, rotation and scale.
//
// Stroke widths arrive pre-scaled in `stroke`, so nothing here divides by the
// glyph size.
// ─────────────────────────────────────────────────────────────────────────────

void _drawGlyph(Canvas c, MedicalGlyph g, Paint fill, Paint stroke) {
  switch (g) {
    case MedicalGlyph.stethoscope:
      _stethoscope(c, fill, stroke);
    case MedicalGlyph.heartEcg:
      _heartEcg(c, fill, stroke);
    case MedicalGlyph.capsule:
      _capsule(c, fill, stroke);
    case MedicalGlyph.shieldCross:
      _shieldCross(c, fill, stroke);
    case MedicalGlyph.pillBottle:
      _pillBottle(c, fill, stroke);
    case MedicalGlyph.syringe:
      _syringe(c, fill, stroke);
    case MedicalGlyph.dna:
      _dna(c, fill, stroke);
    case MedicalGlyph.clipboard:
      _clipboard(c, fill, stroke);
    case MedicalGlyph.hospital:
      _hospital(c, fill, stroke);
    case MedicalGlyph.firstAidKit:
      _firstAidKit(c, fill, stroke);
    case MedicalGlyph.mortarPestle:
      _mortarPestle(c, fill, stroke);
    case MedicalGlyph.flask:
      _flask(c, fill, stroke);
    case MedicalGlyph.pills:
      _pills(c, fill, stroke);
    case MedicalGlyph.sparkle:
      _sparkle(c, fill);
    case MedicalGlyph.dot:
      // Solid, not the translucent fill — a speck this small vanishes
      // otherwise.
      c.drawCircle(
        const Offset(0.5, 0.5),
        0.5,
        Paint()..color = stroke.color,
      );
  }
}

/// Rounded cross bar helper — the medical cross recurs in four glyphs.
void _cross(Canvas c, Paint p, Offset centre, double arm, double thick) {
  final r = Radius.circular(thick * 0.4);
  c
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: thick, height: arm),
        r,
      ),
      p,
    )
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: arm, height: thick),
        r,
      ),
      p,
    );
}

void _stethoscope(Canvas c, Paint fill, Paint stroke) {
  // The tubing: a wide U from both earpieces down to the junction, then a
  // sweep out to the chest piece.
  final tube = Path()
    ..moveTo(0.18, 0.12)
    ..cubicTo(0.10, 0.42, 0.20, 0.62, 0.38, 0.62)
    ..cubicTo(0.56, 0.62, 0.64, 0.42, 0.56, 0.12);
  c.drawPath(tube, stroke);

  final drop = Path()
    ..moveTo(0.38, 0.62)
    ..cubicTo(0.38, 0.78, 0.52, 0.82, 0.64, 0.80);
  c.drawPath(drop, stroke);

  // Earpieces.
  c
    ..drawCircle(const Offset(0.18, 0.10), 0.075, fill)
    ..drawCircle(const Offset(0.56, 0.10), 0.075, fill)
    // Chest piece.
    ..drawCircle(const Offset(0.76, 0.79), 0.165, fill)
    ..drawCircle(const Offset(0.76, 0.79), 0.165, stroke)
    ..drawCircle(const Offset(0.76, 0.79), 0.075, stroke);
}

void _heartEcg(Canvas c, Paint fill, Paint stroke) {
  final heart = Path()
    ..moveTo(0.5, 0.88)
    ..cubicTo(0.06, 0.60, 0.06, 0.20, 0.30, 0.14)
    ..cubicTo(0.42, 0.11, 0.50, 0.22, 0.50, 0.28)
    ..cubicTo(0.50, 0.22, 0.58, 0.11, 0.70, 0.14)
    ..cubicTo(0.94, 0.20, 0.94, 0.60, 0.5, 0.88)
    ..close();
  c.drawPath(heart, fill);

  // The trace is knocked out of the heart, so it reads as a cut rather than
  // a line drawn on top.
  final ecg = Path()
    ..moveTo(0.16, 0.47)
    ..lineTo(0.34, 0.47)
    ..lineTo(0.41, 0.33)
    ..lineTo(0.50, 0.62)
    ..lineTo(0.58, 0.44)
    ..lineTo(0.64, 0.47)
    ..lineTo(0.84, 0.47);
  c.drawPath(ecg, stroke);
}

void _capsule(Canvas c, Paint fill, Paint stroke) {
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.06, 0.30, 0.94, 0.70),
    const Radius.circular(0.20),
  );
  c
    ..drawRRect(body, fill)
    ..drawRRect(body, stroke)
    // The seam between the two halves.
    ..drawLine(const Offset(0.50, 0.30), const Offset(0.50, 0.70), stroke);
}

void _shieldCross(Canvas c, Paint fill, Paint stroke) {
  final shield = Path()
    ..moveTo(0.5, 0.04)
    ..lineTo(0.90, 0.20)
    ..lineTo(0.90, 0.52)
    ..cubicTo(0.90, 0.76, 0.72, 0.90, 0.50, 0.96)
    ..cubicTo(0.28, 0.90, 0.10, 0.76, 0.10, 0.52)
    ..lineTo(0.10, 0.20)
    ..close();
  c
    ..drawPath(shield, fill)
    ..drawPath(shield, stroke);
  _cross(c, stroke, const Offset(0.5, 0.48), 0.36, 0.11);
}

void _pillBottle(Canvas c, Paint fill, Paint stroke) {
  final cap = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.28, 0.05, 0.72, 0.22),
    const Radius.circular(0.05),
  );
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.20, 0.22, 0.80, 0.95),
    const Radius.circular(0.10),
  );
  c
    ..drawRRect(cap, fill)
    ..drawRRect(cap, stroke)
    ..drawRRect(body, fill)
    ..drawRRect(body, stroke);
  _cross(c, stroke, const Offset(0.5, 0.58), 0.30, 0.10);
}

void _syringe(Canvas c, Paint fill, Paint stroke) {
  // Drawn along the horizontal, then rotated into place by the spec — much
  // easier to reason about than authoring it on the diagonal.
  c
    ..save()
    ..translate(0.5, 0.5)
    ..rotate(-math.pi / 4)
    ..translate(-0.5, -0.5)
    // Needle.
    ..drawLine(const Offset(0.02, 0.5), const Offset(0.24, 0.5), stroke);

  final barrel = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.30, 0.34, 0.78, 0.66),
    const Radius.circular(0.04),
  );
  c
    ..drawRRect(barrel, fill)
    ..drawRRect(barrel, stroke)
    // Hub between needle and barrel.
    ..drawLine(const Offset(0.24, 0.5), const Offset(0.30, 0.5), stroke)
    // Graduations.
    ..drawLine(const Offset(0.44, 0.40), const Offset(0.44, 0.50), stroke)
    ..drawLine(const Offset(0.56, 0.40), const Offset(0.56, 0.50), stroke)
    // Plunger flange and rod.
    ..drawLine(const Offset(0.86, 0.26), const Offset(0.86, 0.74), stroke)
    ..drawLine(const Offset(0.78, 0.5), const Offset(0.98, 0.5), stroke)
    ..restore();
}

void _dna(Canvas c, Paint fill, Paint stroke) {
  Path strand(double phase) {
    final p = Path();
    for (var i = 0; i <= 24; i++) {
      final t = i / 24;
      final x = 0.5 + 0.34 * math.sin(2 * math.pi * t + phase);
      final y = 0.06 + t * 0.88;
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p;
  }

  c
    ..drawPath(strand(0), stroke)
    ..drawPath(strand(math.pi), stroke);

  // Rungs, skipping the points where the strands cross.
  for (final t in const [0.13, 0.30, 0.70, 0.87]) {
    final x1 = 0.5 + 0.34 * math.sin(2 * math.pi * t);
    final x2 = 0.5 + 0.34 * math.sin(2 * math.pi * t + math.pi);
    final y = 0.06 + t * 0.88;
    c.drawLine(Offset(x1, y), Offset(x2, y), stroke);
  }
}

void _clipboard(Canvas c, Paint fill, Paint stroke) {
  final board = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.10, 0.10, 0.90, 0.96),
    const Radius.circular(0.10),
  );
  final clip = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.33, 0.02, 0.67, 0.18),
    const Radius.circular(0.05),
  );
  c
    ..drawRRect(board, fill)
    ..drawRRect(board, stroke)
    ..drawRRect(clip, fill)
    ..drawRRect(clip, stroke);

  // Ruled lines, the top one short like a heading.
  for (final (y, right) in const [(0.42, 0.62), (0.58, 0.76), (0.74, 0.68)]) {
    c.drawLine(Offset(0.24, y), Offset(right, y), stroke);
  }
}

void _hospital(Canvas c, Paint fill, Paint stroke) {
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.12, 0.26, 0.88, 0.96),
    const Radius.circular(0.07),
  );
  c
    ..drawRRect(body, fill)
    ..drawRRect(body, stroke);

  // Sign above the entrance.
  final sign = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.36, 0.06, 0.64, 0.26),
    const Radius.circular(0.05),
  );
  c
    ..drawRRect(sign, fill)
    ..drawRRect(sign, stroke);
  _cross(c, stroke, const Offset(0.5, 0.16), 0.14, 0.055);

  // Windows.
  for (final x in const [0.26, 0.50, 0.74]) {
    for (final y in const [0.44, 0.64]) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 0.13, height: 0.11),
          const Radius.circular(0.03),
        ),
        stroke,
      );
    }
  }
  // Door.
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(0.42, 0.80, 0.58, 0.96),
      const Radius.circular(0.04),
    ),
    stroke,
  );
}

void _firstAidKit(Canvas c, Paint fill, Paint stroke) {
  // Handle.
  final handle = Path()
    ..moveTo(0.38, 0.22)
    ..lineTo(0.38, 0.14)
    ..lineTo(0.62, 0.14)
    ..lineTo(0.62, 0.22);
  c.drawPath(handle, stroke);

  final body = RRect.fromRectAndRadius(
    const Rect.fromLTRB(0.06, 0.22, 0.94, 0.86),
    const Radius.circular(0.11),
  );
  c
    ..drawRRect(body, fill)
    ..drawRRect(body, stroke);
  _cross(c, stroke, const Offset(0.5, 0.54), 0.32, 0.10);
}

void _mortarPestle(Canvas c, Paint fill, Paint stroke) {
  // Pestle, leaning in from the top left.
  c.drawLine(const Offset(0.26, 0.14), const Offset(0.48, 0.48), stroke);

  // Bowl.
  final bowl = Path()
    ..moveTo(0.14, 0.50)
    ..lineTo(0.86, 0.50)
    ..cubicTo(0.84, 0.86, 0.66, 0.94, 0.50, 0.94)
    ..cubicTo(0.34, 0.94, 0.16, 0.86, 0.14, 0.50)
    ..close();
  c
    ..drawPath(bowl, fill)
    ..drawPath(bowl, stroke)
    // Rim.
    ..drawLine(const Offset(0.08, 0.50), const Offset(0.92, 0.50), stroke);
}

void _flask(Canvas c, Paint fill, Paint stroke) {
  final body = Path()
    ..moveTo(0.38, 0.08)
    ..lineTo(0.38, 0.38)
    ..lineTo(0.14, 0.82)
    ..cubicTo(0.10, 0.92, 0.18, 0.95, 0.28, 0.95)
    ..lineTo(0.72, 0.95)
    ..cubicTo(0.82, 0.95, 0.90, 0.92, 0.86, 0.82)
    ..lineTo(0.62, 0.38)
    ..lineTo(0.62, 0.08);
  c.drawPath(body, stroke);

  // Liquid pooled in the base.
  final liquid = Path()
    ..moveTo(0.235, 0.68)
    ..lineTo(0.765, 0.68)
    ..lineTo(0.86, 0.82)
    ..cubicTo(0.90, 0.92, 0.82, 0.95, 0.72, 0.95)
    ..lineTo(0.28, 0.95)
    ..cubicTo(0.18, 0.95, 0.10, 0.92, 0.14, 0.82)
    ..close();
  c
    ..drawPath(liquid, fill)
    // Lip.
    ..drawLine(const Offset(0.32, 0.08), const Offset(0.68, 0.08), stroke);
}

void _pills(Canvas c, Paint fill, Paint stroke) {
  c
    ..drawCircle(const Offset(0.36, 0.40), 0.30, fill)
    ..drawCircle(const Offset(0.36, 0.40), 0.30, stroke)
    // Score line across the back tablet.
    ..drawLine(const Offset(0.20, 0.40), const Offset(0.52, 0.40), stroke)
    ..drawCircle(const Offset(0.64, 0.66), 0.28, fill)
    ..drawCircle(const Offset(0.64, 0.66), 0.28, stroke);
}

/// The four-point star used in the wordmark (`✦ NEXUS ✦`) and as a speck in
/// the floating field. Drawn rather than typed, because the glyph isn't in
/// the app's font stack.
class SparkleMark extends StatelessWidget {
  const SparkleMark({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _SparklePainter(color)),
      );
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width);
    _sparkle(canvas, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}

void _sparkle(Canvas c, Paint fill) {
  final p = Path()
    ..moveTo(0.5, 0.0)
    ..quadraticBezierTo(0.57, 0.43, 1.0, 0.5)
    ..quadraticBezierTo(0.57, 0.57, 0.5, 1.0)
    ..quadraticBezierTo(0.43, 0.57, 0.0, 0.5)
    ..quadraticBezierTo(0.43, 0.43, 0.5, 0.0)
    ..close();
  c.drawPath(p, fill);
}
