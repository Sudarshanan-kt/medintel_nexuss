import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../scan/application/scans_controller.dart';
import '../application/profile_controller.dart';
import '../domain/profile_record.dart';
import 'profile_sheets.dart';
import '../../../core/network/server_config.dart';
import 'server_settings_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Whether the health record section is unlocked for this session.
  /// Resets when the user leaves and returns to this screen.
  bool _healthUnlocked = false;

  // ── Biometric unlock for health section ───────────────────────────────────

  Future<void> _unlockHealth() async {
    final biometric = ref.read(biometricServiceProvider);
    final available = await biometric.isAvailable();

    if (!available) {
      // No biometrics on this device — unlock directly.
      if (mounted) setState(() => _healthUnlocked = true);
      return;
    }

    final passed = await biometric.authenticate(
      reason: 'Unlock your health record',
    );
    if (passed && mounted) {
      setState(() => _healthUnlocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull?.user;
    final profile = ref.watch(profileControllerProvider);
    final dash = ref.watch(dashboardStateProvider);
    final personal = profile.personal;

    final name = personal.fullName.isNotEmpty
        ? personal.fullName
        : (user?.displayName.isNotEmpty == true
            ? user!.displayName
            : 'Your profile');
    final phone = personal.phone.isNotEmpty
        ? personal.phone
        : (user?.phone ?? 'Add your phone number');

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            AppSpacing.xxxl,
          ),
          physics: const BouncingScrollPhysics(),
          children: [
            // ── Header ─────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Profile',
                    style: AppTypography.headlineMd
                        .copyWith(color: AppColors.textPrimary),
                  ),
                ),
                _IconChip(
                  icon: Icons.qr_code_rounded,
                  onTap: () => showInfoSheet(
                    context,
                    icon: Icons.qr_code_rounded,
                    title: 'Patient QR',
                    body:
                        'In an emergency, a clinician can scan this QR to access your allergies, conditions and emergency contacts. Coming in the next update.',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _IconChip(
                  icon: Icons.notifications_none_rounded,
                  onTap: () => openNotificationsSheet(context, ref),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Hero card ──────────────────────────────────────────────
            _HeroCard(
              name: name,
              phone: phone,
              onEdit: () => openEditProfileSheet(context, ref),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Stats row ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Scans',
                    value: '${dash.scansCount}',
                    icon: Icons.center_focus_strong_rounded,
                    tint: AppColors.tintBlue,
                    fg: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatTile(
                    label: 'Reports',
                    value: '${dash.reportsCount}',
                    icon: Icons.description_rounded,
                    tint: AppColors.tintCyan,
                    fg: AppColors.accentCyan,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatTile(
                    label: 'Medicines',
                    value: '${dash.medicineCount}',
                    icon: Icons.medication_rounded,
                    tint: AppColors.tintGreen,
                    fg: AppColors.success,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Personal details ───────────────────────────────────────
            const _SectionLabel(label: 'Personal details'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: [
                _DetailRow(
                  icon: Icons.mail_outline_rounded,
                  tint: AppColors.tintBlue,
                  fg: AppColors.primary,
                  label: 'Email',
                  value: personal.email.isNotEmpty ? personal.email : null,
                ),
                const _Divider(),
                _DetailRow(
                  icon: Icons.cake_outlined,
                  tint: AppColors.tintViolet,
                  fg: AppColors.accentViolet,
                  label: 'Age',
                  value: personal.age != null ? '${personal.age} yrs' : null,
                ),
                const _Divider(),
                _DetailRow(
                  icon: Icons.wc_rounded,
                  tint: AppColors.tintCyan,
                  fg: AppColors.accentCyan,
                  label: 'Gender',
                  value: personal.gender.isNotEmpty ? personal.gender : null,
                ),
                const _Divider(),
                _DetailRow(
                  icon: Icons.bloodtype_outlined,
                  tint: AppColors.tintRed,
                  fg: AppColors.danger,
                  label: 'Blood group',
                  value: personal.bloodGroup.isNotEmpty
                      ? personal.bloodGroup
                      : null,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Health record — locked by default ──────────────────────
            Row(
              children: [
                const Expanded(child: _SectionLabel(label: 'Health record')),
                if (_healthUnlocked)
                  TextButton.icon(
                    icon: const Icon(Icons.lock_open_rounded, size: 14),
                    label: const Text('Lock'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textTertiary,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => setState(() => _healthUnlocked = false),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            if (!_healthUnlocked) ...[
              // Locked state — show unlock prompt.
              _LockedHealthCard(onUnlock: _unlockHealth),
            ] else ...[
              // Unlocked — show full health record.
              _SettingsCard(
                children: [
                  _TileRow(
                    icon: Icons.bloodtype_rounded,
                    tint: AppColors.tintRed,
                    fg: AppColors.danger,
                    label: 'Allergies',
                    trailing: _summary(profile.allergies, 'None'),
                    onTap: () => openAllergiesSheet(context, ref),
                  ),
                  const _Divider(),
                  _TileRow(
                    icon: Icons.monitor_heart_rounded,
                    tint: AppColors.tintBlue,
                    fg: AppColors.primary,
                    label: 'Conditions',
                    trailing: _summary(profile.conditions, 'None'),
                    onTap: () => openConditionsSheet(context, ref),
                  ),
                  const _Divider(),
                  _TileRow(
                    icon: Icons.medication_rounded,
                    tint: AppColors.tintGreen,
                    fg: AppColors.success,
                    label: 'Active medicines',
                    trailing: _summary(
                      profile.currentMedicines,
                      '${dash.medicineCount}',
                    ),
                    onTap: () => showInfoSheet(
                      context,
                      icon: Icons.medication_rounded,
                      title: 'Active medicines',
                      body: _medicinesSummary(ref, profile),
                    ),
                  ),
                  const _Divider(),
                  _TileRow(
                    icon: Icons.contact_emergency_rounded,
                    tint: AppColors.tintAmber,
                    fg: AppColors.warning,
                    label: 'Emergency contacts',
                    trailing: '${profile.emergencyContacts.length}',
                    onTap: () => openEmergencyContactsSheet(context, ref),
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            // ── Preferences ────────────────────────────────────────────
            const _SectionLabel(label: 'Preferences'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: [
                _BiometricToggleTile(
                  value: profile.biometricEnabled,
                ),
                const _Divider(),
                _TileRow(
                  icon: Icons.language_rounded,
                  tint: AppColors.tintViolet,
                  fg: AppColors.accentViolet,
                  label: 'Language',
                  trailing: profile.language.label,
                  onTap: () => openLanguageSheet(context, ref),
                ),
                const _Divider(),
                _TileRow(
                  icon: Icons.notifications_active_rounded,
                  tint: AppColors.tintCyan,
                  fg: AppColors.accentCyan,
                  label: 'Notifications',
                  trailing: profile.notifications.label,
                  onTap: () => openNotificationsSheet(context, ref),
                ),
                const _Divider(),
                _TileRow(
                  icon: Icons.privacy_tip_rounded,
                  tint: AppColors.tintAmber,
                  fg: AppColors.warning,
                  label: 'Privacy & data',
                  onTap: () => showInfoSheet(
                    context,
                    icon: Icons.privacy_tip_rounded,
                    title: 'Privacy & data',
                    body:
                        'Your prescriptions and reports are encrypted at rest and in transit. AI analysis runs server-side and is never sold or used to train external models. You can request export or deletion at any time.',
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Connection ─────────────────────────────────────────────
            // The backend runs on a laptop whose address changes with the
            // network. Editable here so a new address is a ten-second fix
            // rather than a rebuild.
            const _SectionLabel(label: 'Connection'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final baseUrl = ref.watch(serverConfigProvider);
                    return _TileRow(
                      icon: Icons.dns_rounded,
                      tint: AppColors.tintSky,
                      fg: AppColors.info,
                      label: 'Server address',
                      trailing:
                          baseUrl.replaceFirst(RegExp(r'^https?://'), ''),
                      onTap: () => showServerSettingsSheet(context),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── About ──────────────────────────────────────────────────
            const _SectionLabel(label: 'About'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: [
                _TileRow(
                  icon: Icons.help_outline_rounded,
                  tint: AppColors.tintBlue,
                  fg: AppColors.primary,
                  label: 'Help & support',
                  onTap: () => showInfoSheet(
                    context,
                    icon: Icons.help_outline_rounded,
                    title: 'Help & support',
                    body:
                        'Need help? Email support@medintelnexus.app or visit medintelnexus.app/help — typical response time is 24 hours.',
                  ),
                ),
                const _Divider(),
                _TileRow(
                  icon: Icons.description_outlined,
                  tint: AppColors.tintBlue,
                  fg: AppColors.primary,
                  label: 'Terms & privacy',
                  onTap: () => showInfoSheet(
                    context,
                    icon: Icons.description_outlined,
                    title: 'Terms & privacy',
                    body:
                        'MedIntel Nexus is an AI-assisted clinical intelligence platform, not a replacement for a doctor. Use of the app is governed by our Terms of Service and Privacy Policy at medintelnexus.app/legal.',
                  ),
                ),
                const _Divider(),
                _TileRow(
                  icon: Icons.info_outline_rounded,
                  tint: AppColors.tintBlue,
                  fg: AppColors.primary,
                  label: 'App version',
                  trailing: '1.0.0',
                  onTap: () => showInfoSheet(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'MedIntel Nexus · v1.0.0',
                    body:
                        'Build 1 · Patient client. AI-Powered Clinical Intelligence & Prescription Risk Analysis Platform.',
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            _SignOutButton(
              onTap: () => ref.read(authControllerProvider.notifier).signOut(),
            ),

            const SizedBox(height: AppSpacing.lg),
            Center(
              child: Text(
                'MedIntel Nexus · Patient',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(List<String> items, String emptyLabel) {
    if (items.isEmpty) return emptyLabel;
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} · ${items[1]}';
    return '${items[0]} · ${items[1]} · +${items.length - 2}';
  }

  String _medicinesSummary(WidgetRef ref, ProfileRecord profile) {
    // Show health-profile medicines first.
    final healthMeds = profile.currentMedicines;
    if (healthMeds.isNotEmpty) return healthMeds.join(' · ');

    // Fall back to scanned prescriptions.
    final scans = ref.read(scansControllerProvider);
    final names = <String>[
      for (final s in scans)
        for (final m in s.medicines)
          '${m.name}${m.strength.isEmpty ? '' : ' ${m.strength}'}',
    ];
    if (names.isEmpty) {
      return 'No medicines recorded yet. Scan a prescription or set up your health profile.';
    }
    return names.join(' · ');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Locked health card
// ─────────────────────────────────────────────────────────────────────────────

class _LockedHealthCard extends StatelessWidget {
  const _LockedHealthCard({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.tintBlue,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Health record is protected',
            style: AppTypography.titleMd
                .copyWith(color: AppColors.textPrimary, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your allergies, conditions, medicines and emergency contacts are hidden by default. '
            'Unlock with biometrics or device PIN to view.',
            style:
                AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Unlock health record',
            icon: Icons.fingerprint_rounded,
            onPressed: onUnlock,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Biometric toggle tile — real authentication gate
// ─────────────────────────────────────────────────────────────────────────────

/// A settings tile that gates the biometric-unlock preference behind a real
/// biometric / device-credential prompt.
///
/// The switch stays at its **current stored value** while authentication is
/// in-flight (no premature visual toggle). It only flips to the new value
/// once the platform confirms the prompt succeeded. On failure it stays at
/// the old value and a SnackBar explains why.
class _BiometricToggleTile extends ConsumerStatefulWidget {
  const _BiometricToggleTile({required this.value});

  final bool value;

  @override
  ConsumerState<_BiometricToggleTile> createState() =>
      _BiometricToggleTileState();
}

class _BiometricToggleTileState extends ConsumerState<_BiometricToggleTile> {
  /// True while the biometric prompt / setBiometric call is running.
  bool _loading = false;

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final error = await ref
          .read(profileControllerProvider.notifier)
          .setBiometric(!widget.value);

      if (!mounted) return;

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _loading ? null : _toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.tintBlue,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(
                Icons.fingerprint_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Labels
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Biometric unlock',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Fingerprint or Face ID',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Trailing: spinner while auth is in-flight, switch otherwise
            if (_loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              )
            else
              Switch.adaptive(
                // Reflect the authoritative stored value — never optimistically
                // toggle before auth completes.
                value: widget.value,
                // Null disables the switch's own tap; the InkWell handles it
                // so the whole row is tappable.
                onChanged: (_) => _toggle(),
                activeThumbColor: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.name,
    required this.phone,
    required this.onEdit,
  });
  final String name;
  final String phone;
  final VoidCallback onEdit;

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        // Near-black rather than the brand gradient. A single dark block is
        // what gives a settings screen a centre of gravity — a full-bleed
        // gradient competes with the tinted rows below it and reads busy.
        color: AppColors.heroDark,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.heroDark.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Circular, with a brand-gradient ring — the one place on the
              // screen the brand colour appears at full strength.
              Container(
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.heroDark,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _initials,
                    style: AppTypography.headlineMd
                        .copyWith(color: Colors.white, fontSize: 21),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headlineMd.copyWith(
                        color: Colors.white,
                        fontSize: 21,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      phone,
                      style: AppTypography.bodyMd.copyWith(
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Patient account',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _OutlineActionButton(
                  icon: Icons.edit_rounded,
                  label: 'Edit profile',
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _OutlineActionButton(
                  icon: Icons.share_rounded,
                  label: 'Care Circle',
                  onTap: () => context.go(Routes.careCircle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.labelMd
                  .copyWith(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.fg,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      // Centred, circular medallion — the same language as the dashboard's
      // quick actions, so the two screens read as one product.
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 19),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: AppTypography.headlineMd.copyWith(
              color: AppColors.textPrimary,
              fontSize: 24,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    // Sentence case at full weight, not tiny letter-spaced caps. Caps in a
    // pale tertiary grey is the single thing that made this screen read as
    // a settings dump rather than a designed page.
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        label,
        style: AppTypography.titleMd.copyWith(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        // Larger radius and a softer stroke than the old card: against the
        // grey canvas the border only needs to separate, not outline.
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(children: children),
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.icon,
    required this.tint,
    required this.fg,
    required this.label,
    required this.onTap,
    this.trailing,
  });
  final IconData icon;
  final Color tint;
  final Color fg;
  final String label;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          // Taller rows. The old 12px vertical made a 5-row card feel
          // cramped, which is most of what read as unpolished.
          vertical: 15,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, color: fg, size: 19),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) ...[
              Flexible(
                child: Text(
                  trailing!,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.tint,
    required this.fg,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color tint;
  final Color fg;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 15,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 19),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyLg.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              hasValue ? value! : 'Not set',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMd.copyWith(
                color:
                    hasValue ? AppColors.textSecondary : AppColors.textTertiary,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(height: 1, thickness: 1, color: AppColors.outlineSoft),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.tintRed,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AppColors.danger,
                size: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Sign out',
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.danger,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outline),
          boxShadow: AppShadows.card,
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 18),
      ),
    );
  }
}
