import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/scans_controller.dart';

/// Real-time camera scanner. Initialises the back camera on mount, paints
/// an animated capture frame with corner markers + scan line, and exposes
/// flash / gallery / shutter / switch-camera controls.
///
/// In production the captured frame would be passed through the AI pipeline
/// (OCR → BioBERT → risk). This scaffold sends the user straight to the
/// pre-baked demo result so the UX flow is end-to-end testable.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AnimationController _scan;
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _flash = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _initFuture = _initialiseCamera();
  }

  Future<void> _initialiseCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'CameraAccessDenied' ||
          'CameraAccessDeniedWithoutPrompt' =>
            'Camera permission denied. Enable it in Settings → Apps → MedIntel Nexus.',
          _ => 'Could not open camera: ${e.description ?? e.code}',
        };
      });
    } catch (e) {
      setState(() => _error = 'Could not open camera: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initFuture = _initialiseCamera();
      setState(() {});
    }
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final next = !_flash;
    try {
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _flash = next);
    } on CameraException {
      // Some devices don't support torch; silently ignore.
    }
  }

  Future<void> _capture() async {
    HapticFeedback.mediumImpact();
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      final file = await c.takePicture();
      final scan =
          ref.read(scansControllerProvider.notifier).addCapture(file.path);
      if (mounted) context.go(Routes.scanResultId(scan.id));
    } on CameraException catch (e) {
      debugPrint('Capture failed: ${e.code}');
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    _controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview (or loading / error state).
          if (ready)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.previewSize?.height ?? 1,
                  height: controller.value.previewSize?.width ?? 1,
                  child: CameraPreview(controller),
                ),
              ),
            )
          else if (_error != null)
            _CameraError(message: _error!)
          else
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Colors.white),
                strokeWidth: 2.4,
              ),
            ),

          // Mask + capture frame.
          if (ready)
            AnimatedBuilder(
              animation: _scan,
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: _ScanOverlayPainter(progress: _scan.value),
              ),
            ),

          // Header.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  _CircleButton(
                    icon: Icons.close_rounded,
                    onTap: () => context.go(Routes.home),
                  ),
                  const Spacer(),
                  if (ready)
                    _CircleButton(
                      icon: _flash
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      onTap: _toggleFlash,
                    ),
                ],
              ),
            ),
          ),

          // Footer instructions + shutter.
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                    vertical: AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StatusPill(
                        label: 'Hold steady · Tap to capture',
                        tone: PillTone.info,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _CircleButton(
                            icon: Icons.photo_library_rounded,
                            onTap: () {},
                          ),
                          GestureDetector(
                            onTap: _capture,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.brandGradient,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                              ),
                            ),
                          ),
                          _CircleButton(
                            icon: Icons.cameraswitch_rounded,
                            onTap: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_rounded,
              size: 56,
              color: Colors.white70,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLg.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final frameW = size.width * 0.82;
    final frameH = size.height * 0.52;
    final dx = (size.width - frameW) / 2;
    final dy = (size.height - frameH) / 2 - 10;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(dx, dy, frameW, frameH),
      const Radius.circular(20),
    );

    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rect);
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xFF22D3EE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    const cornerLen = 28.0;
    final corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final c in [
      Offset(rect.left, rect.top),
      Offset(rect.right, rect.top),
      Offset(rect.left, rect.bottom),
      Offset(rect.right, rect.bottom),
    ]) {
      final dirX = c.dx == rect.left ? 1 : -1;
      final dirY = c.dy == rect.top ? 1 : -1;
      canvas.drawLine(c, Offset(c.dx + dirX * cornerLen, c.dy), corner);
      canvas.drawLine(c, Offset(c.dx, c.dy + dirY * cornerLen), corner);
    }

    final lineY = dy + 16 + (frameH - 32) * progress;
    canvas.drawLine(
      Offset(dx + 24, lineY),
      Offset(dx + frameW - 24, lineY),
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF22D3EE).withValues(alpha: 0),
            const Color(0xFF22D3EE),
            const Color(0xFF22D3EE).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(dx, lineY, frameW, 1))
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
