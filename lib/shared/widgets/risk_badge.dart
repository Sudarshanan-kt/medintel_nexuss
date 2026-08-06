import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Severity of a detected clinical risk.
enum RiskLevel { none, moderate, severe }

/// Risk severity badge. Critically: risk is **never conveyed by colour
/// alone** — every level pairs a colour with an icon and a text label, for
/// accessibility and clinical clarity.
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.level});

  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final (color, tint, icon, label) = switch (level) {
      RiskLevel.none => (
          AppColors.success,
          AppColors.tintGreen,
          Icons.check_circle_rounded,
          'No interaction',
        ),
      RiskLevel.moderate => (
          AppColors.warning,
          AppColors.tintAmber,
          Icons.warning_amber_rounded,
          'Caution',
        ),
      RiskLevel.severe => (
          AppColors.danger,
          AppColors.tintRed,
          Icons.error_rounded,
          'Severe risk',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
