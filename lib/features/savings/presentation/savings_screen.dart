import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/savings_controller.dart';
import '../domain/generic_swap.dart';

/// "Savings" — surfaces generic-equivalent estimates for scanned medicines,
/// the price-transparency differentiator. Never a specific price quote:
/// percentage bands only, always paired with a pharmacist-check disclaimer.
class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(savingsControllerProvider);
    final actionable = state.actionable;

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Generic Swap Savings'),
        actions: [
          IconButton(
            icon: state.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: state.loading
                ? null
                : () => ref.read(savingsControllerProvider.notifier).refresh(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.xxxl,
        ),
        physics: const BouncingScrollPhysics(),
        children: [
          Text(
            'See if switching to a generic could lower your medicine costs — '
            'estimates only, always confirm with your pharmacist.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.swaps.isEmpty && !state.loading)
            const EmptyState(
              icon: Icons.savings_rounded,
              title: 'No medicines to check yet',
              message:
                  'Scan a prescription or add a medicine to see generic-swap savings here.',
            )
          else if (state.swaps.isEmpty && state.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (actionable.isNotEmpty) ...[
              _SummaryCard(count: actionable.length),
              const SizedBox(height: AppSpacing.lg),
            ],
            for (final swap in state.swaps) ...[
              _SwapCard(swap: swap),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.tintGreen,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.savings_rounded, color: AppColors.success),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              count == 1
                  ? 'A generic swap is available for 1 medicine.'
                  : 'Generic swaps are available for $count medicines.',
              style: AppTypography.bodyLg.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapCard extends StatelessWidget {
  const _SwapCard({required this.swap});
  final GenericSwap swap;

  @override
  Widget build(BuildContext context) {
    final alreadyGeneric = swap.isAlreadyGeneric;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  swap.brandName,
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusPill(
                label: alreadyGeneric ? 'Already generic' : 'Save ${swap.savingsRangeLabel}',
                tone: alreadyGeneric ? PillTone.neutral : PillTone.success,
                showDot: false,
              ),
            ],
          ),
          if (!alreadyGeneric) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  swap.genericName,
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            swap.note,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
