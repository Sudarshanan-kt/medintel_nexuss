import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/medicine.dart';
import 'reminders_controller.dart';

/// Full-screen modal overlay displayed when a medicine alarm rings.
///
/// Features:
///   - Pulsing visual alarm state
///   - Medicine Name, Dosage, Slot & Purpose details
///   - Action Buttons: Mark as Taken, Snooze (10m, 30m, 60m), and Skip
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({
    super.key,
    required this.medicine,
    required this.slot,
  });

  final Medicine medicine;
  final String slot;

  static Future<void> show(
    BuildContext context, {
    required Medicine medicine,
    required String slot,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => AlarmRingScreen(medicine: medicine, slot: slot),
    );
  }

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _primary = Color(0xFF2563EB);
  static const _green = Color(0xFF16A34A);
  static const _red = Color(0xFFDC2626);
  static const _amber = Color(0xFFD97706);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onTaken() {
    ref.read(remindersControllerProvider.notifier).logDose(
          medicineId: widget.medicine.id,
          medicineName: widget.medicine.name,
          dosage: widget.medicine.dosage,
          scheduleSlot: widget.slot,
          status: 'taken',
        );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Great job! Marked ${widget.medicine.name} as Taken.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onSkip() {
    ref.read(remindersControllerProvider.notifier).logDose(
          medicineId: widget.medicine.id,
          medicineName: widget.medicine.name,
          dosage: widget.medicine.dosage,
          scheduleSlot: widget.slot,
          status: 'missed',
        );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Skipped dose for ${widget.medicine.name}.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onSnooze(int minutes) {
    ref.read(remindersControllerProvider.notifier).snoozeDose(
          medicine: widget.medicine,
          slot: widget.slot,
          minutes: minutes,
        );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Snoozed ${widget.medicine.name} for $minutes minutes.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medicine;
    final slotLabel = widget.slot.toUpperCase();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header Indicator
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(99),
            ),
          ),

          // Alarm Pulsing Animation & Icon
          Column(
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _green.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.alarm_on_rounded,
                    size: 56,
                    color: _green,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'MEDICINE REMINDER · $slotLabel',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: _primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                med.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                med.dosage.isEmpty ? '1 dose' : med.dosage,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
              if (med.purpose.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Notes: ${med.purpose}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: _ink),
                ),
              ],
            ],
          ),

          // Action Buttons: Taken, Snooze, Skip
          Column(
            children: [
              // Mark as Taken
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _onTaken,
                  icon: const Icon(Icons.check_circle_rounded, size: 22),
                  label: const Text(
                    'Mark as Taken',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  // Snooze Menu
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: PopupMenuButton<int>(
                        onSelected: _onSnooze,
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 10,
                            child: Text('Snooze 10 minutes'),
                          ),
                          PopupMenuItem(
                            value: 30,
                            child: Text('Snooze 30 minutes'),
                          ),
                          PopupMenuItem(
                            value: 60,
                            child: Text('Snooze 1 hour'),
                          ),
                        ],
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.snooze_rounded, color: _amber, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Snooze…',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _amber,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Skip Button
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _onSkip,
                        icon: const Icon(Icons.close_rounded, color: _red, size: 20),
                        label: const Text(
                          'Skip Dose',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _red,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
