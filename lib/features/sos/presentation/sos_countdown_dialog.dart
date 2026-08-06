import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sos_controller.dart';

/// Interactive modal overlay showing a 3-second countdown before activating SOS.
/// Features a prominent CANCEL SOS button to abort immediately.
class SosCountdownDialog extends ConsumerStatefulWidget {
  const SosCountdownDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SosCountdownDialog(),
    );
  }

  @override
  ConsumerState<SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends ConsumerState<SosCountdownDialog>
    with SingleTickerProviderStateMixin {
  int _secondsLeft = 3;
  Timer? _timer;
  late AnimationController _animController;

  static const _red = Color(0xFFDC2626);
  static const _ink = Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        _timer?.cancel();
        _animController.stop();
        _onCountdownCompleted();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _onCountdownCompleted() async {
    Navigator.of(context).pop();
    final event = await ref.read(sosControllerProvider.notifier).triggerSos();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          content: Text(
            '🚨 Emergency SOS Activated! Primary contact (${event.primaryContactPhone}) called & SMS sent.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
  }

  void _onCancel() {
    _timer?.cancel();
    _animController.stop();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SOS Activation Cancelled.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3FDC2626),
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 48, color: _red),
            const SizedBox(height: 12),
            const Text(
              'EMERGENCY SOS',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _red,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Activating emergency call & SMS with your GPS location…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 28),

            // Big 3-second animated countdown ring
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: CircularProgressIndicator(
                    value: _secondsLeft / 3,
                    strokeWidth: 10,
                    backgroundColor: const Color(0xFFFEE2E2),
                    color: _red,
                  ),
                ),
                Text(
                  '$_secondsLeft',
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Prominent CANCEL SOS Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _onCancel,
                icon: const Icon(Icons.close_rounded, size: 24),
                label: const Text(
                  'CANCEL SOS',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  foregroundColor: _ink,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
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
