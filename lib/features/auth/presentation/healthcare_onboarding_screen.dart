import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/application/profile_controller.dart';
import '../../profile/data/health_profile_repository.dart';
import '../../profile/domain/profile_record.dart';

/// 5-step Health Profile Setup wizard shown after first login.
///
/// Steps:
///   1 — Identity (name, gender, date of birth)
///   2 — Body metrics (blood group, height, weight)
///   3 — Allergies
///   4 — Conditions & current medicines
///   5 — Emergency contacts
///
/// On completion:
///   • Upserts the `health_profiles` Supabase table row (RLS-protected).
///   • Seeds the local ProfileController so the Profile page is immediately
///     populated without another round-trip.
///   • Calls [AuthController.completeOnboarding] → flips onboarding flag →
///     router sends the user to /home.
class HealthcareOnboardingScreen extends ConsumerStatefulWidget {
  const HealthcareOnboardingScreen({super.key});

  @override
  ConsumerState<HealthcareOnboardingScreen> createState() =>
      _HealthcareOnboardingScreenState();
}

class _HealthcareOnboardingScreenState
    extends ConsumerState<HealthcareOnboardingScreen> {
  int _step = 0;

  static const _stepTitles = [
    'Your identity',
    'Body metrics',
    'Allergies',
    'Conditions & medicines',
    'Emergency contacts',
  ];

  static const _stepDescriptions = [
    'Help us personalise your experience and power AI insights.',
    'Used to compute dosage safety ranges and adherence scores.',
    'Fuel your interaction and allergy alerts.',
    'These conditions and medicines shape your risk reports.',
    'Shown to clinicians in an emergency scan.',
  ];

  // Step 1 — Identity
  final _name = TextEditingController();
  DateTime? _dob;
  String _gender = '';

  // Step 2 — Body metrics
  final _heightCm = TextEditingController();
  final _weightKg = TextEditingController();
  String _bloodGroup = '';

  // Step 3 — Allergies
  final _allergies = <String>{};

  // Step 4 — Conditions & medicines
  final _conditions = <String>{};
  final _medicines = <String>[];

  // Step 5 — Emergency contacts
  final _contacts = <EmergencyContact>[];

  // ── options ──────────────────────────────────────────────────────────────

  static const _genderOptions = [
    'Male',
    'Female',
    'Non-binary',
    'Prefer not to say',
  ];
  static const _bloodGroupOptions = [
    'A+',
    'A−',
    'B+',
    'B−',
    'AB+',
    'AB−',
    'O+',
    'O−',
    'Unknown',
  ];
  static const _allergyOptions = [
    'Penicillin',
    'Sulfa drugs',
    'Aspirin',
    'NSAIDs',
    'Latex',
    'Peanuts',
    'Tree nuts',
    'Eggs',
    'Milk',
    'Shellfish',
    'Iodine',
  ];
  static const _conditionOptions = [
    'Diabetes (Type 1)',
    'Diabetes (Type 2)',
    'Hypertension',
    'Asthma',
    'Heart disease',
    'Kidney disease',
    'Thyroid disorder',
    'Epilepsy',
    'COPD',
    'Arthritis',
    'Depression / Anxiety',
  ];

  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    // Pre-fill name from auth session if available.
    final user = ref.read(authControllerProvider).valueOrNull?.user;
    if (user?.fullName != null && user!.fullName!.isNotEmpty) {
      _name.text = user.fullName!;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _heightCm.dispose();
    _weightKg.dispose();
    super.dispose();
  }

  // ── navigation ────────────────────────────────────────────────────────────

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _name.text.trim().length >= 2;
      default:
        return true;
    }
  }

  Future<void> _next() async {
    if (_step < _stepTitles.length - 1) {
      setState(() => _step++);
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    final user = ref.read(authControllerProvider).valueOrNull?.user;
    if (user == null) {
      setState(() {
        _saving = false;
        _saveError = 'Session expired. Please sign in again.';
      });
      return;
    }

    // Build domain objects from collected data.
    final personal = PersonalDetails(
      fullName: _name.text.trim(),
      email: user.email ?? '',
      phone: user.phone ?? '',
      gender: _gender,
      bloodGroup: _bloodGroup,
      dateOfBirth: _dob,
      heightCm: _heightCm.text.trim(),
      weightKg: _weightKg.text.trim(),
    );

    try {
      // 1) Save to Supabase (if table exists).
      final repo = ref.read(healthProfileRepositoryProvider);
      await repo.saveHealthProfile(
        userId: user.id,
        personal: personal,
        allergies: _allergies.toList(),
        conditions: _conditions.toList(),
        currentMedicines: _medicines,
        emergencyContacts: _contacts,
      );

      // 2) Seed ProfileController (local secure storage — instant UI).
      final profileNotifier = ref.read(profileControllerProvider.notifier);
      await profileNotifier.savePersonalDetails(personal);
      await profileNotifier.setAllergies(_allergies.toList());
      await profileNotifier.setConditions(_conditions.toList());
      await profileNotifier.setCurrentMedicines(_medicines);
      for (final c in _contacts) {
        await profileNotifier.addEmergencyContact(c);
      }

      // 3) Flip auth onboarding flag → router sends to /home.
      await ref.read(authControllerProvider.notifier).completeOnboarding({
        'fullName': _name.text.trim(),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not finish setup. Check your connection and try again.';
      });
      return;
    }

    // If we're still mounted here, completeOnboarding ran but the router
    // never navigated us away — the auth status still resolved to
    // "onboarding" (e.g. the health profile couldn't be found remotely).
    // Surface that instead of leaving the button spinning forever.
    if (mounted) {
      setState(() {
        _saving = false;
        _saveError = 'Setup saved, but we could not confirm it. Please try again.';
      });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        leading: _step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _saving ? null : () => setState(() => _step--),
              ),
        title: Text('Step ${_step + 1} of ${_stepTitles.length}'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress bar.
            Row(
              children: List.generate(_stepTitles.length, (i) {
                final filled = i <= _step;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: EdgeInsets.only(
                      right: i == _stepTitles.length - 1 ? 0 : 6,
                    ),
                    height: 6,
                    decoration: BoxDecoration(
                      color: filled ? AppColors.primary : AppColors.outline,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.xl),

            Text(
              _stepTitles[_step],
              style: AppTypography.headlineMd
                  .copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _stepDescriptions[_step],
              style:
                  AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),

            if (_saveError != null) ...[
              _ErrorBanner(message: _saveError!),
              const SizedBox(height: AppSpacing.lg),
            ],

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _stepBody(),
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label:
                  _step == _stepTitles.length - 1 ? 'Finish setup' : 'Continue',
              icon: _step == _stepTitles.length - 1
                  ? Icons.check_circle_rounded
                  : Icons.arrow_forward_rounded,
              isLoading: _saving,
              onPressed: (_canContinue && !_saving) ? _next : null,
            ),
            if (_step < _stepTitles.length - 1) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: _saving ? null : _next,
                  child: Text(
                    'Skip for now',
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _StepIdentity(
          name: _name,
          gender: _gender,
          dob: _dob,
          genderOptions: _genderOptions,
          onGenderChanged: (g) => setState(() => _gender = g),
          onDobChanged: (d) => setState(() => _dob = d),
          onNameChanged: () => setState(() {}),
        );
      case 1:
        return _StepBodyMetrics(
          heightCm: _heightCm,
          weightKg: _weightKg,
          bloodGroup: _bloodGroup,
          bloodGroupOptions: _bloodGroupOptions,
          onBloodGroupChanged: (bg) => setState(() => _bloodGroup = bg),
        );
      case 2:
        return _StepChipSelector(
          sectionTitle: 'Known allergies',
          options: _allergyOptions,
          selected: _allergies,
          onChanged: (s) => setState(() {
            _allergies
              ..clear()
              ..addAll(s);
          }),
        );
      case 3:
        return _StepConditionsAndMedicines(
          conditionOptions: _conditionOptions,
          selectedConditions: _conditions,
          medicines: _medicines,
          onConditionsChanged: (s) => setState(() {
            _conditions
              ..clear()
              ..addAll(s);
          }),
          onMedicinesChanged: (m) => setState(() {
            _medicines
              ..clear()
              ..addAll(m);
          }),
        );
      case 4:
        return _StepEmergencyContacts(
          contacts: _contacts,
          onChanged: (c) => setState(() {
            _contacts
              ..clear()
              ..addAll(c);
          }),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step bodies
// ─────────────────────────────────────────────────────────────────────────────

class _StepIdentity extends StatelessWidget {
  const _StepIdentity({
    required this.name,
    required this.gender,
    required this.dob,
    required this.genderOptions,
    required this.onGenderChanged,
    required this.onDobChanged,
    required this.onNameChanged,
  });

  final TextEditingController name;
  final String gender;
  final DateTime? dob;
  final List<String> genderOptions;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<DateTime?> onDobChanged;
  final VoidCallback onNameChanged;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'SELECT DATE OF BIRTH',
    );
    if (picked != null) onDobChanged(picked);
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')} / '
      '${d.month.toString().padLeft(2, '0')} / '
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: name,
          label: 'Full name',
          hint: 'e.g. Dr. Aravind Kumar',
          prefixIcon: Icons.person_outline_rounded,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onNameChanged(),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Gender',
          style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _OptionChips(
          options: genderOptions,
          selected: gender,
          onSelected: onGenderChanged,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Date of birth',
          style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PickerTile(
          icon: Icons.cake_outlined,
          label: dob != null ? _formatDate(dob!) : 'Select date',
          hint: dob == null,
          onTap: () => _pickDate(context),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _StepBodyMetrics extends StatelessWidget {
  const _StepBodyMetrics({
    required this.heightCm,
    required this.weightKg,
    required this.bloodGroup,
    required this.bloodGroupOptions,
    required this.onBloodGroupChanged,
  });

  final TextEditingController heightCm;
  final TextEditingController weightKg;
  final String bloodGroup;
  final List<String> bloodGroupOptions;
  final ValueChanged<String> onBloodGroupChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Blood group',
          style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _OptionChips(
          options: bloodGroupOptions,
          selected: bloodGroup,
          onSelected: onBloodGroupChanged,
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: heightCm,
                label: 'Height (cm)',
                hint: '172',
                prefixIcon: Icons.height_rounded,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: AppTextField(
                controller: weightKg,
                label: 'Weight (kg)',
                hint: '68',
                prefixIcon: Icons.monitor_weight_outlined,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _StepChipSelector extends StatefulWidget {
  const _StepChipSelector({
    required this.sectionTitle,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String sectionTitle;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_StepChipSelector> createState() => _StepChipSelectorState();
}

class _StepChipSelectorState extends State<_StepChipSelector> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _addCustom(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    final next = Set<String>.from(widget.selected)..add(v);
    widget.onChanged(next);
    _custom.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.sectionTitle,
          style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MultiChips(
          options: widget.options,
          selected: widget.selected,
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Add custom',
          style: AppTypography.labelMd
              .copyWith(color: AppColors.textPrimary, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _custom,
                textCapitalization: TextCapitalization.words,
                onSubmitted: _addCustom,
                textInputAction: TextInputAction.done,
                style:
                    AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Type and press add…',
                  hintStyle: AppTypography.bodyMd
                      .copyWith(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
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
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: () => _addCustom(_custom.text),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _StepConditionsAndMedicines extends StatefulWidget {
  const _StepConditionsAndMedicines({
    required this.conditionOptions,
    required this.selectedConditions,
    required this.medicines,
    required this.onConditionsChanged,
    required this.onMedicinesChanged,
  });

  final List<String> conditionOptions;
  final Set<String> selectedConditions;
  final List<String> medicines;
  final ValueChanged<Set<String>> onConditionsChanged;
  final ValueChanged<List<String>> onMedicinesChanged;

  @override
  State<_StepConditionsAndMedicines> createState() =>
      _StepConditionsAndMedicinesState();
}

class _StepConditionsAndMedicinesState
    extends State<_StepConditionsAndMedicines> {
  final _medCtrl = TextEditingController();

  @override
  void dispose() {
    _medCtrl.dispose();
    super.dispose();
  }

  void _addMedicine(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    if (widget.medicines.any((m) => m.toLowerCase() == v.toLowerCase())) return;
    widget.onMedicinesChanged([...widget.medicines, v]);
    _medCtrl.clear();
  }

  void _removeMedicine(String m) {
    widget.onMedicinesChanged(
      widget.medicines.where((x) => x != m).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Medical conditions',
          style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MultiChips(
          options: widget.conditionOptions,
          selected: widget.selectedConditions,
          onChanged: widget.onConditionsChanged,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Current medicines',
          style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'List medicines you take regularly (name + dose, e.g. Metformin 500mg).',
          style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.medicines.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: widget.medicines
                .map(
                  (m) => _RemovableChip(
                    label: m,
                    onRemove: () => _removeMedicine(m),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _medCtrl,
                textCapitalization: TextCapitalization.words,
                onSubmitted: _addMedicine,
                textInputAction: TextInputAction.done,
                style:
                    AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. Metformin 500mg',
                  hintStyle: AppTypography.bodyMd
                      .copyWith(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
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
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: () => _addMedicine(_medCtrl.text),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _StepEmergencyContacts extends StatefulWidget {
  const _StepEmergencyContacts({
    required this.contacts,
    required this.onChanged,
  });

  final List<EmergencyContact> contacts;
  final ValueChanged<List<EmergencyContact>> onChanged;

  @override
  State<_StepEmergencyContacts> createState() => _StepEmergencyContactsState();
}

class _StepEmergencyContactsState extends State<_StepEmergencyContacts> {
  final _nameCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _relationCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final n = _nameCtrl.text.trim();
    final r = _relationCtrl.text.trim();
    final p = _phoneCtrl.text.trim();
    if (n.isEmpty || p.isEmpty) return;
    final c = EmergencyContact(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: n,
      relation: r.isNotEmpty ? r : 'Contact',
      phone: p,
    );
    widget.onChanged([...widget.contacts, c]);
    _nameCtrl.clear();
    _relationCtrl.clear();
    _phoneCtrl.clear();
  }

  void _remove(String id) {
    widget.onChanged(widget.contacts.where((c) => c.id != id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.contacts.isEmpty)
          Text(
            'No contacts added yet.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.textTertiary),
          )
        else
          ...widget.contacts.map(
            (c) => _ContactRow(
              contact: c,
              onRemove: () => _remove(c.id),
            ),
          ),
        if (widget.contacts.length < 3) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Add contact',
            style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _nameCtrl,
            label: 'Name',
            hint: 'e.g. Priya Kumar',
            prefixIcon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _relationCtrl,
            label: 'Relation',
            hint: 'e.g. Spouse, Parent',
            prefixIcon: Icons.people_outline_rounded,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _phoneCtrl,
            label: 'Phone',
            hint: '+91 98765 43210',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'Add contact',
            icon: Icons.person_add_rounded,
            onPressed: _add,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI primitives for the wizard
// ─────────────────────────────────────────────────────────────────────────────

/// Single-select chip row.
class _OptionChips extends StatelessWidget {
  const _OptionChips({
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
      children: options.map((o) {
        final isSel = o == selected;
        return GestureDetector(
          onTap: () => onSelected(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isSel ? AppColors.primary : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: isSel ? AppColors.primary : AppColors.outline,
              ),
            ),
            child: Text(
              o,
              style: AppTypography.labelMd.copyWith(
                color: isSel ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Multi-select chip grid.
class _MultiChips extends StatelessWidget {
  const _MultiChips({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: options.map((o) {
        final isSel = selected.contains(o);
        return GestureDetector(
          onTap: () {
            final next = Set<String>.from(selected);
            isSel ? next.remove(o) : next.add(o);
            onChanged(next);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isSel ? AppColors.primary : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: isSel ? AppColors.primary : AppColors.outline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSel) ...[
                  const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  o,
                  style: AppTypography.labelMd.copyWith(
                    color: isSel ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Removable tag chip.
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
        color: AppColors.tintBlue,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelMd.copyWith(color: AppColors.primary),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable date / selection tile.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool hint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyLg.copyWith(
                  color: hint ? AppColors.textTertiary : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Contact display row with remove button.
class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onRemove});
  final EmergencyContact contact;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.tintBlue,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.contact_emergency_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: AppTypography.labelMd
                      .copyWith(color: AppColors.textPrimary),
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
              Icons.delete_outline_rounded,
              color: AppColors.danger,
              size: 18,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMd.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
