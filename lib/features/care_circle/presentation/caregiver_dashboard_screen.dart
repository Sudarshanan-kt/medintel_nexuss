import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/route_names.dart';
import '../../auth/application/auth_controller.dart';
import '../application/care_circle_controller.dart';
import '../application/care_task_controller.dart';
import '../domain/care_circle_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Caregiver identity — violet, matching the caregiver sign-in screen.
//
// The whole point of the colour split is that someone who looks after a
// parent can tell at a glance whose data they're looking at. Kept local for
// the same reason the patient dashboard keeps its mint tokens local.
// ─────────────────────────────────────────────────────────────────────────────

const Color _bg = Color(0xFFF4F1FC);
const Color _violet = Color(0xFF7C5CFC);
const Color _violetLight = Color(0xFFB6A4FF);
const Color _violetDeep = Color(0xFF5B3FD9);
const Color _violetSoft = Color(0xFFEEE9FE);
const Color _ink = Color(0xFF241E3B);
const Color _muted = Color(0xFF7C748F);
const Color _card = Colors.white;
const Color _cardStroke = Color(0xFFEBE6F7);
const Color _amber = Color(0xFFEA9C1A);
const Color _red = Color(0xFFE0554B);
const Color _greenOk = Color(0xFF12A97D);

const LinearGradient _caregiverGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_violetLight, _violetDeep],
);

/// Home for someone looking after other people.
///
/// Deliberately not the patient dashboard with different data in it. A
/// caregiver's question is "is everyone alright, and what needs doing?" —
/// so the screen leads with the people, then what's gone wrong, then what's
/// outstanding. Their own medicines aren't here at all; that's the patient
/// side of the app.
class CaregiverDashboardScreen extends ConsumerWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final circle = ref.watch(careCircleControllerProvider);
    final name = (auth?.user?.displayName ?? 'there').trim().split(' ').first;
    final patients = circle.linkedPatients;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _CareBackdrop()),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: _violet,
              onRefresh: () =>
                  ref.read(careCircleControllerProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                children: [
                  _TopBar(name: name),
                  const SizedBox(height: 20),

                  if (circle.loading && patients.isEmpty)
                    const _LoadingBlock()
                  else if (patients.isEmpty)
                    const _NoPatientsCard()
                  else ...[
                    _AlertsFeed(patients: patients),
                    const SizedBox(height: 22),

                    const _SectionLabel('People you care for'),
                    const SizedBox(height: 12),
                    for (final p in patients) ...[
                      _PatientCard(patient: p),
                      const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 10),
                    const _SectionLabel('Care tasks'),
                    const SizedBox(height: 12),
                    for (final p in patients)
                      _CareTasksBlock(patient: p),
                  ],

                  const SizedBox(height: 22),
                  const _SectionLabel('Quick actions'),
                  const SizedBox(height: 12),
                  _QuickActions(hasPatients: patients.isNotEmpty),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: _caregiverGradient,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.volunteer_activism_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Caregiver',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _violet,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout_rounded, color: _muted),
          onPressed: () =>
              ref.read(authControllerProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w800,
        color: _ink,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Alerts
// ─────────────────────────────────────────────────────────────────────────────

/// What a caregiver opens the app to check.
///
/// Derived from adherence the app already tracks — nothing here is invented.
/// When there's nothing wrong it says so plainly rather than padding the
/// screen with reassurance.
class _AlertsFeed extends StatelessWidget {
  const _AlertsFeed({required this.patients});
  final List<LinkedPatientView> patients;

  @override
  Widget build(BuildContext context) {
    final concerns = [
      for (final p in patients)
        if (p.adherence.hasAnyData && p.adherence.weeklyPercent < 80)
          (
            p.member.patientDisplayName,
            p.adherence.weeklyPercent,
            p.adherence.weeklyPercent < 50,
          ),
    ];

    if (concerns.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardStroke),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _greenOk.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: _greenOk, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No missed doses flagged this week.',
                style: TextStyle(fontSize: 14, color: _ink),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: _red, size: 20),
              const SizedBox(width: 8),
              Text(
                concerns.length == 1
                    ? 'Needs attention'
                    : '${concerns.length} need attention',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final (who, percent, severe) in concerns)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: severe ? _red : _amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$who took ${percent.round()}% of doses this week',
                      style: const TextStyle(fontSize: 13.5, color: _muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Patients
// ─────────────────────────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient});
  final LinkedPatientView patient;

  Color get _tone {
    if (!patient.adherence.hasAnyData) return _muted;
    final p = patient.adherence.weeklyPercent;
    if (p >= 80) return _greenOk;
    if (p >= 50) return _amber;
    return _red;
  }

  @override
  Widget build(BuildContext context) {
    final a = patient.adherence;
    final initials = patient.member.patientDisplayName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardStroke),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: _violetSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: const TextStyle(
                    color: _violetDeep,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.member.patientDisplayName,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.hasAnyData
                          ? '${a.streakDays}-day streak'
                          : 'No doses logged yet',
                      style: const TextStyle(fontSize: 12.5, color: _muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    a.hasAnyData ? '${a.weeklyPercent.round()}%' : '—',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: _tone,
                    ),
                  ),
                  const Text(
                    'this week',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            ],
          ),
          if (a.hasAnyData) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                for (final day in a.last7Days)
                  Expanded(
                    child: Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: !day.hasData
                            ? _violetSoft
                            : day.isPerfect
                                ? _greenOk
                                : _amber,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
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
// Care tasks
// ─────────────────────────────────────────────────────────────────────────────

/// The open tasks for one circle. Loads per patient, because that's how the
/// repository is keyed — a caregiver with three patients makes three small
/// fetches rather than one combined query that would need a new endpoint.
class _CareTasksBlock extends ConsumerWidget {
  const _CareTasksBlock({required this.patient});
  final LinkedPatientView patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(careTasksProvider(patient.member.patientId));

    return tasks.when(
      loading: () => const SizedBox.shrink(),
      // A failed task fetch shouldn't blank the dashboard — the patient
      // cards above it are the more important information.
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final open =
            list.where((t) => t.status != 'done').toList(growable: false);
        if (open.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _cardStroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For ${patient.member.patientDisplayName}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _violet,
                ),
              ),
              const SizedBox(height: 10),
              for (final task in open.take(4)) _TaskRow(task: task),
            ],
          ),
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final CareTask task;

  @override
  Widget build(BuildContext context) {
    final claimed = task.claimedByName != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            claimed
                ? Icons.person_pin_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: claimed ? _violet : _muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                if (claimed)
                  Text(
                    '${task.claimedByName} is on it',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.hasPatients});
  final bool hasPatients;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.groups_rounded,
            label: 'Care circle',
            onTap: () => context.go(Routes.careCircle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.call_rounded,
            label: 'Emergency',
            // Deliberately opens the dialer rather than dialling: a
            // caregiver tapping around the app should never place a call
            // by accident.
            onTap: hasPatients
                ? () => launchUrl(Uri.parse('tel:'))
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.person_rounded,
            label: 'Profile',
            onTap: () => context.go(Routes.profile),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _cardStroke),
        ),
        child: Column(
          children: [
            Icon(icon, color: enabled ? _violet : _muted, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: enabled ? _ink : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / loading
// ─────────────────────────────────────────────────────────────────────────────

class _NoPatientsCard extends StatelessWidget {
  const _NoPatientsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cardStroke),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _violetSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.group_add_rounded,
                color: _violetDeep, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            "You're not caring for anyone yet.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ask the person you look after to invite you from their '
            'Care Circle. Their medicines and adherence will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: _muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _violet,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => context.go(Routes.careCircle),
              child: const Text(
                'Manage Care Circle',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: CircularProgressIndicator(color: _violet),
      ),
    );
  }
}

class _CareBackdrop extends StatelessWidget {
  const _CareBackdrop();

  static const List<(Alignment, IconData, double, double)> _items = [
    (Alignment(-0.88, -0.94), Icons.favorite_rounded, 50, .13),
    (Alignment(0.86, -0.90), Icons.groups_rounded, 58, .12),
    (Alignment(0.92, -0.20), Icons.medication_rounded, 44, .10),
    (Alignment(-0.90, 0.20), Icons.health_and_safety_rounded, 52, .10),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          children: [
            for (final (align, icon, size, opacity) in _items)
              Align(
                alignment: align,
                child: Icon(icon,
                    size: size, color: _violet.withValues(alpha: opacity)),
              ),
          ],
        ),
      ),
    );
  }
}
