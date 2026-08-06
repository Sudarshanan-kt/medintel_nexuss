import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../application/assistant_controller.dart';
import '../data/assistant_service.dart';
import '../domain/chat_message.dart';
import '../domain/voice_state.dart';

/// Premium, cinematic voice assistant. Dark-glass aesthetic, hero orb with
/// concentric rings, live mic waveform, and a quote-style AI response.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ambient;
  bool? _hasKey;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _checkKey();
  }

  Future<void> _checkKey() async {
    final svc = ref.read(assistantServiceProvider);
    final has = await svc.hasApiKey();
    if (mounted) setState(() => _hasKey = has);
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _openApiKeySheet() async {
    await showAppSheet<void>(
      context: context,
      builder: (_) => _ApiKeySheet(onSaved: _checkKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF050B1A),
      body: Stack(
        children: [
          // ── Ambient atmosphere ─────────────────────────────────────────
          AnimatedBuilder(
            animation: _ambient,
            builder: (_, __) => CustomPaint(
              size: Size.infinite,
              painter: _AmbientPainter(time: _ambient.value),
            ),
          ),

          // ── Foreground ─────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(
                  language: state.language,
                  onLanguageChanged: controller.setLanguage,
                  onSettings: _openApiKeySheet,
                  handsFree: state.handsFree,
                  onToggleHandsFree: () {
                    HapticFeedback.selectionClick();
                    controller.toggleHandsFree();
                  },
                ),
                if (_hasKey == false) _KeyPromptBanner(onTap: _openApiKeySheet),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      _HeroOrb(phase: state.phase, amplitude: state.amplitude),
                      const SizedBox(height: AppSpacing.lg),
                      _StatusLine(state: state),
                      Expanded(
                        child: _DialogueDisplay(state: state),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.lg,
                    AppSpacing.gutter,
                    AppSpacing.xl,
                  ),
                  child: _TalkButton(
                    phase: state.phase,
                    handsFree: state.handsFree,
                    onStart: () async {
                      HapticFeedback.mediumImpact();
                      await controller.startListening();
                    },
                    onStop: () async {
                      HapticFeedback.lightImpact();
                      await controller.stopListening();
                    },
                    onInterrupt: controller.interrupt,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Ambient background — dark navy with slow-drifting aurora blobs + stars.
// ─────────────────────────────────────────────────────────────────────────

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({required this.time});
  final double time;

  static final _rand = math.Random(7);
  static final _stars = List.generate(
    90,
    (_) => Offset(_rand.nextDouble(), _rand.nextDouble()),
  );
  static final _starSizes =
      List.generate(90, (_) => _rand.nextDouble() * 1.8 + 0.4);

  @override
  void paint(Canvas canvas, Size size) {
    // Deep navy base.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF050B1A),
    );

    // Aurora blobs drifting on a long loop.
    void blob(Offset relCenter, double radius, Color color) {
      final c = Offset(relCenter.dx * size.width, relCenter.dy * size.height);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }

    final t = time * 2 * math.pi;
    blob(
      Offset(0.18 + math.sin(t) * 0.06, 0.22 + math.cos(t) * 0.04),
      size.width * 0.55,
      AppColors.primary.withValues(alpha: 0.35),
    );
    blob(
      Offset(0.82 + math.cos(t) * 0.06, 0.18 + math.sin(t * 1.3) * 0.05),
      size.width * 0.45,
      AppColors.accentCyan.withValues(alpha: 0.28),
    );
    blob(
      Offset(0.50 + math.sin(t * 0.7) * 0.05, 0.92),
      size.width * 0.6,
      AppColors.accentViolet.withValues(alpha: 0.30),
    );

    // Sparse star field.
    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (var i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final twinkle = 0.4 +
          0.6 * (0.5 + math.sin(time * 2 * math.pi * 2 + i.toDouble()) * 0.5);
      starPaint.color = Colors.white.withValues(alpha: 0.45 * twinkle);
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        _starSizes[i],
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.time != time;
}

// ─────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.language,
    required this.onLanguageChanged,
    required this.onSettings,
    required this.handsFree,
    required this.onToggleHandsFree,
  });

  final AssistantLanguage language;
  final ValueChanged<AssistantLanguage> onLanguageChanged;
  final VoidCallback onSettings;

  /// Whether hands-free conversation mode is currently active.
  final bool handsFree;
  final VoidCallback onToggleHandsFree;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nexus',
                style: AppTypography.headlineMd.copyWith(
                  color: Colors.white,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                'Clinical Assistant',
                style: AppTypography.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const Spacer(),
          _GlassPill(
            child: PopupMenuButton<AssistantLanguage>(
              onSelected: onLanguageChanged,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              itemBuilder: (_) => AssistantLanguage.values
                  .map((l) => PopupMenuItem(value: l, child: Text(l.label)))
                  .toList(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.translate_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    language.label,
                    style: AppTypography.labelMd
                        .copyWith(color: Colors.white, fontSize: 13),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _GlassIconButton(
            icon: handsFree
                ? Icons.record_voice_over_rounded
                : Icons.touch_app_rounded,
            onTap: onToggleHandsFree,
            active: handsFree,
            tooltip: handsFree
                ? 'Hands-free is on — tap to stop'
                : 'Turn on hands-free conversation',
          ),
          const SizedBox(width: AppSpacing.sm),
          _GlassIconButton(icon: Icons.tune_rounded, onTap: onSettings),
        ],
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;

  /// Highlights the button in the brand accent when a mode it toggles is on.
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.accentCyan.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? AppColors.accentCyan.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Hero orb — big aurora orb with three concentric animated rings.
// ─────────────────────────────────────────────────────────────────────────

class _HeroOrb extends StatefulWidget {
  const _HeroOrb({required this.phase, required this.amplitude});
  final VoicePhase phase;
  final double amplitude;

  @override
  State<_HeroOrb> createState() => _HeroOrbState();
}

class _HeroOrbState extends State<_HeroOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _applySpeed();
  }

  @override
  void didUpdateWidget(covariant _HeroOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) _applySpeed();
  }

  void _applySpeed() {
    _spin.duration = switch (widget.phase) {
      VoicePhase.thinking || VoicePhase.speaking => const Duration(seconds: 3),
      VoicePhase.listening => const Duration(seconds: 4),
      _ => const Duration(seconds: 9),
    };
    _spin
      ..reset()
      ..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const orbSize = 180.0;
    final pulse = widget.phase == VoicePhase.listening
        ? (widget.amplitude * 0.18 + 0.04)
        : 0.0;
    return SizedBox(
      width: orbSize * 2,
      height: orbSize * 1.55,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (_, __) {
          final angle = _spin.value * 2 * math.pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer breathing ring.
              Container(
                width: orbSize * (1.55 + pulse),
                height: orbSize * (1.55 + pulse),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                    width: 1.2,
                  ),
                ),
              ),
              // Mid orbital ring with a single glowing arc.
              SizedBox(
                width: orbSize * 1.30,
                height: orbSize * 1.30,
                child: CustomPaint(
                  painter: _OrbitalRingPainter(
                    angle: angle,
                    color: AppColors.accentCyan,
                  ),
                ),
              ),
              // Outer glow halo.
              Container(
                width: orbSize * (1.10 + pulse * 1.4),
                height: orbSize * (1.10 + pulse * 1.4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accentCyan.withValues(alpha: 0.35),
                      AppColors.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              // The orb itself.
              Transform.rotate(
                angle: angle,
                child: Container(
                  width: orbSize,
                  height: orbSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(
                      colors: [
                        AppColors.accentCyan,
                        AppColors.primary,
                        AppColors.accentViolet,
                        AppColors.accentCyan,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.6),
                        blurRadius: 60,
                        spreadRadius: -6,
                      ),
                    ],
                  ),
                ),
              ),
              // White core.
              Container(
                width: orbSize * 0.42,
                height: orbSize * 0.42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.90),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.6),
                      blurRadius: 30,
                    ),
                  ],
                ),
              ),
              // Amplitude waveform around the orb (only while listening).
              if (widget.phase == VoicePhase.listening)
                Positioned(
                  bottom: 0,
                  child: _Waveform(amplitude: widget.amplitude),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OrbitalRingPainter extends CustomPainter {
  _OrbitalRingPainter({required this.angle, required this.color});
  final double angle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Faint full ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );

    // Glowing arc that rotates.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 0.5,
        colors: [color.withValues(alpha: 0), color],
        transform: GradientRotation(angle),
      ).createShader(rect);
    canvas.drawArc(rect, angle, math.pi * 0.5, false, glow);
  }

  @override
  bool shouldRepaint(_OrbitalRingPainter old) =>
      old.angle != angle || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────
// Live audio waveform
// ─────────────────────────────────────────────────────────────────────────

class _Waveform extends StatefulWidget {
  const _Waveform({required this.amplitude});
  final double amplitude;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 56,
      child: AnimatedBuilder(
        animation: _t,
        builder: (_, __) => CustomPaint(
          painter: _WaveformPainter(
            amp: widget.amplitude,
            phase: _t.value,
            seed: _rand,
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.amp,
    required this.phase,
    required this.seed,
  });

  final double amp;
  final double phase;
  final math.Random seed;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 22;
    final barW = size.width / (bars * 1.8);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;
    for (var i = 0; i < bars; i++) {
      final t = phase * 2 * math.pi + i * 0.55;
      final base = (math.sin(t) + 1) / 2;
      final variance = (math.sin(t * 1.7 + i) + 1) / 2 * 0.4;
      final h = (base * 0.6 + variance) * size.height * (amp.clamp(0.05, 1));
      final x = i * (size.width / bars) + barW;
      final y0 = size.height / 2 - h / 2;
      final y1 = size.height / 2 + h / 2;
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.accentCyan.withValues(alpha: 0.95),
          AppColors.primary.withValues(alpha: 0.95),
        ],
      ).createShader(Rect.fromLTWH(x, y0, barW, h.clamp(2, size.height)));
      canvas.drawLine(Offset(x, y0), Offset(x, y1), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.amp != amp || old.phase != phase;
}

// ─────────────────────────────────────────────────────────────────────────
// Status line + dialogue display
// ─────────────────────────────────────────────────────────────────────────

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});
  final AssistantState state;

  String get _text => switch (state.phase) {
        VoicePhase.idle => 'Tap to talk',
        VoicePhase.listening => 'Listening…',
        VoicePhase.thinking => 'Thinking…',
        VoicePhase.speaking => 'Speaking',
        VoicePhase.error => state.errorMessage ?? 'Something went wrong',
      };

  @override
  Widget build(BuildContext context) {
    final color = state.phase == VoicePhase.error
        ? AppColors.danger
        : Colors.white.withValues(alpha: 0.75);
    return Text(
      _text,
      style: AppTypography.labelMd.copyWith(
        color: color,
        fontSize: 13,
        letterSpacing: 2.5,
      ),
    );
  }
}

class _DialogueDisplay extends StatelessWidget {
  const _DialogueDisplay({required this.state});
  final AssistantState state;

  ChatMessage? get _lastAssistant {
    for (final m in state.messages.reversed) {
      if (!m.isUser) return m;
    }
    return null;
  }

  ChatMessage? get _lastUser {
    for (final m in state.messages.reversed) {
      if (m.isUser) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final liveOrUser = state.liveTranscript.isNotEmpty
        ? state.liveTranscript
        : _lastUser?.content;
    final assistant = _lastAssistant?.content ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (liveOrUser != null && liveOrUser.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  liveOrUser,
                  key: ValueKey(liveOrUser),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMd.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (assistant.isNotEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                assistant,
                key: ValueKey(assistant),
                textAlign: TextAlign.center,
                style: AppTypography.titleMd.copyWith(
                  color: Colors.white,
                  fontSize: 19,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Talk button — big gradient pill at the bottom, hold-to-talk
// ─────────────────────────────────────────────────────────────────────────

class _TalkButton extends StatefulWidget {
  const _TalkButton({
    required this.phase,
    required this.handsFree,
    required this.onStart,
    required this.onStop,
    required this.onInterrupt,
  });

  final VoicePhase phase;

  /// When true, listening is auto-triggered by the controller between
  /// turns — the button becomes a single always-tappable "stop" control
  /// instead of the hold-to-talk gesture.
  final bool handsFree;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onInterrupt;

  @override
  State<_TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<_TalkButton> {
  bool _holding = false;

  bool get _busy =>
      widget.phase == VoicePhase.thinking ||
      widget.phase == VoicePhase.speaking;

  String get _label {
    if (widget.handsFree) {
      if (widget.phase == VoicePhase.thinking) return 'Thinking…';
      if (widget.phase == VoicePhase.speaking) return 'Hands-free — tap to stop';
      if (widget.phase == VoicePhase.listening) return 'Listening — tap to stop';
      return 'Hands-free — tap to stop';
    }
    if (widget.phase == VoicePhase.thinking) return 'Thinking…';
    if (widget.phase == VoicePhase.speaking) return 'Tap to interrupt';
    if (widget.phase == VoicePhase.listening) return 'Release to send';
    return 'Hold to talk';
  }

  IconData get _icon {
    if (widget.handsFree) return Icons.stop_rounded;
    return widget.phase == VoicePhase.speaking
        ? Icons.stop_rounded
        : Icons.mic_rounded;
  }

  @override
  Widget build(BuildContext context) {
    // Hands-free: listening is auto-triggered between turns, so the button
    // is just a single always-tappable "stop the conversation" control —
    // no hold gesture to learn.
    final gesture = widget.handsFree
        ? GestureDetector(onTap: widget.onInterrupt, child: _talkButtonBody())
        : GestureDetector(
            onTapDown: (_) {
              if (_busy) return;
              setState(() => _holding = true);
              widget.onStart();
            },
            onTapUp: (_) {
              if (widget.phase == VoicePhase.speaking) {
                widget.onInterrupt();
                return;
              }
              if (_busy) return;
              setState(() => _holding = false);
              widget.onStop();
            },
            onTapCancel: () {
              if (_busy) return;
              setState(() => _holding = false);
              widget.onStop();
            },
            onTap:
                widget.phase == VoicePhase.speaking ? widget.onInterrupt : null,
            child: _talkButtonBody(),
          );

    return gesture;
  }

  Widget _talkButtonBody() {
    final listening = widget.phase == VoicePhase.listening;
    return AnimatedScale(
      scale: _holding && listening ? 1.04 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppColors.accentCyan,
              AppColors.primary,
              AppColors.accentViolet,
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadows.brandGlow,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, color: Colors.white, size: 24),
              const SizedBox(width: AppSpacing.md),
              Text(
                _label.toUpperCase(),
                style: AppTypography.labelMd.copyWith(
                  color: Colors.white,
                  fontSize: 14,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// API key prompt banner + paste sheet
// ─────────────────────────────────────────────────────────────────────────

class _KeyPromptBanner extends StatelessWidget {
  const _KeyPromptBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Using demo responses',
                          style: AppTypography.labelMd
                              .copyWith(color: Colors.white, fontSize: 13),
                        ),
                        Text(
                          'Add a Groq key to unlock real AI · free, takes 30s',
                          style: AppTypography.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiKeySheet extends ConsumerStatefulWidget {
  const _ApiKeySheet({required this.onSaved});
  final VoidCallback onSaved;

  @override
  ConsumerState<_ApiKeySheet> createState() => _ApiKeySheetState();
}

class _ApiKeySheetState extends ConsumerState<_ApiKeySheet> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await ref.read(assistantServiceProvider).setApiKey(_controller.text.trim());
    if (!mounted) return;
    widget.onSaved();
    Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    await ref.read(assistantServiceProvider).setApiKey(null);
    if (!mounted) return;
    widget.onSaved();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0B1325),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Connect real AI',
                style: AppTypography.titleMd.copyWith(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Paste a Groq API key to get real conversational responses '
                'in English & Tamil. Free at console.groq.com/keys — takes '
                '30 seconds with a Google sign-in.',
                style: AppTypography.bodyMd.copyWith(
                  color: Colors.white.withValues(alpha: 0.65),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                obscureText: true,
                style: AppTypography.bodyLg.copyWith(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'gsk_…',
                  hintStyle: AppTypography.bodyMd.copyWith(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.accentCyan),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _busy ? null : _save,
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.accentCyan,
                          AppColors.primary,
                          AppColors.accentViolet,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            'Save and use real AI',
                            style: AppTypography.labelMd.copyWith(
                              color: Colors.white,
                              fontSize: 15,
                              letterSpacing: 0.4,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: _clear,
                  child: Text(
                    'Clear and use demo responses',
                    style: AppTypography.labelMd.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
