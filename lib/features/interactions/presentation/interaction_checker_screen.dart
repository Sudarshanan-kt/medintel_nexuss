import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../reminders/reminders_controller.dart';
import '../../scan/application/scans_controller.dart';
import '../application/interaction_controller.dart';
import '../domain/drug_interaction_result.dart';

/// Real drug-interaction checker — replaces routing "Drug Interaction" to
/// the free-form AI assistant, which risked hallucinating a safety-critical
/// answer. Results here are text pulled from actual FDA drug labels (see
/// `InteractionRepository`), never generated.
class InteractionCheckerScreen extends ConsumerStatefulWidget {
  const InteractionCheckerScreen({super.key});

  @override
  ConsumerState<InteractionCheckerScreen> createState() =>
      _InteractionCheckerScreenState();
}

class _InteractionCheckerScreenState
    extends ConsumerState<InteractionCheckerScreen> {
  final Set<String> _selected = {};
  final _manualCtrl = TextEditingController();
  List<String>? _checkedNames;

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Set<String> get _knownMedicineNames {
    final scans = ref.watch(scansControllerProvider);
    final reminders = ref.watch(remindersControllerProvider);
    return {
      for (final scan in scans)
        for (final m in scan.medicines) m.name.trim(),
      for (final m in reminders.medicines) m.name.trim(),
    }..removeWhere((n) => n.isEmpty);
  }

  void _addManual() {
    final name = _manualCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _selected.add(name);
      _manualCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final known = _knownMedicineNames;

    return GradientScaffold(
      appBar: AppBar(title: const Text('Drug Interaction Checker')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.xxxl,
        ),
        physics: const BouncingScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.tintAmber.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.outline),
            ),
            child: Text(
              'Sourced from FDA drug label text, not a clinical interaction '
              'engine. A "no mention found" result does not mean a '
              'combination is safe — always confirm with a pharmacist or '
              'doctor.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Select medicines to check'),
          const SizedBox(height: AppSpacing.sm),
          if (known.isEmpty)
            Text(
              'No scanned or reminded medicines yet — add one manually below.',
              style:
                  AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final name in known)
                  FilterChip(
                    label: Text(name),
                    selected: _selected.contains(name),
                    onSelected: (v) => setState(() {
                      v ? _selected.add(name) : _selected.remove(name);
                    }),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _manualCtrl,
                  hint: 'Add another medicine by name',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: const Icon(
                  Icons.add_circle_rounded,
                  color: AppColors.primary,
                ),
                onPressed: _addManual,
              ),
            ],
          ),
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final name in _selected)
                  Chip(
                    label: Text(name),
                    onDeleted: () => setState(() => _selected.remove(name)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Check interactions',
            onPressed: _selected.length < 2
                ? null
                : () => setState(() => _checkedNames = _selected.toList()),
          ),
          if (_checkedNames != null) ...[
            const SizedBox(height: AppSpacing.xl),
            _ResultsSection(medicineNames: _checkedNames!),
          ],
        ],
      ),
    );
  }
}

class _ResultsSection extends ConsumerWidget {
  const _ResultsSection({required this.medicineNames});
  final List<String> medicineNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(interactionCheckProvider(medicineNames));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.tintRed.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Text(
          'Could not reach the drug label service. Check your connection '
          'and try again.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
      ),
      data: (results) {
        if (results.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Results'),
            const SizedBox(height: AppSpacing.md),
            for (final r in results) ...[
              _InteractionResultCard(result: r),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

class _InteractionResultCard extends StatelessWidget {
  const _InteractionResultCard({required this.result});
  final DrugInteractionResult result;

  @override
  Widget build(BuildContext context) {
    final flagged = result.found;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: flagged ? AppColors.danger : AppColors.outline,
          width: flagged ? 1.5 : 1,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                flagged
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
                color: flagged ? AppColors.danger : AppColors.success,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${result.medicineA} + ${result.medicineB}',
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            flagged
                ? 'Mentioned in ${result.mentionedIn}\'s FDA label:'
                : 'No mention found in either drug\'s FDA label interactions section.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (flagged && result.excerpt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              result.excerpt!,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
