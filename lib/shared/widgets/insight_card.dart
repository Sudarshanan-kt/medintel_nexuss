import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'app_card.dart';

/// Tone of a healthcare insight card — drives the accent rail + icon tint.
enum InsightTone { neutral, positive, caution, alert }

/// A healthcare insight card for the dashboard feed: recent scans, medicine
/// adherence, risk alerts, AI recommendations. Kept primitive-typed so it
/// stays a pure design-system widget with no feature dependency.
class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tone = InsightTone.neutral,
    this.trailing,
    this.onTap,
    this.subtitleWidget,
  });

  final IconData icon;
  final String title;

  /// Always required, even when [subtitleWidget] overrides its display —
  /// keeps a plain-text fallback available (e.g. for accessibility tools)
  /// and means every existing call site is unaffected by this override.
  final String subtitle;
  final InsightTone tone;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Optional replacement for the subtitle's rendered [Text] widget — used
  /// where the subtitle needs to be asynchronous (e.g. an LLM-narrated
  /// rephrasing that starts out showing [subtitle] and may swap in a
  /// friendlier version once ready). Falls back to plain [subtitle] text
  /// when null.
  final Widget? subtitleWidget;

  ({Color rail, Color tint, Color fg}) _palette() {
    switch (tone) {
      case InsightTone.positive:
        return (
          rail: AppColors.success,
          tint: AppColors.tintGreen,
          fg: AppColors.success,
        );
      case InsightTone.caution:
        return (
          rail: AppColors.warning,
          tint: AppColors.tintAmber,
          fg: AppColors.warning,
        );
      case InsightTone.alert:
        return (
          rail: AppColors.danger,
          tint: AppColors.tintRed,
          fg: AppColors.danger,
        );
      case InsightTone.neutral:
        return (
          rail: AppColors.primary,
          tint: AppColors.tintBlue,
          fg: AppColors.primary,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = _palette();

    return AppCard(
      onTap: onTap,
      accentRail: p.rail,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.tint,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: p.fg, size: 22),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyLg.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                subtitleWidget ??
                    Text(
                      subtitle,
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.textSecondary),
                    ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ] else if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 22,
            ),
        ],
      ),
    );
  }
}
