import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app/router/route_names.dart';
import 'adherence_controller.dart';
import 'adherence_streak_card.dart';
import 'alarm_ring_screen.dart';
import 'data/alarm_service.dart';
import 'data/medicine_label_scanner.dart';
import 'domain/medicine.dart';
import 'reminders_controller.dart';

/// Complete Medicine Manager Screen
///
/// Features:
///   - Real local exact alarm scheduling with sound & vibration
///   - Today's Schedule with Morning/Afternoon/Night slots & Taken/Snooze/Skip actions
///   - Active vs Completed Medicines list & management
///   - Dose Log History
///   - Full manual medicine addition form with custom alarm sounds, slot time pickers, schedule, dates & notes
class MedicineReminderScreen extends ConsumerStatefulWidget {
  const MedicineReminderScreen({super.key});

  @override
  ConsumerState<MedicineReminderScreen> createState() =>
      _MedicineReminderScreenState();
}

class _MedicineReminderScreenState
    extends ConsumerState<MedicineReminderScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _primary = Color(0xFF2563EB);
  static const _green = Color(0xFF15803D);
  static const _red = Color(0xFFDC2626);
  static const _amber = Color(0xFFD97706);

  int _medSegment = 0; // 0 = Active, 1 = Completed

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remindersControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        title: const Text(
          'Medicine Manager',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Test Alarm Ring',
            icon: const Icon(Icons.alarm_on_rounded, color: _primary),
            onPressed: () {
              if (state.activeMedicines.isNotEmpty) {
                AlarmRingScreen.show(
                  context,
                  medicine: state.activeMedicines.first,
                  slot: 'morning',
                );
              } else {
                ref.read(remindersControllerProvider.notifier).sendTest();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: _primary,
          unselectedLabelColor: _muted,
          indicatorColor: _primary,
          tabs: const [
            Tab(text: "Today's Schedule"),
            Tab(text: 'All Medicines'),
            Tab(text: 'History'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Medicine'),
        onPressed: () => _openAddMedicineSheet(context),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTodayScheduleTab(state),
          _buildAllMedicinesTab(state),
          _buildHistoryTab(state),
        ],
      ),
    );
  }

  // ── Tab 1: Today's Schedule ────────────────────────────────────────────────

  Widget _buildTodayScheduleTab(MedicineManagerState state) {
    final activeMeds = state.activeMedicines;
    final todayStr = DateFormat('EEEE, MMM d, yyyy').format(DateTime.now());

    if (activeMeds.isEmpty) {
      return _buildEmptyState(
        icon: Icons.medication_outlined,
        title: 'No active medicines',
        subtitle: 'Add a medicine to start tracking your daily doses and exact alarms.',
        buttonLabel: 'Add Medicine',
        onTap: () => _openAddMedicineSheet(context),
      );
    }

    final morningMeds = activeMeds.where((m) => m.morning).toList();
    final afternoonMeds = activeMeds.where((m) => m.afternoon).toList();
    final nightMeds = activeMeds.where((m) => m.night).toList();
    final asNeededMeds =
        activeMeds.where((m) => !m.morning && !m.afternoon && !m.night).toList();
    final adherence = ref.watch(adherenceStateProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_rounded, color: _primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  todayStr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        AdherenceStreakCard(state: adherence),
        const SizedBox(height: 16),

        if (morningMeds.isNotEmpty) ...[
          _buildSlotHeader('🌅 Morning Doses', 'Exact alarm set for Morning'),
          for (final med in morningMeds) _buildDoseCard(med, 'morning', state),
          const SizedBox(height: 16),
        ],

        if (afternoonMeds.isNotEmpty) ...[
          _buildSlotHeader('☀️ Afternoon Doses', 'Exact alarm set for Afternoon'),
          for (final med in afternoonMeds) _buildDoseCard(med, 'afternoon', state),
          const SizedBox(height: 16),
        ],

        if (nightMeds.isNotEmpty) ...[
          _buildSlotHeader('🌙 Night Doses', 'Exact alarm set for Night'),
          for (final med in nightMeds) _buildDoseCard(med, 'night', state),
          const SizedBox(height: 16),
        ],

        if (asNeededMeds.isNotEmpty) ...[
          _buildSlotHeader('💊 As Needed / General', 'Take as required'),
          for (final med in asNeededMeds) _buildDoseCard(med, 'as_needed', state),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildSlotHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildDoseCard(
    Medicine med,
    String slot,
    MedicineManagerState state,
  ) {
    final now = DateTime.now();
    DoseLog? todayLog;
    for (final log in state.logs) {
      if (log.medicineId == med.id &&
          log.scheduleSlot == slot &&
          log.timestamp.year == now.year &&
          log.timestamp.month == now.month &&
          log.timestamp.day == now.day) {
        todayLog = log;
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medication_rounded, color: _green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Dosage: ${med.dosage.isEmpty ? "1 dose" : med.dosage}'
                      '${med.purpose.isNotEmpty ? " · ${med.purpose}" : ""}',
                      style: const TextStyle(fontSize: 13, color: _muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.alarm_on_rounded, color: _primary),
                tooltip: 'Preview Alarm Ring',
                onPressed: () => AlarmRingScreen.show(
                  context,
                  medicine: med,
                  slot: slot,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (todayLog != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: todayLog.isTaken
                    ? const Color(0xFFDCFCE7)
                    : (todayLog.status == 'snoozed'
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFFEE2E2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    todayLog.isTaken
                        ? Icons.check_circle_rounded
                        : (todayLog.status == 'snoozed'
                            ? Icons.snooze_rounded
                            : Icons.cancel_rounded),
                    size: 18,
                    color: todayLog.isTaken
                        ? _green
                        : (todayLog.status == 'snoozed' ? _amber : _red),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    todayLog.isTaken
                        ? 'Taken at ${DateFormat.jm().format(todayLog.timestamp)}'
                        : (todayLog.status == 'snoozed'
                            ? 'Snoozed at ${DateFormat.jm().format(todayLog.timestamp)}'
                            : 'Marked as Missed'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: todayLog.isTaken
                          ? _green
                          : (todayLog.status == 'snoozed' ? _amber : _red),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref
                          .read(remindersControllerProvider.notifier)
                          .logDose(
                            medicineId: med.id,
                            medicineName: med.name,
                            dosage: med.dosage,
                            scheduleSlot: slot,
                            status: 'taken',
                          );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Marked ${med.name} as Taken'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_rounded, color: _green),
                    label: const Text(
                      'Taken',
                      style: TextStyle(color: _green, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF86EFAC)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<int>(
                  onSelected: (mins) {
                    ref.read(remindersControllerProvider.notifier).snoozeDose(
                          medicine: med,
                          slot: slot,
                          minutes: mins,
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Snoozed ${med.name} for $mins mins'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 10, child: Text('Snooze 10m')),
                    PopupMenuItem(value: 30, child: Text('Snooze 30m')),
                    PopupMenuItem(value: 60, child: Text('Snooze 1h')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.snooze_rounded, color: _amber, size: 18),
                        SizedBox(width: 4),
                        Text(
                          'Snooze',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref
                          .read(remindersControllerProvider.notifier)
                          .logDose(
                            medicineId: med.id,
                            medicineName: med.name,
                            dosage: med.dosage,
                            scheduleSlot: slot,
                            status: 'missed',
                          );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Marked ${med.name} as Missed'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.close_rounded, color: _red),
                    label: const Text(
                      'Skip',
                      style: TextStyle(color: _red, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Tab 2: All Medicines (Active vs Completed) ────────────────────────────

  Widget _buildAllMedicinesTab(MedicineManagerState state) {
    final active = state.activeMedicines;
    final completed = state.completedMedicines;
    final currentList = _medSegment == 0 ? active : completed;

    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _medSegment = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _medSegment == 0 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Active (${active.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _medSegment == 0 ? _primary : _muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _medSegment = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _medSegment == 1 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Completed (${completed.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _medSegment == 1 ? _primary : _muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          child: currentList.isEmpty
              ? _buildEmptyState(
                  icon: Icons.medication_liquid_outlined,
                  title: _medSegment == 0
                      ? 'No active medicines'
                      : 'No completed medicines',
                  subtitle: _medSegment == 0
                      ? 'Tap below to add a new medicine with exact local alarms.'
                      : 'Medicines you mark as completed will automatically stop alarms and appear here.',
                  buttonLabel: _medSegment == 0 ? 'Add Medicine' : null,
                  onTap: _medSegment == 0
                      ? () => _openAddMedicineSheet(context)
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  itemCount: currentList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final med = currentList[i];
                    return _buildMedicineDetailCard(med);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMedicineDetailCard(Medicine med) {
    final morningTimeStr = TimeOfDay(hour: med.morningHour, minute: med.morningMinute).format(context);
    final afternoonTimeStr = TimeOfDay(hour: med.afternoonHour, minute: med.afternoonMinute).format(context);
    final nightTimeStr = TimeOfDay(hour: med.nightHour, minute: med.nightMinute).format(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  med.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: _muted),
                onSelected: (val) {
                  if (val == 'toggle') {
                    ref
                        .read(remindersControllerProvider.notifier)
                        .toggleCompleted(med.id);
                  } else if (val == 'delete') {
                    _confirmDeleteMed(med);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      med.isCompleted
                          ? 'Reactivate Medicine'
                          : 'Mark as Completed',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: _red),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),

          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (med.dosage.isNotEmpty) _badge(med.dosage, const Color(0xFFEFF6FF), _primary),
              _badge(med.frequency, const Color(0xFFF1F5F9), _ink),
              _badge('Sound: ${med.sound}', const Color(0xFFF3E8FF), const Color(0xFF7E22CE)),
              if (med.morning) _badge('Morning ($morningTimeStr)', const Color(0xFFFEF3C7), const Color(0xFFD97706)),
              if (med.afternoon) _badge('Afternoon ($afternoonTimeStr)', const Color(0xFFFFEDD5), const Color(0xFFC2410C)),
              if (med.night) _badge('Night ($nightTimeStr)', const Color(0xFFF3E8FF), const Color(0xFF7E22CE)),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            'Start: ${DateFormat.yMMMd().format(med.startDate)}'
            '${med.endDate != null ? " · End: ${DateFormat.yMMMd().format(med.endDate!)}" : " · Ongoing"}',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),

          if (med.purpose.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Notes: ${med.purpose}',
              style: const TextStyle(fontSize: 13, color: _ink),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: text),
      ),
    );
  }

  // ── Tab 3: History ─────────────────────────────────────────────────────────

  Widget _buildHistoryTab(MedicineManagerState state) {
    final logs = state.logs;

    if (logs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_rounded,
        title: 'No dose history yet',
        subtitle:
            'When you mark doses as Taken, Missed, or Snoozed, your history will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final log = logs[i];
        final dateStr = DateFormat.yMMMd().add_jm().format(log.timestamp);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(
                log.isTaken
                    ? Icons.check_circle_rounded
                    : (log.status == 'snoozed'
                        ? Icons.snooze_rounded
                        : Icons.cancel_rounded),
                color: log.isTaken
                    ? _green
                    : (log.status == 'snoozed' ? _amber : _red),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.medicineName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    Text(
                      '${log.dosage.isEmpty ? "1 dose" : log.dosage} · ${log.scheduleSlot} · $dateStr',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: _muted, size: 20),
                onPressed: () {
                  ref
                      .read(remindersControllerProvider.notifier)
                      .deleteDoseLog(log.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Shared Empty State ─────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? buttonLabel,
    VoidCallback? onTap,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _muted),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
            if (buttonLabel != null && onTap != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.add),
                label: Text(buttonLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmDeleteMed(Medicine med) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete medicine?'),
        content: Text('Remove "${med.name}" and cancel all its future alarms?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _red),
            onPressed: () {
              ref
                  .read(remindersControllerProvider.notifier)
                  .deleteMedicine(med.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Add Medicine Bottom Sheet Form ─────────────────────────────────────────

  Future<void> _scanMedicineLabel(
    BuildContext sheetCtx,
    TextEditingController nameCtl,
    TextEditingController dosageCtl,
    void Function(void Function()) setSheet,
    void Function(bool) setScanning,
  ) async {
    setScanning(true);
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo == null) return;

      final result =
          await ref.read(medicineLabelScannerProvider).scan(photo.path);
      if (result == null) {
        if (sheetCtx.mounted) {
          ScaffoldMessenger.of(sheetCtx).showSnackBar(
            const SnackBar(
              content: Text(
                "Couldn't read the label clearly — try a closer, "
                'well-lit photo, or type it in.',
              ),
            ),
          );
        }
        return;
      }

      setSheet(() {
        nameCtl.text = result.name;
        if (result.dosage != null) dosageCtl.text = result.dosage!;
      });
      if (sheetCtx.mounted) {
        ScaffoldMessenger.of(sheetCtx).showSnackBar(
          const SnackBar(
            content: Text('Detected from photo — please check it\'s correct.'),
          ),
        );
      }
    } finally {
      setScanning(false);
    }
  }

  Future<void> _openAddMedicineSheet(BuildContext context) async {
    await ref.read(alarmServiceProvider).requestPermissions();
    if (!context.mounted) return;

    final nameCtl = TextEditingController();
    final dosageCtl = TextEditingController();
    final purposeCtl = TextEditingController();
    bool scanningLabel = false;

    String frequency = 'Daily';
    String sound = 'default'; // 'default', 'gentle', 'chime', 'urgent', 'classic'
    bool morning = true;
    TimeOfDay morningTime = const TimeOfDay(hour: 9, minute: 0);
    bool afternoon = false;
    TimeOfDay afternoonTime = const TimeOfDay(hour: 14, minute: 0);
    bool night = false;
    TimeOfDay nightTime = const TimeOfDay(hour: 21, minute: 0);
    DateTime startDate = DateTime.now();
    DateTime? endDate;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Add New Medicine & Exact Alarm',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Scan package — reads the name/dosage off a photo of
                    // the box on-device, so typing is optional.
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: scanningLabel
                            ? null
                            : () => _scanMedicineLabel(
                                  sheetCtx,
                                  nameCtl,
                                  dosageCtl,
                                  setSheet,
                                  (v) => setSheet(() => scanningLabel = v),
                                ),
                        icon: scanningLabel
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.document_scanner_rounded),
                        label: Text(
                          scanningLabel ? 'Reading label…' : 'Scan package',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Name
                    TextField(
                      controller: nameCtl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Medicine Name *',
                        hintText: 'e.g. Paracetamol, Metformin',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Dosage
                    TextField(
                      controller: dosageCtl,
                      decoration: const InputDecoration(
                        labelText: 'Dosage',
                        hintText: 'e.g. 500 mg, 1 tablet',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Custom Alarm Sound Selection
                    const Text(
                      'Alarm Sound',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in ['default', 'gentle', 'chime', 'urgent', 'classic'])
                          ChoiceChip(
                            label: Text(s.toUpperCase()),
                            selected: sound == s,
                            onSelected: (val) {
                              if (val) setSheet(() => sound = s);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Frequency
                    const Text(
                      'Frequency',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final f in ['Daily', 'Twice Daily', 'Weekly', 'As needed'])
                          ChoiceChip(
                            label: Text(f),
                            selected: frequency == f,
                            onSelected: (val) {
                              if (val) setSheet(() => frequency = f);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Schedule Slots with Exact Time Pickers
                    const Text(
                      'Exact Alarm Slots & Times',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      children: [
                        _buildSlotTimeRow(
                          label: '🌅 Morning',
                          selected: morning,
                          time: morningTime,
                          onToggle: (val) => setSheet(() => morning = val),
                          onPickTime: () async {
                            final picked = await showTimePicker(
                              context: sheetCtx,
                              initialTime: morningTime,
                            );
                            if (picked != null) setSheet(() => morningTime = picked);
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildSlotTimeRow(
                          label: '☀️ Afternoon',
                          selected: afternoon,
                          time: afternoonTime,
                          onToggle: (val) => setSheet(() => afternoon = val),
                          onPickTime: () async {
                            final picked = await showTimePicker(
                              context: sheetCtx,
                              initialTime: afternoonTime,
                            );
                            if (picked != null) setSheet(() => afternoonTime = picked);
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildSlotTimeRow(
                          label: '🌙 Night',
                          selected: night,
                          time: nightTime,
                          onToggle: (val) => setSheet(() => night = val),
                          onPickTime: () async {
                            final picked = await showTimePicker(
                              context: sheetCtx,
                              initialTime: nightTime,
                            );
                            if (picked != null) setSheet(() => nightTime = picked);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Dates
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: sheetCtx,
                                initialDate: startDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setSheet(() => startDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start Date',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                DateFormat.yMMMd().format(startDate),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: sheetCtx,
                                initialDate: endDate ?? startDate.add(const Duration(days: 7)),
                                firstDate: startDate,
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setSheet(() => endDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'End Date (Optional)',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                endDate != null
                                    ? DateFormat.yMMMd().format(endDate!)
                                    : 'Ongoing',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Purpose / Notes
                    TextField(
                      controller: purposeCtl,
                      decoration: const InputDecoration(
                        labelText: 'Purpose / Notes (Optional)',
                        hintText: 'e.g. Take after breakfast for blood pressure',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          if (nameCtl.text.trim().isEmpty) return;
                          ref.read(remindersControllerProvider.notifier).addMedicine(
                                name: nameCtl.text,
                                dosage: dosageCtl.text,
                                frequency: frequency,
                                morning: morning,
                                morningHour: morningTime.hour,
                                morningMinute: morningTime.minute,
                                afternoon: afternoon,
                                afternoonHour: afternoonTime.hour,
                                afternoonMinute: afternoonTime.minute,
                                night: night,
                                nightHour: nightTime.hour,
                                nightMinute: nightTime.minute,
                                startDate: startDate,
                                endDate: endDate,
                                purpose: purposeCtl.text,
                                sound: sound,
                              );
                          Navigator.of(sheetCtx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Exact alarm scheduled for ${nameCtl.text}'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const Text(
                          'Save & Schedule Alarm',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameCtl.dispose();
    dosageCtl.dispose();
    purposeCtl.dispose();
  }

  Widget _buildSlotTimeRow({
    required String label,
    required bool selected,
    required TimeOfDay time,
    required ValueChanged<bool> onToggle,
    required VoidCallback onPickTime,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _primary : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            activeColor: _primary,
            onChanged: (val) => onToggle(val ?? false),
          ),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: _ink),
          ),
          const Spacer(),
          if (selected)
            TextButton.icon(
              onPressed: onPickTime,
              icon: const Icon(Icons.access_time_rounded, size: 16),
              label: Text(time.format(context)),
            ),
        ],
      ),
    );
  }
}
