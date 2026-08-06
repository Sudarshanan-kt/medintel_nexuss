import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/profile_controller.dart';
import '../domain/profile_record.dart';

// ─────────────────────────────────────────────────────────────────────────
// Reusable bottom-sheet shell
// ─────────────────────────────────────────────────────────────────────────

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: AppTypography.titleMd
                    .copyWith(color: AppColors.textPrimary, fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Editable chips list (allergies + conditions)
// ─────────────────────────────────────────────────────────────────────────

class _ChipsEditor extends StatefulWidget {
  const _ChipsEditor({
    required this.initial,
    required this.suggestions,
    required this.onSaved,
  });
  final List<String> initial;
  final List<String> suggestions;
  final Future<void> Function(List<String>) onSaved;

  @override
  State<_ChipsEditor> createState() => _ChipsEditorState();
}

class _ChipsEditorState extends State<_ChipsEditor> {
  late final List<String> _items = [...widget.initial];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    if (_items.any((e) => e.toLowerCase() == v.toLowerCase())) return;
    setState(() => _items.add(v));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final unused = widget.suggestions
        .where((s) => !_items.any((i) => i.toLowerCase() == s.toLowerCase()))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_items.isEmpty)
          Text(
            'Nothing yet — add an item below.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.textTertiary),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final i in _items)
                _RemovableChip(
                  label: i,
                  onRemove: () => setState(() => _items.remove(i)),
                ),
            ],
          ),
        if (unused.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Suggestions',
            style: AppTypography.labelMd
                .copyWith(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in unused)
                _SuggestionChip(label: s, onAdd: () => _add(s)),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _controller,
          onSubmitted: _add,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Add custom item…',
            filled: true,
            fillColor: AppColors.surfaceMuted,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _add(_controller.text),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Save',
          icon: Icons.check_rounded,
          onPressed: () async {
            await widget.onSaved(_items);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelMd.copyWith(color: Colors.white),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onAdd});
  final String label;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style:
                  AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.add_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Edit profile (personal + medical identity)
// ─────────────────────────────────────────────────────────────────────────

const _genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];
const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

Future<void> openEditProfileSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(profileControllerProvider).personal;
  await showAppSheet<void>(
    context: context,
    builder: (_) => _SheetShell(
      title: 'Edit profile',
      subtitle: 'Keep your details current — they power your alerts.',
      child: _EditProfileForm(initial: current),
    ),
  );
}

class _EditProfileForm extends ConsumerStatefulWidget {
  const _EditProfileForm({required this.initial});
  final PersonalDetails initial;

  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initial.fullName);
  late final TextEditingController _phone =
      TextEditingController(text: widget.initial.phone);
  late final TextEditingController _email =
      TextEditingController(text: widget.initial.email);
  late final TextEditingController _height =
      TextEditingController(text: widget.initial.heightCm);
  late final TextEditingController _weight =
      TextEditingController(text: widget.initial.weightKg);

  late DateTime? _dob = widget.initial.dateOfBirth;
  late String _gender = widget.initial.gender;
  late String _bloodGroup = widget.initial.bloodGroup;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final next = widget.initial.copyWith(
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      dateOfBirth: _dob,
      clearDateOfBirth: _dob == null,
      gender: _gender,
      bloodGroup: _bloodGroup,
      heightCm: _height.text.trim(),
      weightKg: _weight.text.trim(),
    );
    await ref
        .read(profileControllerProvider.notifier)
        .savePersonalDetails(next);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dobLabel = _dob == null
        ? 'Select date of birth'
        : DateFormat('d MMM yyyy').format(_dob!);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'Full name',
            hint: 'e.g. Aravind Kumar',
            textInputAction: TextInputAction.next,
            validator: (v) => Validators.required(v, 'Full name'),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _phone,
            label: 'Phone number',
            hint: '+91 …',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: Validators.phone,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _email,
            label: 'Email',
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            // Optional, but if present it must be valid.
            validator: (v) =>
                (v ?? '').trim().isEmpty ? null : Validators.email(v),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _height,
                  label: 'Height (cm)',
                  hint: '172',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppTextField(
                  controller: _weight,
                  label: 'Weight (kg)',
                  hint: '68',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _FieldLabel('Date of birth'),
          const SizedBox(height: AppSpacing.sm),
          _PickerField(
            icon: Icons.cake_outlined,
            label: dobLabel,
            isPlaceholder: _dob == null,
            onTap: _pickDob,
          ),
          const SizedBox(height: AppSpacing.md),
          const _FieldLabel('Gender'),
          const SizedBox(height: AppSpacing.sm),
          _ChoiceWrap(
            options: _genderOptions,
            selected: _gender,
            onSelected: (v) => setState(() => _gender = v == _gender ? '' : v),
          ),
          const SizedBox(height: AppSpacing.md),
          const _FieldLabel('Blood group'),
          const SizedBox(height: AppSpacing.sm),
          _ChoiceWrap(
            options: _bloodGroups,
            selected: _bloodGroup,
            onSelected: (v) =>
                setState(() => _bloodGroup = v == _bloodGroup ? '' : v),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save changes',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.isPlaceholder,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isPlaceholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyLg.copyWith(
                  color: isPlaceholder
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceWrap extends StatelessWidget {
  const _ChoiceWrap({
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final o in options)
          GestureDetector(
            onTap: () => onSelected(o),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color:
                    o == selected ? AppColors.primary : AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: o == selected ? AppColors.primary : AppColors.outline,
                ),
              ),
              child: Text(
                o,
                style: AppTypography.labelMd.copyWith(
                  color: o == selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Public entry points
// ─────────────────────────────────────────────────────────────────────────

Future<void> openAllergiesSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(profileControllerProvider).allergies;
  await showAppSheet<void>(
    context: context,
    builder: (_) => _SheetShell(
      title: 'Allergies',
      subtitle: 'These power your medication risk alerts.',
      child: _ChipsEditor(
        initial: current,
        suggestions: const [
          'Penicillin',
          'Sulfa',
          'Aspirin',
          'Latex',
          'Peanuts',
          'Eggs',
          'Shellfish',
          'Dust',
        ],
        onSaved: (next) =>
            ref.read(profileControllerProvider.notifier).setAllergies(next),
      ),
    ),
  );
}

Future<void> openConditionsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(profileControllerProvider).conditions;
  await showAppSheet<void>(
    context: context,
    builder: (_) => _SheetShell(
      title: 'Conditions',
      subtitle: 'Chronic conditions help us flag risky prescriptions.',
      child: _ChipsEditor(
        initial: current,
        suggestions: const [
          'Diabetes',
          'Hypertension',
          'Asthma',
          'Heart disease',
          'Kidney disease',
          'Thyroid',
          'Anxiety',
        ],
        onSaved: (next) =>
            ref.read(profileControllerProvider.notifier).setConditions(next),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Emergency contacts manager
// ─────────────────────────────────────────────────────────────────────────

Future<void> openEmergencyContactsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  await showAppSheet<void>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (_, sheetRef, __) {
        final contacts =
            sheetRef.watch(profileControllerProvider).emergencyContacts;
        return _SheetShell(
          title: 'Emergency contacts',
          subtitle: 'We can show these on your lock screen in an emergency.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (contacts.isEmpty)
                Text(
                  'No contacts yet.',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.textTertiary),
                )
              else
                for (final c in contacts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _ContactRow(
                      contact: c,
                      onEdit: () => _openContactEditor(
                        sheetContext,
                        sheetRef,
                        c,
                      ),
                      onDelete: () => sheetRef
                          .read(profileControllerProvider.notifier)
                          .removeEmergencyContact(c.id),
                    ),
                  ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: 'Add contact',
                icon: Icons.add_rounded,
                onPressed: () =>
                    _openContactEditor(sheetContext, sheetRef, null),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _openContactEditor(
  BuildContext context,
  WidgetRef ref,
  EmergencyContact? existing,
) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  final relC = TextEditingController(text: existing?.relation ?? '');
  final phoneC = TextEditingController(text: existing?.phone ?? '');

  await showAppSheet<void>(
    context: context,
    builder: (_) => _SheetShell(
      title: existing == null ? 'Add contact' : 'Edit contact',
      subtitle: 'Tap save when you\'re done.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: nameC,
            label: 'Name',
            hint: 'e.g. Lakshmi Kumar',
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: relC,
            label: 'Relation',
            hint: 'Spouse, parent, GP…',
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: phoneC,
            label: 'Phone',
            hint: '+91 …',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save contact',
            icon: Icons.check_rounded,
            onPressed: () async {
              if (nameC.text.trim().isEmpty || phoneC.text.trim().isEmpty) {
                return;
              }
              final notifier = ref.read(profileControllerProvider.notifier);
              if (existing == null) {
                await notifier.addEmergencyContact(
                  EmergencyContact(
                    id: 'c_${DateTime.now().microsecondsSinceEpoch}',
                    name: nameC.text.trim(),
                    relation:
                        relC.text.trim().isEmpty ? 'Contact' : relC.text.trim(),
                    phone: phoneC.text.trim(),
                  ),
                );
              } else {
                await notifier.updateEmergencyContact(
                  EmergencyContact(
                    id: existing.id,
                    name: nameC.text.trim(),
                    relation:
                        relC.text.trim().isEmpty ? 'Contact' : relC.text.trim(),
                    phone: phoneC.text.trim(),
                  ),
                );
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    ),
  );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });
  final EmergencyContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.tintBlue,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${contact.relation} · ${contact.phone}',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.edit_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: AppColors.danger,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Single-choice picker (language + notifications)
// ─────────────────────────────────────────────────────────────────────────

Future<void> openLanguageSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(profileControllerProvider).language;
  await showAppSheet<void>(
    context: context,
    builder: (_) => _SheetShell(
      title: 'Language',
      subtitle: 'Changes the app language, the assistant, and report translations.',
      child: Column(
        children: [
          for (final l in AppLanguage.values)
            _RadioRow(
              label: l.label,
              selected: l == current,
              onTap: () async {
                await ref
                    .read(profileControllerProvider.notifier)
                    .setLanguage(l);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> openNotificationsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(profileControllerProvider).notifications;
  await showAppSheet<void>(
    context: context,
    builder: (_) => _SheetShell(
      title: 'Notifications',
      subtitle: 'How chatty MedIntel should be.',
      child: Column(
        children: [
          for (final n in NotificationLevel.values)
            _RadioRow(
              label: n.label,
              selected: n == current,
              onTap: () async {
                await ref
                    .read(profileControllerProvider.notifier)
                    .setNotifications(n);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    ),
  );
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.tintBlue : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outline,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyLg.copyWith(
                  color:
                      selected ? AppColors.primaryDeep : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Info dialog (privacy / help / terms / version)
// ─────────────────────────────────────────────────────────────────────────

Future<void> showInfoSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
}) async {
  await showAppSheet<void>(
    context: context,
    builder: (_) => _SheetShell(
      title: title,
      subtitle: 'About MedIntel Nexus',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.tintBlue,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    body,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Got it',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
}
