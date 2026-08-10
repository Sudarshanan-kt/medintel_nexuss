import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../auth/application/auth_controller.dart';
import '../application/care_circle_controller.dart';
import 'care_task_board.dart';
import 'caregiver_theme.dart';

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
      backgroundColor: kBg,
      body: Stack(
        children: [
          const Positioned.fill(child: _CareBackdrop()),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: kViolet,
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
                  // Checked before the empty case, and this is the whole
                  // point of the ordering: a failed load used to fall
                  // through to "You're not caring for anyone yet", which
                  // tells a caregiver their circle is empty when in fact
                  // the app has no idea. Silence about a patient must never
                  // be presented as good news.
                  else if (circle.error != null)
                    _LoadFailedCard(
                      message: circle.error!,
                      onRetry: () => ref
                          .read(careCircleControllerProvider.notifier)
                          .refresh(),
                    )
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CareTaskBoard(
                          patientId: p.member.patientId,
                          patientName: p.member.patientDisplayName,
                          title: 'For ${p.member.patientDisplayName}',
                        ),
                      ),
                  ],

                  const SizedBox(height: 22),
                  const _SectionLabel('Quick actions'),
                  const SizedBox(height: 12),
                  _QuickActions(patients: patients),
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
            gradient: kCaregiverGradient,
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
                  color: kViolet,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: kInk,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout_rounded, color: kMuted),
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
        color: kInk,
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
          color: kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kCardStroke),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kGreenOk.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: kGreenOk, size: 20,),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No missed doses flagged this week.',
                style: TextStyle(fontSize: 14, color: kInk),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: kRed, size: 20,),
              const SizedBox(width: 8),
              Text(
                concerns.length == 1
                    ? 'Needs attention'
                    : '${concerns.length} need attention',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: kInk,
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
                      color: severe ? kRed : kAmber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$who took ${percent.round()}% of doses this week',
                      style: const TextStyle(fontSize: 13.5, color: kMuted),
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

/// One patient, and a way in.
///
/// Tapping opens [Routes.caregiverPatient]. Before this the card was inert:
/// it could tell you someone had taken 62% of their doses and offered no
/// route to which doses those were.
class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient});
  final LinkedPatientView patient;

  @override
  Widget build(BuildContext context) {
    final a = patient.adherence;
    final name = patient.member.patientDisplayName;
    final tone = adherenceTone(a.weeklyPercent, hasData: a.hasAnyData);
    final word = adherenceWord(a.weeklyPercent, hasData: a.hasAnyData);
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();

    return Semantics(
      button: true,
      label: a.hasAnyData
          ? '$name. $word. ${a.weeklyPercent.round()}% of doses taken this '
              'week. Open for detail.'
          : '$name. No doses logged yet. Open for detail.',
      excludeSemantics: true,
      child: Material(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.go(Routes.caregiverPatientFor(
            patient.member.patientId,
          ),),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kCardStroke),
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
                        color: kVioletSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initials.isEmpty ? '?' : initials,
                        style: const TextStyle(
                          color: kVioletDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: kCardTitle),
                          const SizedBox(height: 2),
                          Text(
                            // A streak of zero isn't a streak; saying
                            // "0-day streak" is noise where the word alone
                            // is the useful part.
                            !a.hasAnyData
                                ? 'No doses logged yet'
                                : a.streakDays > 0
                                    ? '$word · ${a.streakDays}-day streak'
                                    : word,
                            style: kBodyMuted.copyWith(
                              color: a.hasAnyData ? tone : kMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          a.hasAnyData ? '${a.weeklyPercent.round()}%' : '—',
                          style: kMetric.copyWith(fontSize: 23, color: tone),
                        ),
                        const Text('this week', style: kLabel),
                      ],
                    ),
                    const Icon(Icons.chevron_right_rounded, color: kMuted),
                  ],
                ),
                if (a.hasAnyData) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final day in a.last7Days)
                        Expanded(
                          child: Container(
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: !day.hasData
                                  ? kVioletSoft
                                  : day.isPerfect
                                      ? kGreenOk
                                      : kAmber,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions
// ─────────────────────────────────────────────────────────────────────────────

/// There used to be an "Emergency" tile here that opened the dialer on
/// `tel:` with no number in it — it could not have worked. A caregiver
/// cannot read `health_profiles`, which is where emergency contacts live and
/// where they should stay; sharing a patient's full profile to make one
/// button work would be the wrong trade. So the slot went to the thing a
/// caregiver actually does often: ask the circle for help.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.patients});
  final List<LinkedPatientView> patients;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            icon: Icons.add_task_rounded,
            label: 'Ask for help',
            onTap: patients.isEmpty ? null : () => _postTask(context, ref),
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

  /// Skips the picker when there's only one person to pick.
  Future<void> _postTask(BuildContext context, WidgetRef ref) async {
    var target = patients.first;
    if (patients.length > 1) {
      final chosen = await showModalBottomSheet<LinkedPatientView>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _PatientPicker(patients: patients),
      );
      if (chosen == null) return;
      target = chosen;
    }
    if (!context.mounted) return;
    await showAddCareTaskSheet(
      context,
      ref,
      patientId: target.member.patientId,
      patientName: target.member.patientDisplayName,
    );
  }
}

class _PatientPicker extends StatelessWidget {
  const _PatientPicker({required this.patients});
  final List<LinkedPatientView> patients;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('Who is this for?', style: kTitle),
          ),
          for (final p in patients)
            ListTile(
              minVerticalPadding: 12,
              leading: const CircleAvatar(
                backgroundColor: kVioletSoft,
                child: Icon(Icons.person_rounded, color: kVioletDeep),
              ),
              title: Text(p.member.patientDisplayName, style: kBody),
              onTap: () => Navigator.of(context).pop(p),
            ),
          const SizedBox(height: 12),
        ],
      ),
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
          color: kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kCardStroke),
        ),
        child: Column(
          children: [
            Icon(icon, color: enabled ? kViolet : kMuted, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: enabled ? kInk : kMuted,
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

/// Shown when the circle could not be loaded at all.
///
/// Deliberately not styled as an alert about a patient — nothing is known
/// about any patient right now, and that is exactly what it has to say.
class _LoadFailedCard extends StatelessWidget {
  const _LoadFailedCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(stroke: kAmber.withValues(alpha: 0.35)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: kAmber, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text("Couldn't load your circle", style: kCardTitle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(message, style: kBodyMuted),
          const SizedBox(height: 6),
          const Text(
            "This doesn't mean anything is wrong with the people you care "
            'for — it means the app has no current information about them.',
            style: kBodyMuted,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kViolet,
                minimumSize: const Size(0, kTapTarget),
              ),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPatientsCard extends StatelessWidget {
  const _NoPatientsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kCardStroke),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: kVioletSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.group_add_rounded,
                color: kVioletDeep, size: 28,),
          ),
          const SizedBox(height: 16),
          const Text(
            "You're not caring for anyone yet.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: kInk,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ask the person you look after to invite you from their '
            'Care Circle. Their medicines and adherence will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: kMuted, height: 1.45),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kViolet,
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
        child: CircularProgressIndicator(color: kViolet),
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
                    size: size, color: kViolet.withValues(alpha: opacity),),
              ),
          ],
        ),
      ),
    );
  }
}
