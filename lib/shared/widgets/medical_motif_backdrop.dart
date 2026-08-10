import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Decorative medical imagery drifting slowly behind a screen's content.
///
/// Every motif is drawn at a *very* low opacity — this is atmosphere, never
/// content. The rule of thumb: if you can read a motif without looking for
/// it, the opacity is too high. Nothing here is announced to screen readers
/// and nothing accepts a pointer.
///
/// The drift is what stops the layer reading as a flat wallpaper: each motif
/// bobs on its own period and phase, so the field never visibly repeats.
/// Honours reduce-motion via `MediaQuery.disableAnimations`, in which case
/// the motifs are painted at their rest positions and the ticker never runs.
class MedicalMotifBackdrop extends StatefulWidget {
  const MedicalMotifBackdrop({
    super.key,
    this.tint,
    this.intensity = 1,
    this.count = 12,
    this.seed = 7,
  });

  /// Overrides the default blue-grey. Pass a screen's own accent when it has
  /// one (the caregiver surfaces run violet), so the motifs belong to that
  /// screen rather than looking pasted on from elsewhere.
  final Color? tint;

  /// Scales the (already very low) per-motif opacity. Values above ~1.5 stop
  /// being decorative and start competing with the content.
  final double intensity;

  /// How many motifs to scatter. They are laid out on a jittered grid, so
  /// raising this fills the field more evenly rather than clumping.
  final int count;

  /// Fixes the layout. The same seed always produces the same arrangement,
  /// so a screen's backdrop doesn't reshuffle on every rebuild.
  final int seed;

  @override
  State<MedicalMotifBackdrop> createState() => _MedicalMotifBackdropState();
}

class _MedicalMotifBackdropState extends State<MedicalMotifBackdrop>
    with SingleTickerProviderStateMixin {
  /// One long cycle drives every motif; each reads it at its own speed and
  /// phase. Cheaper than a controller per motif, and they stay in sync
  /// across rebuilds.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 32),
  );

  late List<_Motif> _motifs = _buildMotifs(widget.count, widget.seed);

  @override
  void initState() {
    super.initState();
    _drift.repeat();
  }

  @override
  void didUpdateWidget(covariant MedicalMotifBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count || oldWidget.seed != widget.seed) {
      _motifs = _buildMotifs(widget.count, widget.seed);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final tint =
        widget.tint ?? (isDark ? AppColors.darkMotifTint : AppColors.motifTint);

    // The ticker is pure cost when nothing may move, so stop it outright
    // rather than animating into a value the painter would ignore.
    if (reduceMotion) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }

    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _MotifPainter(
                motifs: _motifs,
                time: reduceMotion ? 0 : _drift.value,
                tint: tint,
                // Dark surfaces swallow a light glyph, so the same visual
                // weight needs a touch more alpha there. Both ceilings are
                // set so a motif is visible once you look for it and
                // invisible while you're reading.
                maxAlpha: (isDark ? 0.20 : 0.15) * widget.intensity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The imagery itself. Outlined and filled shapes are mixed on purpose —
/// a field of all-filled glyphs reads as heavy blobs at this size.
///
/// Kept `const` so Flutter's icon tree-shaker can still prove which glyphs
/// the app uses and drop the rest of the Material icon font.
const List<IconData> _kMedicalIcons = [
  Icons.medical_services_outlined,
  Icons.favorite_rounded,
  Icons.medication_rounded,
  Icons.monitor_heart_outlined,
  Icons.vaccines_rounded,
  Icons.biotech_rounded,
  Icons.science_outlined,
  Icons.healing_rounded,
  Icons.local_hospital_outlined,
  Icons.bloodtype_outlined,
  Icons.water_drop_rounded,
  Icons.medical_information_outlined,
  Icons.health_and_safety_outlined,
  Icons.masks_rounded,
];

/// One motif's fixed identity: where it sits (in fractions of the canvas),
/// how big it is, and how it moves. Resolved once per layout so the field
/// stays put while it drifts.
class _Motif {
  const _Motif({
    required this.icon,
    required this.dx,
    required this.dy,
    required this.size,
    required this.alpha,
    required this.speed,
    required this.phase,
    required this.amplitude,
    required this.tilt,
  });

  final IconData icon;
  final double dx; // 0..1 across the canvas
  final double dy; // 0..1 down the canvas
  final double size; // logical px at a 400px-wide reference canvas
  final double alpha; // 0..1, scaled by the painter's ceiling
  final double speed; // cycles per full controller period
  final double phase; // 0..1 offset into its own cycle
  final double amplitude; // px of vertical travel
  final double tilt; // radians of sway
}

/// Scatters [count] motifs over a jittered grid.
///
/// A plain random scatter clumps badly at these counts — three icons landing
/// in one corner and a bare half-screen elsewhere. Assigning each motif its
/// own grid cell and then jittering inside it keeps the field even while
/// still looking unplanned.
List<_Motif> _buildMotifs(int count, int seed) {
  final rnd = math.Random(seed);
  final cols = count <= 6 ? 2 : 3;
  final rows = (count / cols).ceil();

  return List<_Motif>.generate(count, (i) {
    final col = i % cols;
    final row = i ~/ cols;
    // Cell centre, then jitter within the cell — never past its edge, or
    // neighbouring motifs start to overlap.
    final cellW = 1 / cols;
    final cellH = 1 / rows;
    final jitterX = (rnd.nextDouble() - 0.5) * cellW * 0.7;
    final jitterY = (rnd.nextDouble() - 0.5) * cellH * 0.7;

    return _Motif(
      icon: _kMedicalIcons[(i * 5 + seed) % _kMedicalIcons.length],
      dx: (col + 0.5) * cellW + jitterX,
      dy: (row + 0.5) * cellH + jitterY,
      size: 42 + rnd.nextDouble() * 44,
      alpha: 0.55 + rnd.nextDouble() * 0.45,
      speed: 0.7 + rnd.nextDouble() * 0.8,
      phase: rnd.nextDouble(),
      amplitude: 6 + rnd.nextDouble() * 10,
      tilt: (rnd.nextDouble() - 0.5) * 0.12,
    );
  });
}

class _MotifPainter extends CustomPainter {
  _MotifPainter({
    required this.motifs,
    required this.time,
    required this.tint,
    required this.maxAlpha,
  });

  final List<_Motif> motifs;
  final double time;
  final Color tint;
  final double maxAlpha;

  /// Motif sizes are authored against this canvas width and scaled from it,
  /// so a tablet gets proportionally larger imagery instead of the same
  /// small glyphs adrift in a much bigger space.
  static const double _referenceWidth = 400;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = (size.width / _referenceWidth).clamp(0.85, 1.6);
    final painter = TextPainter(textDirection: TextDirection.ltr);

    for (final m in motifs) {
      final t = (time * m.speed + m.phase) * 2 * math.pi;
      final glyphSize = m.size * scale;

      painter
        ..text = TextSpan(
          text: String.fromCharCode(m.icon.codePoint),
          style: TextStyle(
            fontSize: glyphSize,
            fontFamily: m.icon.fontFamily,
            package: m.icon.fontPackage,
            color: tint.withValues(alpha: maxAlpha * m.alpha),
            height: 1,
          ),
        )
        ..layout();

      final centre = Offset(
        m.dx * size.width + math.cos(t * 0.7) * m.amplitude * 0.5,
        m.dy * size.height + math.sin(t) * m.amplitude,
      );

      canvas
        ..save()
        ..translate(centre.dx, centre.dy)
        ..rotate(math.sin(t * 0.5) * m.tilt);
      painter.paint(
        canvas,
        Offset(-painter.width / 2, -painter.height / 2),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MotifPainter old) =>
      old.time != time ||
      old.tint != tint ||
      old.maxAlpha != maxAlpha ||
      !identical(old.motifs, motifs);
}
