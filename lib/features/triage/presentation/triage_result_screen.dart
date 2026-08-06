import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/triage_controller.dart';
import '../domain/triage_models.dart';

/// Adaptive symptom-triage flow — Ada Health / Buoy Health's pattern of a
/// short Q&A that narrows to an urgency level, distinct from the free-form
/// AI assistant chat. Never diagnoses: every screen this can end on shows
/// urgency + next-step guidance only, never a condition name.
class TriageScreen extends ConsumerWidget {
  const TriageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(triageControllerProvider);

    return GradientScaffold(
      appBar: AppBar(title: const Text('Symptom Check')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.xxxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.tintBlue.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.outline),
              ),
              child: Text(
                "This isn't a diagnosis — it only estimates how urgently to "
                'seek care. In a medical emergency, call emergency services '
                'immediately.',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Expanded(
              child: switch (state.current) {
                null => const Center(child: CircularProgressIndicator()),
                final TriageQuestion q when state.loading == false =>
                  _QuestionView(question: q),
                final TriageResult r =>
                  _ResultView(result: r, hadError: state.error),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionView extends ConsumerWidget {
  const _QuestionView({required this.question});
  final TriageQuestion question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(triageControllerProvider).loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.question,
          style:
              AppTypography.headlineMd.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final option in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SecondaryButton(
              label: option,
              onPressed: loading
                  ? null
                  : () => ref
                      .read(triageControllerProvider.notifier)
                      .answer(option),
            ),
          ),
        if (loading) ...[
          const SizedBox(height: AppSpacing.md),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.result, required this.hadError});
  final TriageResult result;
  final bool hadError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: result.urgency.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: result.urgency.color, width: 1.5),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      result.urgency == TriageUrgency.emergency
                          ? Icons.emergency_rounded
                          : Icons.health_and_safety_rounded,
                      color: result.urgency.color,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        result.urgency.label,
                        style: AppTypography.titleMd.copyWith(
                          color: result.urgency.color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  result.summary,
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          if (hadError) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              "We couldn't fully complete the assessment — treat this as a "
              'cautious default, not a full result.',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (result.urgency == TriageUrgency.emergency)
            PrimaryButton(
              label: 'Open Emergency SOS',
              icon: Icons.call_rounded,
              onPressed: () => context.push(Routes.sos),
            ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Start over',
            icon: Icons.refresh_rounded,
            onPressed: () =>
                ref.read(triageControllerProvider.notifier).restart(),
          ),
        ],
      ),
    );
  }
}
