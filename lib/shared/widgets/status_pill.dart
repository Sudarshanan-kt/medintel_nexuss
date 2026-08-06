import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Semantic tone for a [StatusPill].
enum PillTone { neutral, info, processing, success, warning, danger }

/// A compact status chip — used for scan pipeline state, AI status, etc.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = PillTone.neutral,
    this.showDot = true,
  });

  final String label;
  final PillTone tone;
  final bool showDot;

  ({Color fg, Color bg}) _colors() {
    switch (tone) {
      case PillTone.info:
        return (fg: AppColors.primary, bg: AppColors.tintBlue);
      case PillTone.processing:
        return (fg: AppColors.primaryDeep, bg: AppColors.tintBlue);
      case PillTone.success:
        return (fg: AppColors.success, bg: AppColors.tintGreen);
      case PillTone.warning:
        return (fg: AppColors.warning, bg: AppColors.tintAmber);
      case PillTone.danger:
        return (fg: AppColors.danger, bg: AppColors.tintRed);
      case PillTone.neutral:
        return (fg: AppColors.textSecondary, bg: AppColors.surfaceMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: c.fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
