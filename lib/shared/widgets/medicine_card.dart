import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'app_card.dart';
import 'risk_badge.dart';

/// Structured medicine card — the payoff surface of the scan flow. Shows the
/// drug name + strength, the parsed dosage line, and an interaction/allergy
/// badge. Risk-flagged cards get an amber/red accent rail.
///
/// Primitive-typed by design: the `scan` feature maps its `Medicine` domain
/// entity onto these props, keeping this a pure design-system widget.
class MedicineCard extends StatelessWidget {
  const MedicineCard({
    super.key,
    required this.name,
    required this.dosageLine,
    required this.riskLevel,
    this.riskNote,
    this.uncertainFieldLabels = const [],
    this.riskLocked = false,
    this.interactionsChecked = true,
    this.onTap,
  });

  /// e.g. "Amoxicillin 500 mg"
  final String name;

  /// Parsed dosage line, e.g. "1 cap · 3×/day · 7 days"
  final String dosageLine;

  final RiskLevel riskLevel;

  /// Plain-language explanation shown when there is a risk.
  final String? riskNote;

  /// Names of the fields the OCR wasn't confident it read correctly (e.g.
  /// `['Name', 'Strength']`). The card names them rather than showing a
  /// generic warning, so the patient knows exactly what to look at.
  final List<String> uncertainFieldLabels;

  /// True while the interaction check is being withheld pending
  /// confirmation — the badge is replaced by an explicit "not checked yet"
  /// marker, because an absent risk badge would otherwise read as "safe".
  final bool riskLocked;

  /// False when the interaction database doesn't contain this drug, so no
  /// check was possible. Suppresses the risk badge for the same reason
  /// [riskLocked] does: [RiskLevel.none] renders as a green tick reading
  /// "No interaction", which would be an all-clear nobody gave.
  final bool interactionsChecked;

  final VoidCallback? onTap;

  Color? get _rail => switch (riskLevel) {
        RiskLevel.none => null,
        RiskLevel.moderate => AppColors.warning,
        RiskLevel.severe => AppColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      accentRail: _rail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.tintBlue,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.medication_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.bodyLg.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dosageLine,
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (riskLocked)
                const _RiskLockedChip()
              else if (!interactionsChecked)
                const _NotInDatabaseChip()
              else
                RiskBadge(level: riskLevel),
              if (uncertainFieldLabels.isNotEmpty)
                _CheckFieldsChip(labels: uncertainFieldLabels),
            ],
          ),
          if (riskNote != null && riskLevel != RiskLevel.none) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: riskLevel == RiskLevel.severe
                    ? AppColors.tintRed
                    : AppColors.tintAmber,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                riskNote!,
                style: AppTypography.caption.copyWith(
                  color: riskLevel == RiskLevel.severe
                      ? AppColors.danger
                      : AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared shell for the two confidence-related chips, so they read as one
/// family next to [RiskBadge].
class _MarkerChip extends StatelessWidget {
  const _MarkerChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Names the fields the OCR is unsure about. Icon + text, never colour
/// alone — the same rule the risk states follow.
class _CheckFieldsChip extends StatelessWidget {
  const _CheckFieldsChip({required this.labels});
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return _MarkerChip(
      icon: Icons.edit_note_rounded,
      label: 'Check ${labels.join(' · ').toLowerCase()}',
      color: AppColors.warning,
      background: AppColors.tintAmber,
    );
  }
}

/// Stands in for the risk badge while the safety check is withheld. Without
/// it, a card with no badge would look like a card that came back clean.
class _RiskLockedChip extends StatelessWidget {
  const _RiskLockedChip();

  @override
  Widget build(BuildContext context) {
    return const _MarkerChip(
      icon: Icons.lock_clock_rounded,
      label: 'Safety check pending',
      color: AppColors.textSecondary,
      background: AppColors.surfaceMuted,
    );
  }
}

/// Stands in for the risk badge when the drug isn't in the interaction
/// database. Says the check didn't happen, rather than letting the absence
/// of a warning imply there was nothing to warn about.
class _NotInDatabaseChip extends StatelessWidget {
  const _NotInDatabaseChip();

  @override
  Widget build(BuildContext context) {
    return const _MarkerChip(
      icon: Icons.help_outline_rounded,
      label: 'Not in safety database',
      color: AppColors.warning,
      background: AppColors.tintAmber,
    );
  }
}
