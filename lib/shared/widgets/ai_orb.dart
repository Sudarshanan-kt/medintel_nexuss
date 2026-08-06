import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';

/// Lifecycle state of the assistant orb.
enum OrbState { idle, listening, thinking }

/// The animated AI orb — the visual heart of the assistant. A breathing
/// aurora gradient that intensifies and speeds up while "thinking", and
/// pulses a ring while "listening".
///
/// Pure CSS-free Flutter animation; respects reduce-motion via the
/// `MediaQuery.disableAnimations` flag.
class AiOrb extends StatefulWidget {
  const AiOrb({super.key, this.state = OrbState.idle, this.size = 140});

  final OrbState state;
  final double size;

  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _applySpeed();
  }

  @override
  void didUpdateWidget(covariant AiOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _applySpeed();
  }

  void _applySpeed() {
    _spin.duration = switch (widget.state) {
      OrbState.thinking => const Duration(seconds: 3),
      OrbState.listening => const Duration(seconds: 5),
      OrbState.idle => const Duration(seconds: 8),
    };
    _spin
      ..reset()
      ..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final active = widget.state != OrbState.idle;

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _spin]),
      builder: (context, _) {
        final breath = reduceMotion ? 0.5 : _breath.value;
        final scale = 1 + (breath * (active ? 0.10 : 0.05));
        final turns = reduceMotion ? 0.0 : _spin.value;

        return SizedBox(
          width: widget.size * 1.5,
          height: widget.size * 1.5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow halo.
              Container(
                width: widget.size * (1.25 + breath * 0.15),
                height: widget.size * (1.25 + breath * 0.15),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accentCyan.withValues(alpha: 0.28),
                      AppColors.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              // Listening ring.
              if (widget.state == OrbState.listening)
                Container(
                  width: widget.size * (1.05 + breath * 0.25),
                  height: widget.size * (1.05 + breath * 0.25),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accentCyan.withValues(alpha: 1 - breath),
                      width: 2,
                    ),
                  ),
                ),
              // The orb itself.
              Transform.scale(
                scale: scale,
                child: Transform.rotate(
                  angle: turns * 6.283,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          AppColors.accentCyan,
                          AppColors.primary,
                          AppColors.accentViolet,
                          AppColors.accentCyan,
                        ],
                      ),
                      boxShadow: AppShadows.brandGlow,
                    ),
                    child: Center(
                      child: Container(
                        width: widget.size * 0.42,
                        height: widget.size * 0.42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
