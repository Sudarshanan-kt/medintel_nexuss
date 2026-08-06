import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/utils/extensions.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../auth/application/auth_controller.dart';
import '../../care_circle/application/care_circle_controller.dart';
import '../../reminders/adherence_controller.dart';
import '../../reminders/domain/medicine.dart';
import '../../reminders/reminders_controller.dart';
import '../../reports/domain/medical_report.dart';
import '../../scan/domain/prescription_scan.dart';
import '../application/dashboard_controller.dart';
import '../domain/quick_action.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local design tokens.
//
// Same reasoning as the redesigned sign-in screen: this dashboard has its own
// mint/emerald identity, kept local to this file rather than folded into the
// app-wide AppColors. That keeps the rest of the app (which still reads
// AppColors) completely unaffected by this restyle — only this screen's look
// changes, none of its data or navigation.
// ─────────────────────────────────────────────────────────────────────────────

const Color _bg = Color(0xFFEFF3F5);
const Color _green = Color(0xFF12A97D);
const Color _greenLight = Color(0xFF5FD6A4);
const Color _greenDeep = Color(0xFF0B8F63);
const Color _ink = Color(0xFF1B2B33);
const Color _muted = Color(0xFF7C8D96);
const Color _card = Colors.white;
const Color _cardStroke = Color(0xFFE9EFF1);
const Color _amber = Color(0xFFEA9C1A);
const Color _red = Color(0xFFE0554B);
const Color _backdropTint = Color(0xFFB9D2E4);

const LinearGradient _brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_greenLight, _greenDeep],
);

// Caregiver mode gets its own identity — a distinct violet palette — so
// switching the header toggle reads as "a different screen", not a
// re-skinned section of the patient dashboard.
const Color _bgCaregiver = Color(0xFFF4F1FC);
const Color _violet = Color(0xFF7C5CFC);
const Color _violetLight = Color(0xFFB6A4FF);
const Color _violetDeep = Color(0xFF5B3FD9);
const Color _violetSoft = Color(0xFFEEE9FE);
const Color _violetBackdropTint = Color(0xFFC9BEEF);

const LinearGradient _caregiverGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_violetLight, _violetDeep],
);

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  Future<void> _openQuickActions(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    return showAppSheet<void>(
      context: context,
      builder: (_) => _QuickActionsSheet(t: t),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final dash = ref.watch(dashboardStateProvider);
    final reminders = ref.watch(remindersControllerProvider);
    final adherence = ref.watch(adherenceStateProvider);
    final careCircle = ref.watch(careCircleControllerProvider);
    final viewMode = ref.watch(dashboardViewModeProvider);
    final name = auth?.user?.displayName ?? 'there';
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    final nextDose = _nextDoseSlot(reminders.activeMedicines);
    final recent = _sortedActivity(t, dash.recentScans, dash.recentReports);

    final showCaregiverView = viewMode == DashboardViewMode.caregiver;

    return Scaffold(
      backgroundColor: showCaregiverView ? _bgCaregiver : _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: _FaintBackdrop(
              tint: showCaregiverView ? _violetBackdropTint : _backdropTint,
            ),
          ),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              physics: const BouncingScrollPhysics(),
              children: [
                _Header(
                  onMenuTap: () => _openQuickActions(context, ref),
                  onBellTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: _ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      content: Text(t.noNewNotifications),
                    ),
                  ),
                  name: firstName,
                  canSwitchCaregiver: true,
                  viewMode: viewMode,
                  onModeChanged: (m) =>
                      ref.read(dashboardViewModeProvider.notifier).state = m,
                ),

                if (showCaregiverView) ...[
                  const SizedBox(height: 22),
                  _CaregiverHero(patientCount: careCircle.linkedPatients.length),
                  const SizedBox(height: 26),
                  _CaregiverBody(careCircle: careCircle),
                ] else ...[
                  const SizedBox(height: 22),
                  Text(
                    '${DateTime.now().greeting},',
                    style: const TextStyle(fontSize: 17, color: _muted),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        firstName,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('👋', style: TextStyle(fontSize: 22)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your health, our priority.',
                    style: TextStyle(fontSize: 14.5, color: _muted),
                  ),

                  const SizedBox(height: 22),
                  const _HeroBanner(),

                  const SizedBox(height: 26),
                  _SectionHeader(
                    title: 'Today Overview',
                    onSeeAll: () => context.go(Routes.reports),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _OverviewCard(
                          icon: Icons.medication_rounded,
                          iconColor: _green,
                          iconBg: const Color(0xFFDFF6EB),
                          label: 'Medicines',
                          value: '${dash.medicineCount}',
                          caption: t.statScansCount(dash.scansCount),
                          captionColor: _muted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OverviewCard(
                          icon: Icons.event_available_rounded,
                          iconColor: _greenDeep,
                          iconBg: const Color(0xFFDFF6EB),
                          label: 'Adherence',
                          value: adherence.weeklyPercent < 0
                              ? '—'
                              : '${adherence.weeklyPercent.round()}%',
                          caption: 'This Week',
                          captionColor: _muted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OverviewCard(
                          icon: Icons.description_rounded,
                          iconColor: _red,
                          iconBg: const Color(0xFFFBE7E5),
                          label: 'Reports',
                          value: '${dash.reportsCount}',
                          caption: 'Uploaded',
                          captionColor: _muted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OverviewCard(
                          icon: Icons.shield_rounded,
                          iconColor: dash.riskAlertCount > 0 ? _red : _green,
                          iconBg: dash.riskAlertCount > 0
                              ? const Color(0xFFFBE7E5)
                              : const Color(0xFFDFF6EB),
                          label: 'Alerts',
                          value: '${dash.riskAlertCount}',
                          caption: dash.riskAlertCount > 0
                              ? t.statReviewNow
                              : t.statAllClear,
                          captionColor:
                              dash.riskAlertCount > 0 ? _red : _green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  _NextMedicineCard(
                    slot: nextDose,
                    onMarkTaken: nextDose == null
                        ? null
                        : () {
                            ref
                                .read(remindersControllerProvider.notifier)
                                .logDose(
                                  medicineId: nextDose.medicine.id,
                                  medicineName: nextDose.medicine.name,
                                  dosage: nextDose.medicine.dosage,
                                  scheduleSlot: nextDose.scheduleSlotKey,
                                  status: 'taken',
                                );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: _greenDeep,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                content: Text(
                                  'Marked ${nextDose.medicine.name} as taken',
                                ),
                              ),
                            );
                          },
                    onTap: () => context.go(Routes.reminders),
                  ),

                  const SizedBox(height: 20),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _StreakCard(
                            state: adherence,
                            onTap: () => context.go(Routes.reminders),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            children: [
                              _RecentCard(
                                item: recent.isEmpty ? null : recent.first,
                                onSeeAll: () => context.go(Routes.reports),
                              ),
                              const SizedBox(height: 14),
                              _EmergencyCard(
                                onTap: () => context.go(Routes.sos),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  _AssistantCard(onTap: () => context.go(Routes.assistant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Faint medical-iconography backdrop — matches the sign-in screen's identity,
// much sparser/paler here since real content sits over it the whole time.
// ─────────────────────────────────────────────────────────────────────────────

class _FaintBackdrop extends StatelessWidget {
  const _FaintBackdrop({this.tint = _backdropTint});
  final Color tint;

  static const List<(Alignment, IconData, double, double)> _items = [
    (Alignment(-0.75, -0.95), Icons.medical_services_outlined, 60, .22),
    (Alignment(0.05, -0.90), Icons.favorite_rounded, 68, .18),
    (Alignment(0.70, -0.92), Icons.medication_rounded, 56, .20),
    (Alignment(0.95, -0.72), Icons.biotech_rounded, 60, .18),
    (Alignment(-0.55, -0.55), Icons.monitor_heart_outlined, 70, .14),
    (Alignment(0.90, -0.30), Icons.water_drop_rounded, 48, .16),
    (Alignment(-0.92, 0.05), Icons.vaccines_rounded, 62, .16),
    (Alignment(0.30, 0.02), Icons.add_rounded, 40, .12),
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
                child: Icon(
                  icon,
                  size: size,
                  color: tint.withValues(alpha: opacity),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — menu (opens quick actions), notification bell, caregiver switch,
// avatar. All real, pre-existing actions — just relocated/restyled.
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.onMenuTap,
    required this.onBellTap,
    required this.name,
    required this.canSwitchCaregiver,
    required this.viewMode,
    required this.onModeChanged,
  });

  final VoidCallback onMenuTap;
  final VoidCallback onBellTap;
  final String name;
  final bool canSwitchCaregiver;
  final DashboardViewMode viewMode;
  final ValueChanged<DashboardViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final isCaregiver = viewMode == DashboardViewMode.caregiver;
    return Row(
      children: [
        _RoundIconButton(icon: Icons.menu_rounded, onTap: onMenuTap),
        const Spacer(),
        if (canSwitchCaregiver) ...[
          _CaregiverSwitch(mode: viewMode, onChanged: onModeChanged),
          const SizedBox(width: 10),
        ],
        _RoundIconButton(icon: Icons.notifications_none_rounded, onTap: onBellTap),
        const SizedBox(width: 12),
        _Avatar(name: name, caregiverMode: isCaregiver),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8DA4B4).withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 21, color: _ink),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.caregiverMode = false});
  final String name;
  final bool caregiverMode;

  String get _initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: caregiverMode ? _caregiverGradient : _brandGradient,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            _initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: caregiverMode ? _violet : _green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Caregiver-mode switch — same feature as before (Care Circle "Caring for"
/// lens), just restyled to sit in this screen's new header.
class _CaregiverSwitch extends StatelessWidget {
  const _CaregiverSwitch({required this.mode, required this.onChanged});
  final DashboardViewMode mode;
  final ValueChanged<DashboardViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCaregiver = mode == DashboardViewMode.caregiver;
    return Tooltip(
      message: isCaregiver
          ? 'Caregiver view is on — tap to switch back to yourself'
          : 'Switch to caregiver view',
      child: GestureDetector(
        onTap: () => onChanged(
          isCaregiver ? DashboardViewMode.me : DashboardViewMode.caregiver,
        ),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isCaregiver ? _violetSoft : Colors.white,
            borderRadius: BorderRadius.circular(23),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8DA4B4).withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_rounded,
                size: 15,
                color: isCaregiver ? _violet : _muted,
              ),
              SizedBox(
                width: 34,
                height: 24,
                child: Transform.scale(
                  scale: 0.62,
                  child: Switch(
                    value: isCaregiver,
                    onChanged: (v) => onChanged(
                      v ? DashboardViewMode.caregiver : DashboardViewMode.me,
                    ),
                    activeThumbColor: _violet,
                    activeTrackColor: Colors.white,
                    inactiveThumbColor: _muted,
                    inactiveTrackColor: Colors.white,
                    trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
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

// ─────────────────────────────────────────────────────────────────────────────
// Hero motivational banner
// ─────────────────────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDCF3E8), Color(0xFFE9F5F0)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user_rounded, color: _green, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 15.5, color: _ink, height: 1.3),
                    children: [
                      TextSpan(text: 'Health is your '),
                      TextSpan(
                        text: 'greatest wealth',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _greenDeep,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Stay consistent. Stay healthy.',
                  style: TextStyle(fontSize: 13, color: _muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.favorite_rounded, color: _greenLight, size: 34),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header with "See all"
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _green,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: _green, size: 20),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Today Overview card
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.caption,
    required this.captionColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final String caption;
  final Color captionColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: captionColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Next Medicine
// ─────────────────────────────────────────────────────────────────────────────

class _NextMedicineCard extends StatelessWidget {
  const _NextMedicineCard({
    required this.slot,
    required this.onMarkTaken,
    required this.onTap,
  });

  final _DoseSlot? slot;
  final VoidCallback? onMarkTaken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardStroke),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFDFF6EB),
                shape: BoxShape.circle,
                border: Border.all(color: _green.withValues(alpha: 0.35), width: 2),
              ),
              child: const Icon(Icons.medication_liquid_rounded, color: _greenDeep, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Next Medicine',
                    style: TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    slot?.medicine.name ?? 'All medicines taken',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  if (slot != null) ...[
                    Text(
                      '${slot!.medicine.dosage} · ${slot!.label(AppLocalizations.of(context)!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _muted),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 14, color: _green),
                        const SizedBox(width: 4),
                        Text(
                          slot!.timeLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _green,
                          ),
                        ),
                      ],
                    ),
                  ] else
                    const Text(
                      'Nothing scheduled right now',
                      style: TextStyle(fontSize: 12.5, color: _muted),
                    ),
                ],
              ),
            ),
            if (onMarkTaken != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onMarkTaken,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: _brandGradient,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'Mark as Taken',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adherence streak (real data — computeAdherenceState's weekly window)
// ─────────────────────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.state, required this.onTap});
  final AdherenceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardStroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adherence Streak',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink),
            ),
            const SizedBox(height: 12),
            if (!state.hasAnyData)
              const Text(
                'Log a dose to start your streak.',
                style: TextStyle(fontSize: 12.5, color: _muted),
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    '${state.streakDays}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text(
                      'Days',
                      style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                state.streakDays > 0 ? 'Keep it up!' : 'Start today',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in state.last7Days)
                      Expanded(child: _DayBar(day: day)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, this.accentColor = _green});
  final DayAdherence day;
  final Color accentColor;

  Color get _color {
    if (!day.hasData) return const Color(0xFFE4EBEE);
    return day.isPerfect ? accentColor : _red;
  }

  double get _height {
    if (!day.hasData) return 6;
    return day.isPerfect ? 26 : 16;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(day.date, DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: _height,
            decoration: BoxDecoration(
              color: _color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            DateFormat.E().format(day.date).substring(0, 1),
            style: TextStyle(
              color: isToday ? _ink : _muted,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ─────────────────────────────────────────────────────────────────────────────
// Recent report/scan
// ─────────────────────────────────────────────────────────────────────────────

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item, required this.onSeeAll});
  final _ActivityItem? item;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Report',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink),
                ),
              ),
              GestureDetector(
                onTap: onSeeAll,
                child: const Text(
                  'See All',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (item == null)
            const Text(
              'No reports or scans yet.',
              style: TextStyle(fontSize: 12.5, color: _muted),
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.go(item!.routePath),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: item!.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(item!.icon, size: 18, color: item!.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item!.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        Text(
                          DateFormat.MMMd().format(item!.timestamp),
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  _StatusTag(label: item!.subtitle, color: item!.color),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Emergency SOS
// ─────────────────────────────────────────────────────────────────────────────

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardStroke),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emergency',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'SOS is active',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _red),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Alerts your emergency contacts',
                    style: TextStyle(fontSize: 10.5, color: _muted),
                  ),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFBE7E5),
                shape: BoxShape.circle,
                border: Border.all(color: _red.withValues(alpha: 0.4), width: 1.5),
              ),
              child: const Center(
                child: Text(
                  'SOS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI assistant entry point
// ─────────────────────────────────────────────────────────────────────────────

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardStroke),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFDFF6EB),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_rounded, color: _greenDeep, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Health Assistant',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Ask me anything about your health,\nmedicines, reports and more.',
                    style: TextStyle(fontSize: 11.5, color: _muted, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                gradient: _brandGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Caregiver-mode body (unchanged feature — restyled to the new palette)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Caregiver hero — the violet identity that replaces the patient greeting +
// green banner entirely, so toggling the header switch reads as landing on
// a genuinely different screen.
// ─────────────────────────────────────────────────────────────────────────────

class _CaregiverHero extends StatelessWidget {
  const _CaregiverHero({required this.patientCount});
  final int patientCount;

  String get _subtitle {
    if (patientCount == 0) return "You're not linked to anyone yet";
    if (patientCount == 1) return "Watching over 1 person's adherence";
    return 'Watching over $patientCount people\'s adherence';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: _caregiverGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _violet.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.volunteer_activism_rounded, color: _violetDeep, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Caring for',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaregiverBody extends StatelessWidget {
  const _CaregiverBody({required this.careCircle});
  final CareCircleState careCircle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (careCircle.loading && careCircle.linkedPatients.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: _violet),
            ),
          )
        else if (careCircle.linkedPatients.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _violetSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You're not caring for anyone yet.",
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink),
                ),
                SizedBox(height: 4),
                Text(
                  'Ask them to send you a Care Circle invite code, or open '
                  'Care Circle to enter one.',
                  style: TextStyle(fontSize: 12.5, color: _muted),
                ),
              ],
            ),
          )
        else ...[
          Text(
            careCircle.linkedPatients.length == 1
                ? 'Your person'
                : 'Your people (${careCircle.linkedPatients.length})',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink),
          ),
          const SizedBox(height: 12),
          for (final p in careCircle.linkedPatients) ...[
            _PatientOverviewCard(patient: p),
            const SizedBox(height: 14),
          ],
        ],
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => context.go(Routes.careCircle),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _cardStroke),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.diversity_3_rounded, size: 18, color: _violet),
                SizedBox(width: 8),
                Text(
                  'Manage Care Circle',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _violet),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A single linked patient's card — their name, an avatar medallion, and
/// their real adherence streak/weekly bars, rendered in the violet identity.
class _PatientOverviewCard extends StatelessWidget {
  const _PatientOverviewCard({required this.patient});
  final LinkedPatientView patient;

  String get _initial {
    final n = patient.member.patientDisplayName.trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final state = patient.adherence;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: _caregiverGradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  patient.member.patientDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink),
                ),
              ),
              if (state.weeklyPercent >= 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _violetSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${state.weeklyPercent.round()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _violetDeep,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!state.hasAnyData)
            const Text(
              'No adherence logged yet.',
              style: TextStyle(fontSize: 12.5, color: _muted),
            )
          else ...[
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 4),
                Text(
                  '${state.streakDays}-day streak',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in state.last7Days)
                    Expanded(child: _DayBar(day: day, accentColor: _violet)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions — relocated behind the header's menu button so the main
// screen matches the new, cleaner layout without dropping any destination.
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsSheet extends ConsumerWidget {
  const _QuickActionsSheet({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: _cardStroke,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const Text(
            'Quick actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: [
              for (final a in QuickAction.values)
                _QuickActionTile(
                  action: a,
                  label: _quickActionLabel(t, a),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (a.routePath != null) {
                      context.go(a.routePath!);
                    } else {
                      final label = _quickActionLabel(t, a).replaceAll('\n', ' ');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: _ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          content: Text(t.comingSoon(label)),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.action,
    required this.label,
    required this.onTap,
  });

  final QuickAction action;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFDFF6EB),
              shape: BoxShape.circle,
            ),
            child: Icon(action.icon, color: _greenDeep, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _ink),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick action label lookup (enum stores English only; UI needs the
// localized form)
// ─────────────────────────────────────────────────────────────────────────────

String _quickActionLabel(AppLocalizations t, QuickAction a) {
  switch (a) {
    case QuickAction.medicineReminder:
      return t.quickActionMedicineReminder;
    case QuickAction.nearbyPharmacies:
      return t.quickActionNearbyPharmacies;
    case QuickAction.healthRisk:
      return t.quickActionHealthRisk;
    case QuickAction.genericSwap:
      return t.quickActionGenericSwap;
    case QuickAction.emergencyContacts:
      return t.quickActionEmergencyContacts;
    default:
      return a.label;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity sorting (pure — no widgets)
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityItem {
  const _ActivityItem({
    required this.timestamp,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.routePath,
  });

  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String routePath;
}

List<_ActivityItem> _sortedActivity(
  AppLocalizations t,
  List<PrescriptionScan> scans,
  List<MedicalReport> reports,
) {
  final items = <_ActivityItem>[];
  for (final s in scans) {
    items.add(
      _ActivityItem(
        timestamp: s.capturedAt ?? DateTime.now(),
        icon: Icons.center_focus_strong_rounded,
        color: _green,
        title: t.activityPrescriptionScan,
        subtitle: t.activityMedicinesRecorded(s.medicines.length),
        routePath: Routes.scanResultId(s.id),
      ),
    );
  }
  for (final r in reports) {
    items.add(
      _ActivityItem(
        timestamp: r.uploadedAt,
        icon: Icons.description_rounded,
        color: r.hasRiskFinding
            ? _amber
            : (r.status == ReportStatus.analyzed ? _green : _muted),
        title: r.title,
        subtitle: r.status != ReportStatus.analyzed
            ? t.activityProcessing
            : (r.hasRiskFinding ? 'Review' : 'Normal'),
        routePath: Routes.reportById(r.id),
      ),
    );
  }
  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return items;
}

// ─────────────────────────────────────────────────────────────────────────────
// Next dose (from active medicine reminders)
// ─────────────────────────────────────────────────────────────────────────────

enum _DoseSlotKind { morning, afternoon, night }

class _DoseSlot {
  const _DoseSlot(this.medicine, this.kind, this.hour, this.minute);
  final Medicine medicine;
  final _DoseSlotKind kind;
  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  /// Matches the `scheduleSlot` string convention `logDose` callers use
  /// elsewhere (see medicine_reminder_screen.dart).
  String get scheduleSlotKey => switch (kind) {
        _DoseSlotKind.morning => 'morning',
        _DoseSlotKind.afternoon => 'afternoon',
        _DoseSlotKind.night => 'night',
      };

  String label(AppLocalizations t) => switch (kind) {
        _DoseSlotKind.morning => t.doseSlotMorning,
        _DoseSlotKind.afternoon => t.doseSlotAfternoon,
        _DoseSlotKind.night => t.doseSlotNight,
      };

  String get timeLabel {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour < 12 ? 'AM' : 'PM';
    final mm = minute.toString().padLeft(2, '0');
    return '$h12:$mm $ampm';
  }
}

_DoseSlot? _nextDoseSlot(List<Medicine> activeMedicines) {
  final slots = <_DoseSlot>[];
  for (final m in activeMedicines) {
    if (m.morning) {
      slots.add(_DoseSlot(m, _DoseSlotKind.morning, m.morningHour, m.morningMinute));
    }
    if (m.afternoon) {
      slots.add(_DoseSlot(m, _DoseSlotKind.afternoon, m.afternoonHour, m.afternoonMinute));
    }
    if (m.night) {
      slots.add(_DoseSlot(m, _DoseSlotKind.night, m.nightHour, m.nightMinute));
    }
  }
  if (slots.isEmpty) return null;

  slots.sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
  final nowMinutes = DateTime.now().hour * 60 + DateTime.now().minute;
  return slots.firstWhere(
    (s) => s.minutesOfDay >= nowMinutes,
    orElse: () => slots.first, // nothing left today — show tomorrow's earliest
  );
}
