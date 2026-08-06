import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../reminders/adherence_streak_card.dart';
import '../application/care_circle_controller.dart';
import '../application/care_task_controller.dart';
import '../data/care_task_repository.dart';
import '../domain/care_circle_models.dart';

class CareCircleScreen extends ConsumerStatefulWidget {
  const CareCircleScreen({super.key, this.caregiverMode = false});

  /// When true, this renders as a caregiver-only account's dashboard
  /// (reached directly at login, with no bottom-tab shell around it) rather
  /// than a patient's "Care Circle" tab: the "People caring for me" /
  /// "Invite a caregiver" sections are hidden — a pure caregiver account has
  /// no health profile of its own to invite anyone into — and the app bar
  /// gains a sign-out action since there's no profile tab to reach one from.
  final bool caregiverMode;

  @override
  ConsumerState<CareCircleScreen> createState() => _CareCircleScreenState();
}

class _CareCircleScreenState extends ConsumerState<CareCircleScreen> {
  final _codeCtrl = TextEditingController();
  bool _joining = false;
  bool _inviting = false;

  String? get _selfId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppColors.danger : AppColors.primaryDeep,
        content: Text(msg, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<void> _invite() async {
    setState(() => _inviting = true);
    try {
      final code =
          await ref.read(careCircleControllerProvider.notifier).createInvite();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _InviteCodeDialog(code: code),
      );
    } catch (_) {
      _showMessage('Could not create an invite. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _joining = true);
    try {
      await ref.read(careCircleControllerProvider.notifier).acceptInvite(code);
      if (!mounted) return;
      _codeCtrl.clear();
      _showMessage("You're now following this patient's adherence.");
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(careCircleControllerProvider);

    return GradientScaffold(
      appBar: AppBar(
        title: Text(widget.caregiverMode ? 'My Patients' : 'Care Circle'),
        actions: widget.caregiverMode
            ? [
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: 'Sign out',
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
              ]
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(careCircleControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            AppSpacing.xxxl,
          ),
          physics: const BouncingScrollPhysics(),
          children: [
            if (!widget.caregiverMode) ...[
              Text(
                'People caring for me',
                style: AppTypography.titleMd
                    .copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'They can see your medicine adherence — never your full health profile.',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.myCaregivers.isEmpty)
                const _EmptyRow(text: 'No one added yet.')
              else
                for (final c in state.myCaregivers)
                  _CaregiverRow(
                    member: c,
                    onRemove: () => ref
                        .read(careCircleControllerProvider.notifier)
                        .removeCaregiver(c.id),
                  ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Invite a caregiver',
                icon: Icons.person_add_alt_1_rounded,
                isLoading: _inviting,
                onPressed: _invite,
              ),
              if (_selfId != null) ...[
                const SizedBox(height: AppSpacing.xl),
                _TaskBoardSection(patientId: _selfId!, patientLabel: 'you'),
              ],
              const SizedBox(height: AppSpacing.xxl),
            ],
            Text(
              'People I care for',
              style:
                  AppTypography.titleMd.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            if (state.loading && state.linkedPatients.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state.linkedPatients.isEmpty)
              const _EmptyRow(text: "You're not linked to anyone yet.")
            else
              for (final p in state.linkedPatients) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    p.member.patientDisplayName,
                    style: AppTypography.bodyLg.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AdherenceStreakCard(state: p.adherence),
                const SizedBox(height: AppSpacing.md),
                _TaskBoardSection(
                  patientId: p.member.patientId,
                  patientLabel: p.member.patientDisplayName,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'Have an invite code?',
              style:
                  AppTypography.titleMd.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _codeCtrl,
              label: 'Invite code',
              hint: 'e.g. AB3F9Q',
              prefixIcon: Icons.link_rounded,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Join circle',
              icon: Icons.group_add_rounded,
              isLoading: _joining,
              onPressed: _join,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.tintBlue.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(
        text,
        style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _CaregiverRow extends StatelessWidget {
  const _CaregiverRow({required this.member, required this.onRemove});
  final CareCircleMember member;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.tintViolet,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: AppColors.accentViolet,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              member.caregiverDisplayName,
              style: AppTypography.bodyLg.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppColors.danger, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _InviteCodeDialog extends StatelessWidget {
  const _InviteCodeDialog({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: const Text('Invite code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share this code with your caregiver. It expires in 7 days.',
            style:
                AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.tintBlue,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              code,
              style: AppTypography.displayLg.copyWith(
                color: AppColors.primaryDeep,
                letterSpacing: 4,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')),
            );
          },
          child: const Text('Copy'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Care task board — Lotsa Helping Hands' model: concrete, claimable asks
// shared across the circle rather than one person carrying every request.
// ─────────────────────────────────────────────────────────────────────────

class _TaskBoardSection extends ConsumerWidget {
  const _TaskBoardSection(
      {required this.patientId, required this.patientLabel});
  final String patientId;
  final String patientLabel;

  String get _selfId => Supabase.instance.client.auth.currentUser?.id ?? '';

  String _selfName(WidgetRef ref) =>
      ref.read(authControllerProvider).valueOrNull?.user?.displayName ??
      'Someone';

  Future<void> _openAddDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String title, String? note})>(
      context: context,
      builder: (_) => const _AddTaskDialog(),
    );
    if (result == null || result.title.trim().isEmpty) return;
    await ref.read(careTaskRepositoryProvider).createTask(
          patientId: patientId,
          title: result.title.trim(),
          note: result.note,
          createdById: _selfId,
          createdByName: _selfName(ref),
        );
    ref.invalidate(careTasksProvider(patientId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(careTasksProvider(patientId));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.tintGreen.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Care tasks',
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openAddDialog(context, ref),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'Could not load tasks.',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            data: (tasks) {
              if (tasks.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    'No open requests for $patientLabel.',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                );
              }
              return Column(
                children: [
                  for (final task in tasks)
                    _TaskRow(
                      task: task,
                      selfId: _selfId,
                      onClaim: () async {
                        await ref.read(careTaskRepositoryProvider).claimTask(
                              taskId: task.id,
                              claimedById: _selfId,
                              claimedByName: _selfName(ref),
                            );
                        ref.invalidate(careTasksProvider(patientId));
                      },
                      onUnclaim: () async {
                        await ref
                            .read(careTaskRepositoryProvider)
                            .unclaimTask(task.id);
                        ref.invalidate(careTasksProvider(patientId));
                      },
                      onComplete: () async {
                        await ref
                            .read(careTaskRepositoryProvider)
                            .completeTask(task.id);
                        ref.invalidate(careTasksProvider(patientId));
                      },
                      onDelete: () async {
                        await ref
                            .read(careTaskRepositoryProvider)
                            .deleteTask(task.id);
                        ref.invalidate(careTasksProvider(patientId));
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.selfId,
    required this.onClaim,
    required this.onUnclaim,
    required this.onComplete,
    required this.onDelete,
  });

  final CareTask task;
  final String selfId;
  final VoidCallback onClaim;
  final VoidCallback onUnclaim;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final canDelete = task.createdById == selfId;
    final claimedBySelf = task.claimedById == selfId;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            task.isDone
                ? Icons.check_circle_rounded
                : task.isClaimed
                    ? Icons.person_pin_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: task.isDone
                ? AppColors.success
                : task.isClaimed
                    ? AppColors.primary
                    : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.textPrimary,
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  task.isDone
                      ? 'Done · claimed by ${task.claimedByName ?? '—'}'
                      : task.isClaimed
                          ? 'Claimed by ${task.claimedByName ?? '—'}'
                          : 'Posted by ${task.createdByName}',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (!task.isDone && task.isOpen)
            TextButton(onPressed: onClaim, child: const Text('Claim')),
          if (!task.isDone && task.isClaimed && claimedBySelf) ...[
            TextButton(onPressed: onComplete, child: const Text('Done')),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              onPressed: onUnclaim,
              tooltip: 'Unclaim',
            ),
          ],
          if (canDelete)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: AppColors.danger,
              ),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog();

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final _titleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: const Text('Post a request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _titleCtrl,
            label: 'What do you need?',
            hint: 'e.g. Ride to clinic Tuesday',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(controller: _noteCtrl, label: 'Details (optional)'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final note = _noteCtrl.text.trim();
            final result =
                (title: _titleCtrl.text, note: note.isEmpty ? null : note);
            Navigator.of(context).pop(result);
          },
          child: const Text('Post'),
        ),
      ],
    );
  }
}
