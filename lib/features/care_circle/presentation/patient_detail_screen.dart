import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/navigation.dart';
import '../../../app/router/route_names.dart';
import '../../reminders/adherence_controller.dart';
import '../../reminders/domain/medicine.dart';
import '../application/care_circle_controller.dart';
import 'care_task_board.dart';
import 'caregiver_theme.dart';

/// One linked patient, in detail.
///
/// The dashboard answers "is anything wrong?". This answers "what, exactly?"
/// — which dose was missed, on which day, from which medicine. Without it a
/// caregiver could see that their mother took 62% of her doses this week and
/// had no way to find out which ones, which is an alarm with no information
/// attached.
///
/// Everything here is already in memory from the dashboard's fetch, so
/// opening it costs no round trip.
class PatientDetailScreen extends ConsumerWidget {
  const PatientDetailScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, not read: if the link is revoked while this screen is open,
    // the patient drops out of the list and this rebuilds into the
    // no-longer-linked state rather than showing stale health data.
    ref.watch(careCircleControllerProvider);
    final patient =
        ref.read(careCircleControllerProvider.notifier).patientById(patientId);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: kInk,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.canPop()
              ? context.pop()
              : context.backOr(Routes.caregiverHome),
        ),
        title: Text(
          patient?.member.patientDisplayName ?? 'Patient',
          style: kCardTitle,
        ),
      ),
      body: patient == null
          ? const _NoLongerLinked()
          : RefreshIndicator(
              color: kViolet,
              onRefresh: () =>
                  ref.read(careCircleControllerProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                children: [
                  _AdherenceHero(patient: patient),
                  const SizedBox(height: 20),
                  _WeekBreakdown(patient: patient),
                  const SizedBox(height: 20),
                  _MissedDoses(patient: patient),
                  const SizedBox(height: 20),
                  _CurrentMedicines(patient: patient),
                  const SizedBox(height: 20),
                  CareTaskBoard(
                    patientId: patientId,
                    patientName: patient.member.patientDisplayName,
                  ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adherence summary
// ─────────────────────────────────────────────────────────────────────────────

class _AdherenceHero extends StatelessWidget {
  const _AdherenceHero({required this.patient});
  final LinkedPatientView patient;

  @override
  Widget build(BuildContext context) {
    final a = patient.adherence;
    final tone = adherenceTone(a.weeklyPercent, hasData: a.hasAnyData);
    final word = adherenceWord(a.weeklyPercent, hasData: a.hasAnyData);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.hasAnyData
                          ? '${a.weeklyPercent.round()}%'
                          : 'No data',
                      style: kMetric.copyWith(color: tone),
                    ),
                    const SizedBox(height: 2),
                    const Text('of doses taken this week', style: kBodyMuted),
                  ],
                ),
              ),
              // The word carries the same meaning as the colour, for anyone
              // who can't rely on the colour.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  word,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          if (a.hasAnyData && a.streakDays > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.local_fire_department_rounded,
                    size: 20, color: kViolet,),
                const SizedBox(width: 8),
                Text(
                  a.streakDays == 1
                      ? '1 day with every dose taken'
                      : '${a.streakDays} days in a row with every dose taken',
                  style: kBody,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seven-day breakdown
// ─────────────────────────────────────────────────────────────────────────────

/// The dashboard's seven bars, given labels and numbers.
///
/// On the dashboard the same row is a glance; here it has to be readable, so
/// each day carries its initial, its counts, and a screen-reader description.
class _WeekBreakdown extends StatelessWidget {
  const _WeekBreakdown({required this.patient});
  final LinkedPatientView patient;

  @override
  Widget build(BuildContext context) {
    final days = patient.adherence.last7Days;
    if (days.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The last 7 days', style: kCardTitle),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Semantics(
                    label: _describe(day),
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(
                          DateFormat('E').format(day.date).substring(0, 1),
                          style: kLabel.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: !day.hasData
                                ? kVioletSoft
                                : day.isPerfect
                                    ? kGreenOk
                                    : kAmber,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            !day.hasData ? '–' : '${day.missed}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: day.hasData ? Colors.white : kMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Each bar shows how many doses were missed that day. '
            'A dash means nothing was logged.',
            style: kBodyMuted,
          ),
        ],
      ),
    );
  }

  String _describe(DayAdherence day) {
    final when = DateFormat('EEEE d MMMM').format(day.date);
    if (!day.hasData) return '$when: nothing logged.';
    if (day.missed == 0) return '$when: all ${day.taken} doses taken.';
    return '$when: ${day.missed} missed, ${day.taken} taken.';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Missed doses
// ─────────────────────────────────────────────────────────────────────────────

class _MissedDoses extends StatelessWidget {
  const _MissedDoses({required this.patient});
  final LinkedPatientView patient;

  static const _maxShown = 12;

  @override
  Widget build(BuildContext context) {
    final missed = patient.missedDoses;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(
        stroke: missed.isEmpty ? null : kRed.withValues(alpha: 0.28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            missed.isEmpty ? 'Missed doses' : 'Missed doses (${missed.length})',
            style: kCardTitle,
          ),
          const SizedBox(height: 14),
          if (missed.isEmpty)
            const Text(
              'None logged. Every dose recorded so far was taken.',
              style: kBodyMuted,
            )
          else ...[
            for (final dose in missed.take(_maxShown)) _MissedRow(dose: dose),
            if (missed.length > _maxShown)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ ${missed.length - _maxShown} older',
                  style: kBodyMuted,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MissedRow extends StatelessWidget {
  const _MissedRow({required this.dose});
  final DoseLog dose;

  /// "this morning" / "yesterday evening" / "Tue 3 Jun, morning".
  ///
  /// Relative wording for the recent past because that is how someone asks
  /// the question — "did she take it this morning?" — and absolute dates
  /// once it is far enough back that relative wording stops helping.
  String get _when {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
      dose.timestamp.year,
      dose.timestamp.month,
      dose.timestamp.day,
    );
    final slot = switch (dose.scheduleSlot) {
      'morning' => 'morning',
      'afternoon' => 'afternoon',
      'night' => 'evening',
      _ => '',
    };
    final diff = today.difference(day).inDays;
    if (diff == 0) return slot.isEmpty ? 'today' : 'this $slot';
    if (diff == 1) return slot.isEmpty ? 'yesterday' : 'yesterday $slot';
    final date = DateFormat('E d MMM').format(dose.timestamp);
    return slot.isEmpty ? date : '$date, $slot';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(color: kRed, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.dosage.trim().isEmpty
                      ? dose.medicineName
                      : '${dose.medicineName} · ${dose.dosage}',
                  style: kBody.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(_when, style: kBodyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Current medicines
// ─────────────────────────────────────────────────────────────────────────────

class _CurrentMedicines extends StatelessWidget {
  const _CurrentMedicines({required this.patient});
  final LinkedPatientView patient;

  @override
  Widget build(BuildContext context) {
    final active = patient.medicines
        .where((m) => m.isActive && !m.isCompleted)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current medicines', style: kCardTitle),
          const SizedBox(height: 14),
          if (active.isEmpty)
            const Text('No active medicines on their list.', style: kBodyMuted)
          else
            for (final med in active) _MedicineRow(med: med),
          const SizedBox(height: 6),
          // Says plainly what this screen is not. A caregiver reading a drug
          // list will wonder whether they are seeing everything.
          const Text(
            'Read-only. Only their medicines and dose history are shared with '
            'you — not the rest of their health profile.',
            style: kBodyMuted,
          ),
        ],
      ),
    );
  }
}

class _MedicineRow extends StatelessWidget {
  const _MedicineRow({required this.med});
  final Medicine med;

  String get _schedule {
    final slots = [
      if (med.morning) 'morning',
      if (med.afternoon) 'afternoon',
      if (med.night) 'evening',
    ];
    if (slots.isEmpty) return med.frequency;
    return slots.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: kVioletSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.medication_rounded,
                size: 19, color: kVioletDeep,),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  med.dosage.trim().isEmpty
                      ? med.name
                      : '${med.name} · ${med.dosage}',
                  style: kBody.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(_schedule, style: kBodyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Revoked link
// ─────────────────────────────────────────────────────────────────────────────

class _NoLongerLinked extends StatelessWidget {
  const _NoLongerLinked();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_rounded, size: 44, color: kMuted),
            const SizedBox(height: 16),
            const Text(
              "You're no longer linked to this person",
              style: kCardTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'They may have removed you from their care circle. Their data '
              'is no longer available to you.',
              style: kBodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kViolet),
              onPressed: () => context.backOr(Routes.caregiverHome),
              child: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
