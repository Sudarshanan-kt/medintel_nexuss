import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/application/auth_controller.dart';
import '../application/care_task_controller.dart';
import '../domain/care_circle_models.dart';
import 'caregiver_theme.dart';

/// The care circle's task board for one patient.
///
/// Previously the dashboard rendered these as static rows: you could see
/// that "ride to appointment Tuesday" was outstanding and that nobody had
/// claimed it, and there was nothing you could do about either. The RLS
/// policies always allowed any active member of the circle to post, claim
/// and complete — this is the UI catching up with what the database already
/// permitted.
class CareTaskBoard extends ConsumerWidget {
  const CareTaskBoard({
    super.key,
    required this.patientId,
    required this.patientName,
    this.title = 'Care tasks',
  });

  final String patientId;
  final String patientName;

  /// Heading for the card. The dashboard stacks one board per patient under
  /// its own "Care tasks" section label, so there it passes the patient's
  /// name — otherwise every card repeats the word directly beneath it.
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(careTasksProvider(patientId));
    // Watched because which actions a row offers depends on who you are —
    // and because watching is what guarantees the provider is initialised
    // and that rows rebuild once it resolves.
    ref.watch(authControllerProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: kCardTitle)),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: kViolet,
                  minimumSize: const Size(0, kTapTarget),
                ),
                onPressed: () => showAddCareTaskSheet(
                  context,
                  ref,
                  patientId: patientId,
                  patientName: patientName,
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          tasks.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Loading tasks…', style: kBodyMuted),
            ),
            // Unlike the dashboard, this screen says so. There the task
            // fetch is one block among many and a silent skip is
            // reasonable; here the board is the point of the section.
            error: (_, __) => Row(
              children: [
                const Expanded(
                  child: Text(
                    "Couldn't load tasks.",
                    style: kBodyMuted,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: kViolet),
                  onPressed: () =>
                      ref.invalidate(careTasksProvider(patientId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
            data: (list) {
              final open = list.where((t) => !t.isDone).toList(growable: false);
              if (open.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Nothing outstanding.',
                    style: kBodyMuted,
                  ),
                );
              }
              return Column(
                children: [
                  for (final task in open)
                    CareTaskRow(task: task, patientId: patientId),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One task, with whatever action makes sense for its current state.
class CareTaskRow extends ConsumerStatefulWidget {
  const CareTaskRow({
    super.key,
    required this.task,
    required this.patientId,
  });

  final CareTask task;
  final String patientId;

  @override
  ConsumerState<CareTaskRow> createState() => _CareTaskRowState();
}

class _CareTaskRowState extends ConsumerState<CareTaskRow> {
  bool _busy = false;

  /// Runs [action], holding the row disabled until it settles.
  ///
  /// Two caregivers can be looking at the same board, so a claim can lose a
  /// race. The refetch that follows is what corrects this device's view —
  /// showing a claim that didn't land would be worse than a brief spinner.
  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final actions = ref.read(careTaskActionsProvider);
    final mine = actions.claimedByMe(task);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            task.isClaimed
                ? Icons.person_pin_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: task.isClaimed ? kViolet : kMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: kBody.copyWith(
                  fontWeight: FontWeight.w700,
                ),),
                if (task.dueDate != null || task.isClaimed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_subtitle(task, mine), style: kBodyMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(
              width: kTapTarget,
              height: 20,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (!task.isClaimed)
            _RowAction(
              label: 'Claim',
              onPressed: () => _run(
                () => actions.claim(task),
                "Couldn't claim that task.",
              ),
            )
          else if (mine)
            _RowAction(
              label: 'Done',
              filled: true,
              onPressed: () => _run(
                () => actions.complete(task),
                "Couldn't mark that done.",
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle(CareTask task, bool mine) {
    final parts = <String>[
      if (task.isClaimed) mine ? "You're on it" : '${task.claimedByName} is on it',
      if (task.dueDate != null) 'due ${DateFormat('E d MMM').format(task.dueDate!)}',
    ];
    return parts.join(' · ');
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size(72, kTapTarget - 8)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
    if (filled) {
      return FilledButton(
        style: FilledButton.styleFrom(backgroundColor: kViolet).merge(style),
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: kVioletDeep,
        side: const BorderSide(color: kCardStroke),
      ).merge(style),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add a task
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showAddCareTaskSheet(
  BuildContext context,
  WidgetRef ref, {
  required String patientId,
  required String patientName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AddCareTaskSheet(
      patientId: patientId,
      patientName: patientName,
    ),
  );
}

class _AddCareTaskSheet extends ConsumerStatefulWidget {
  const _AddCareTaskSheet({
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  ConsumerState<_AddCareTaskSheet> createState() => _AddCareTaskSheetState();
}

class _AddCareTaskSheetState extends ConsumerState<_AddCareTaskSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  DateTime? _due;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(careTaskActionsProvider).add(
            patientId: widget.patientId,
            title: _title.text,
            note: _note.text,
            dueDate: _due,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _due = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keeps the fields above the keyboard.
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ask the circle for help', style: kTitle),
          const SizedBox(height: 6),
          Text(
            'Everyone looking after ${widget.patientName} will see this and '
            'can claim it.',
            style: kBodyMuted,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: kBody,
            decoration: const InputDecoration(
              labelText: 'What needs doing',
              hintText: 'Ride to the clinic on Tuesday',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: kBody,
            decoration: const InputDecoration(
              labelText: 'Any details (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kVioletDeep,
                  minimumSize: const Size(0, kTapTarget),
                ),
                onPressed: _pickDue,
                icon: const Icon(Icons.event_rounded, size: 20),
                label: Text(
                  _due == null
                      ? 'Add a date'
                      : DateFormat('E d MMM').format(_due!),
                ),
              ),
              if (_due != null)
                TextButton(
                  onPressed: () => setState(() => _due = null),
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: kBodyMuted.copyWith(color: kRed)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kViolet,
                minimumSize: const Size(0, 52),
              ),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Posting…' : 'Post to the circle'),
            ),
          ),
        ],
      ),
    );
  }
}
