import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../l10n/generated/app_localizations.dart';
import 'adherence_controller.dart';

/// Compact streak + 7-day adherence card. No charting dependency — a hand
/// rolled bar row, consistent with the app's other custom-painted widgets.
class AdherenceStreakCard extends StatelessWidget {
  const AdherenceStreakCard({super.key, required this.state, this.onTap});

  final AdherenceState state;
  final VoidCallback? onTap;

  Color get _percentColor {
    if (state.weeklyPercent < 0) return AppColors.textTertiary;
    if (state.weeklyPercent >= 80) return AppColors.success;
    if (state.weeklyPercent >= 50) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (!state.hasAnyData) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_fire_department_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.adherenceNoData,
                      style: AppTypography.bodyLg.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      t.adherenceNoDataHint,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: state.streakDays > 0
                        ? AppColors.tintAmber
                        : AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    color: state.streakDays > 0
                        ? const Color(0xFFF97316)
                        : AppColors.textSecondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.adherenceStreak(state.streakDays),
                        style: AppTypography.bodyLg.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        t.adherenceLabel,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (state.weeklyPercent >= 0)
                  Text(
                    '${state.weeklyPercent.round()}%',
                    style: AppTypography.headlineMd.copyWith(
                      color: _percentColor,
                      fontSize: 22,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                for (final day in state.last7Days)
                  Expanded(child: _DayBar(day: day)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day});
  final DayAdherence day;

  Color get _color {
    if (!day.hasData) return AppColors.outline;
    return day.isPerfect ? AppColors.success : AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(day.date, DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: _color,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            DateFormat.E().format(day.date).substring(0, 1),
            style: AppTypography.caption.copyWith(
              color: isToday ? AppColors.textPrimary : AppColors.textTertiary,
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
