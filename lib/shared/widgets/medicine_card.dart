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
    this.lowConfidence = false,
    this.onTap,
  });

  /// e.g. "Amoxicillin 500 mg"
  final String name;

  /// Parsed dosage line, e.g. "1 cap · 3×/day · 7 days"
  final String dosageLine;

  final RiskLevel riskLevel;

  /// Plain-language explanation shown when there is a risk.
  final String? riskNote;

  /// True when the OCR confidence for this medicine was below threshold —
  /// the card is visually marked and tappable to correct.
  final bool lowConfidence;

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
          Row(
            children: [
              RiskBadge(level: riskLevel),
              if (lowConfidence) ...[
                const SizedBox(width: AppSpacing.sm),
                _LowConfidenceChip(),
              ],
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

class _LowConfidenceChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.edit_rounded,
            size: 12,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            'Tap to verify',
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
