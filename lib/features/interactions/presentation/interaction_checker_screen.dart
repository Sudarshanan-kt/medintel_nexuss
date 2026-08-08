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

/// Real drug-interaction checker.
///
/// Verdicts come from the backend's interaction database, never from a
/// language model — see `InteractionRepository`. The screen's main job
/// beyond listing results is making sure an empty list can't be read as an
/// all-clear: a check that didn't run, and a drug the database doesn't
/// know, both get said out loud.
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
              'Checked against a drug-interaction database. No database is '
              'complete, so a clear result does not prove a combination is '
              'safe — always confirm with a pharmacist or doctor.',
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
      // The repository already turns failures into checked:false, so
      // reaching here means something unforeseen — still never phrased as
      // an absence of interactions.
      error: (e, _) => const _CouldNotCheckCard(),
      data: (result) {
        if (!result.checked) return const _CouldNotCheckCard();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Results'),
            const SizedBox(height: AppSpacing.md),

            // Anything the database couldn't look up comes first: it
            // qualifies every other result on this screen.
            if (result.unrecognized.isNotEmpty) ...[
              _UnrecognizedCard(names: result.unrecognized),
              const SizedBox(height: AppSpacing.md),
            ],

            if (result.interactions.isEmpty)
              _NothingFoundCard(result: result)
            else
              for (final interaction in result.interactions) ...[
                _InteractionCard(interaction: interaction),
                const SizedBox(height: AppSpacing.md),
              ],

            if (result.ungradedPairCount > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              _FootNote(
                icon: Icons.info_outline_rounded,
                text: '${result.ungradedPairCount} other '
                    '${result.ungradedPairCount == 1 ? 'combination is' : 'combinations are'} '
                    'listed in the database without an established severity, '
                    'so they are not shown as warnings.',
              ),
            ],
            if (result.source != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _FootNote(
                icon: Icons.storage_rounded,
                text: 'Source: ${result.source}. ${result.disclaimer}',
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Shown when the check could not run. Says so plainly rather than
/// rendering an empty list, which would look like a clean result.
class _CouldNotCheckCard extends StatelessWidget {
  const _CouldNotCheckCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.tintRed.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Couldn\'t run the check',
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This is not a result — nothing was checked. Ask a '
                  'pharmacist or doctor before combining these medicines.',
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Names the drugs the database has never heard of.
///
/// Without this the screen would show "no interactions found" while having
/// silently skipped one of the medicines entirely.
class _UnrecognizedCard extends StatelessWidget {
  const _UnrecognizedCard({required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.tintAmber,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.help_outline_rounded,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  names.length == 1
                      ? 'Not in the database: ${names.single}'
                      : 'Not in the database: ${names.join(', ')}',
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  names.length == 1
                      ? 'Nothing below covers this medicine. Try its generic '
                          'name, or ask a pharmacist.'
                      : 'Nothing below covers these medicines. Try their '
                          'generic names, or ask a pharmacist.',
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The only place reassurance is offered — and only when the check actually
/// ran and every medicine was recognised.
class _NothingFoundCard extends StatelessWidget {
  const _NothingFoundCard({required this.result});
  final InteractionCheck result;

  @override
  Widget build(BuildContext context) {
    final clear = result.isClear;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: clear ? AppColors.tintGreen : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: clear
              ? AppColors.success.withValues(alpha: 0.35)
              : AppColors.outline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            clear ? Icons.check_circle_rounded : Icons.remove_circle_outline,
            color: clear ? AppColors.success : AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              clear
                  ? 'No known interactions between these medicines. The '
                      'database is not exhaustive — keep your pharmacist in '
                      'the loop.'
                  : 'No interactions found among the medicines that could be '
                      'looked up. That says nothing about the ones above.',
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractionCard extends StatelessWidget {
  const _InteractionCard({required this.interaction});
  final DrugInteraction interaction;

  @override
  Widget build(BuildContext context) {
    final severe = interaction.risk == RiskLevel.severe;
    final accent = severe ? AppColors.danger : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent, width: severe ? 1.5 : 1),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: accent, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  interaction.pairLabel,
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              RiskBadge(level: interaction.risk),
              const SizedBox(width: AppSpacing.sm),
              // The database's own grading, so "Minor" is never hidden
              // behind the amber badge it shares with "Moderate".
              Text(
                '${interaction.level} severity',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (interaction.mechanism.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              interaction.mechanism,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
          if (interaction.recommendation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: severe ? AppColors.tintRed : AppColors.tintAmber,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                interaction.recommendation,
                style: AppTypography.caption.copyWith(
                  color: accent,
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

class _FootNote extends StatelessWidget {
  const _FootNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
