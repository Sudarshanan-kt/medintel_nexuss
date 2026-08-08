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
  /// Whether any model can answer. Null until the first probe returns, so
  /// the banner doesn't flash before it's known.
  bool? _modelAvailable;

  /// True when replies are generated on the phone rather than the backend.
  bool _onDevice = false;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final service = ref.read(assistantServiceProvider);
    final available = await service.isModelAvailable();
    final onDevice = await service.isRunningOnDevice();
    if (!mounted) return;
    setState(() {
      _modelAvailable = available;
      _onDevice = onDevice;
    });
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _openModelSheet() async {
    await showAppSheet<void>(
      context: context,
      builder: (_) => _LocalModelSheet(onRetry: _checkModel, onDevice: _onDevice),
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
                  onSettings: _openModelSheet,
                  handsFree: state.handsFree,
                  onToggleHandsFree: () {
                    HapticFeedback.selectionClick();
                    controller.toggleHandsFree();
                  },
                ),
                if (_modelAvailable == false)
                  _OfflineModelBanner(onTap: _openModelSheet),
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
                // Typing has to be available regardless of the microphone.
                // Speech can fail for reasons the patient can't fix in the
                // moment — permission revoked, no recogniser for their
                // language, a noisy pharmacy — and without this the
                // assistant is simply unreachable when it does.
                _TextComposer(
                  enabled: state.phase != VoicePhase.thinking,
                  onSubmit: (text) async {
                    HapticFeedback.selectionClick();
                    await controller.sendText(text);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.md,
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
// Local-model status banner + help sheet
// ─────────────────────────────────────────────────────────────────────────

/// Shown when the backend's local model isn't answering, so the demo
/// responses are explained rather than mistaken for the real assistant.
class _OfflineModelBanner extends StatelessWidget {
  const _OfflineModelBanner({required this.onTap});
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
                          'The local AI model isn\'t running · tap for setup',
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

class _LocalModelSheet extends ConsumerStatefulWidget {
  const _LocalModelSheet({required this.onRetry, this.onDevice = false});
  final VoidCallback onRetry;

  /// True when the phone's own model is answering, rather than the backend.
  final bool onDevice;

  @override
  ConsumerState<_LocalModelSheet> createState() => _LocalModelSheetState();
}

/// Explains how to bring the local model up, and re-probes on demand.
///
/// There is nothing for the patient to configure here — inference runs on
/// the backend machine, so this is a status readout and a setup reminder
/// for whoever is running it, not a settings form.
class _LocalModelSheetState extends ConsumerState<_LocalModelSheet> {
  bool _busy = false;
  bool? _available;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    setState(() => _busy = true);
    final available =
        await ref.read(assistantServiceProvider).isModelAvailable();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _available = available;
    });
    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    final available = _available == true;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B1325),
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
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
            Row(
              children: [
                Icon(
                  available
                      ? (widget.onDevice
                          ? Icons.smartphone_rounded
                          : Icons.check_circle_rounded)
                      : Icons.cloud_off_rounded,
                  color: available ? AppColors.success : AppColors.warning,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    available
                        ? (widget.onDevice
                            ? 'Running on this phone'
                            : 'Running on your computer')
                        : 'No AI model available',
                    style: AppTypography.titleMd
                        .copyWith(color: Colors.white, fontSize: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              available
                  ? (widget.onDevice
                      ? 'Replies are generated on this device. It works with '
                          'no server, no Wi-Fi, and nothing you say leaves '
                          'the phone.'
                      : 'Replies come from the model on the machine running '
                          'the backend. Install the on-device model to make '
                          'the assistant work without it.')
                  : 'The assistant is falling back to demo responses. Either '
                      'install the on-device model, or start the backend:',
              style: AppTypography.bodyMd.copyWith(
                color: Colors.white.withValues(alpha: 0.65),
                height: 1.5,
              ),
            ),
            if (!widget.onDevice) ...[
              const SizedBox(height: AppSpacing.lg),
              const _SetupStep(
                step: 'A',
                command: 'adb push qwen2.5-1.5b-it-q8.task '
                    '/sdcard/Android/data/com.medintelnexus.medintel_nexus/'
                    'files/',
                detail: 'Puts the AI model on the phone — about 1.6 GB, once. '
                    'After this the assistant needs no server at all.',
              ),
            ],
            if (!available) ...[
              const SizedBox(height: AppSpacing.lg),
              const _SetupStep(
                step: '1',
                command: 'ollama serve',
                detail: 'Starts the local model server.',
              ),
              const SizedBox(height: AppSpacing.sm),
              const _SetupStep(
                step: '2',
                command: 'ollama pull qwen2.5:7b-instruct',
                detail: 'One-time download, about 4.7 GB.',
              ),
              const SizedBox(height: AppSpacing.sm),
              const _SetupStep(
                step: '3',
                command: 'adb reverse tcp:8000 tcp:8000',
                detail: 'Only on a USB-connected phone, so it can reach the '
                    'backend.',
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _busy ? null : _probe,
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
                          available ? 'Check again' : 'I\'ve started it',
                          style: AppTypography.labelMd.copyWith(
                            color: Colors.white,
                            fontSize: 15,
                            letterSpacing: 0.4,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One numbered shell command in the setup list.
class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.step,
    required this.command,
    required this.detail,
  });

  final String step;
  final String command;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: AppTypography.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: SelectableText(
                  command,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.accentCyan,
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: AppTypography.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Keyboard entry for the assistant.
///
/// Sits under the transcript and above the talk button, so voice stays the
/// primary interaction and this is the always-available way through when
/// the microphone won't cooperate.
class _TextComposer extends StatefulWidget {
  const _TextComposer({required this.onSubmit, this.enabled = true});

  final Future<void> Function(String text) onSubmit;
  final bool enabled;

  @override
  State<_TextComposer> createState() => _TextComposerState();
}

class _TextComposerState extends State<_TextComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    // Keep focus so a follow-up question doesn't need another tap.
    _focus.requestFocus();
    await widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              style: AppTypography.bodyMd.copyWith(color: Colors.white),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Type a question…',
                hintStyle: AppTypography.bodyMd.copyWith(
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: const BorderSide(color: AppColors.accentCyan),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: widget.enabled ? _submit : null,
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: widget.enabled
                    ? const LinearGradient(
                        colors: [AppColors.accentCyan, AppColors.primary],
                      )
                    : null,
                color: widget.enabled
                    ? null
                    : Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white.withValues(alpha: widget.enabled ? 1 : 0.4),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
