import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/scans_controller.dart';
import '../domain/medicine.dart';
import '../domain/prescription_scan.dart';

/// Real scan view — reads the scan the user just captured from the
/// scans controller, shows the image they took, and lets them add the
/// medicines they read off the prescription.
class ScanResultScreen extends ConsumerWidget {
  const ScanResultScreen({super.key, required this.scanId});
  final String scanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scans = ref.watch(scansControllerProvider);
    PrescriptionScan? scan;
    for (final s in scans) {
      if (s.id == scanId) {
        scan = s;
        break;
      }
    }

    if (scan == null) {
      return GradientScaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go(Routes.scan),
          ),
        ),
        body: EmptyState(
          icon: Icons.image_not_supported_rounded,
          title: 'Scan not found',
          message: 'This scan was removed or never saved.',
          actionLabel: 'Back to scanner',
          onAction: () => context.go(Routes.scan),
        ),
      );
    }

    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(Routes.home),
        ),
        title: const Text('Scan'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.danger,
            ),
            onPressed: () async {
              await _confirmDelete(context, ref);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          120,
        ),
        children: [
          _CaptureImage(path: scan.imageRef, capturedAt: scan.capturedAt),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              StatusPill(
                label: _statusLabel(scan),
                tone: _statusTone(scan),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (scan.status == ScanStatus.processing)
            const _AnalyzingState()
          else if (scan.status == ScanStatus.failed)
            _FailedState(
              message: scan.errorMessage,
              onRetry: () =>
                  ref.read(scansControllerProvider.notifier).runOcr(scanId),
              onManual: () => _openMedicineSheet(context, ref, null),
            )
          else if (scan.medicines.isEmpty)
            EmptyState(
              icon: Icons.medication_outlined,
              title: 'No medicines were read from this prescription',
              message:
                  'The scan finished but nothing was extracted. Add the medicines manually below.',
              actionLabel: 'Add medicine',
              onAction: () => _openMedicineSheet(context, ref, null),
            )
          else
            for (final m in scan.medicines) ...[
              MedicineCard(
                name: '${m.name}${m.strength.isEmpty ? '' : ' ${m.strength}'}',
                dosageLine: m.dosageLine,
                riskLevel: m.riskLevel,
                riskNote: m.riskNote,
                lowConfidence: m.isLowConfidence,
                onTap: () => _openMedicineSheet(context, ref, m),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          if (scan.status == ScanStatus.analyzed &&
              scan.medicines.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              icon: Icons.add_rounded,
              label: 'Add another medicine',
              onPressed: () => _openMedicineSheet(context, ref, null),
            ),
          ],
          if (scan.status != ScanStatus.processing) ...[
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              icon: Icons.check_rounded,
              label: 'Save to record',
              onPressed: () => context.go(Routes.home),
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(PrescriptionScan scan) => switch (scan.status) {
        ScanStatus.queued || ScanStatus.processing => 'Analyzing prescription…',
        ScanStatus.failed => scan.errorMessage ?? 'Scan failed',
        ScanStatus.analyzed => scan.medicines.isEmpty
            ? 'No medicines found'
            : '${scan.medicines.length} medicine'
                '${scan.medicines.length == 1 ? '' : 's'} found',
      };

  PillTone _statusTone(PrescriptionScan scan) => switch (scan.status) {
        ScanStatus.queued || ScanStatus.processing => PillTone.info,
        ScanStatus.failed => PillTone.danger,
        ScanStatus.analyzed =>
          scan.medicines.isEmpty ? PillTone.warning : PillTone.success,
      };

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this scan?'),
        content: const Text(
          'The captured image and any medicines you added will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(scansControllerProvider.notifier).deleteScan(scanId);
      if (context.mounted) context.go(Routes.home);
    }
  }

  Future<void> _openMedicineSheet(
    BuildContext context,
    WidgetRef ref,
    Medicine? existing,
  ) async {
    await showAppSheet<void>(
      context: context,
      builder: (_) => _MedicineEditSheet(scanId: scanId, existing: existing),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Captured image
// ─────────────────────────────────────────────────────────────────────────

class _CaptureImage extends StatelessWidget {
  const _CaptureImage({required this.path, this.capturedAt});
  final String path;
  final DateTime? capturedAt;

  @override
  Widget build(BuildContext context) {
    Widget body;
    final file = File(path);
    if (file.existsSync()) {
      body = Image.file(file, fit: BoxFit.cover);
    } else {
      body = Container(
        color: const Color(0xFF0B1220),
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_rounded, color: Colors.white24, size: 40),
            SizedBox(height: 8),
            Text(
              'Image unavailable',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            body,
            if (capturedAt != null)
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Captured · ${DateFormat.jm().format(capturedAt!)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Medicine editor sheet
// ─────────────────────────────────────────────────────────────────────────

class _MedicineEditSheet extends ConsumerStatefulWidget {
  const _MedicineEditSheet({required this.scanId, this.existing});
  final String scanId;
  final Medicine? existing;

  @override
  ConsumerState<_MedicineEditSheet> createState() => _MedicineEditSheetState();
}

class _MedicineEditSheetState extends ConsumerState<_MedicineEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _strength =
      TextEditingController(text: widget.existing?.strength ?? '');
  late final TextEditingController _dosage =
      TextEditingController(text: widget.existing?.dosageLine ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.riskNote ?? '');
  late RiskLevel _risk = widget.existing?.riskLevel ?? RiskLevel.none;

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _dosage.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final notifier = ref.read(scansControllerProvider.notifier);
    if (_isEdit) {
      notifier.updateMedicine(
        widget.scanId,
        widget.existing!.copyWith(
          name: _name.text.trim(),
          strength: _strength.text.trim(),
          dosageLine: _dosage.text.trim(),
          riskLevel: _risk,
          riskNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
        ),
      );
    } else {
      notifier.addMedicine(
        widget.scanId,
        Medicine(
          id: 'm_${DateTime.now().microsecondsSinceEpoch}',
          name: _name.text.trim(),
          strength: _strength.text.trim(),
          dosageLine: _dosage.text.trim(),
          riskLevel: _risk,
          riskNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _delete() {
    if (!_isEdit) return;
    ref
        .read(scansControllerProvider.notifier)
        .removeMedicine(widget.scanId, widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

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
                _isEdit ? 'Edit medicine' : 'Add medicine',
                style: AppTypography.titleMd
                    .copyWith(color: AppColors.textPrimary, fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text(
                'Type what the prescription says.',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _name,
                label: 'Name',
                hint: 'e.g. Amoxicillin',
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _strength,
                      label: 'Strength',
                      hint: '500 mg',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: AppTextField(
                      controller: _dosage,
                      label: 'Dosage',
                      hint: '1 cap · 3×/day · 7 days',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Risk level',
                style: AppTypography.labelMd
                    .copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  for (final r in RiskLevel.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: _RiskChip(
                        level: r,
                        selected: _risk == r,
                        onTap: () => setState(() => _risk = r),
                      ),
                    ),
                ],
              ),
              if (_risk != RiskLevel.none) ...[
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _note,
                  label: 'Risk note (optional)',
                  hint: 'e.g. Avoid with blood thinners',
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: _isEdit ? 'Save changes' : 'Add to scan',
                icon: Icons.check_rounded,
                onPressed: _save,
              ),
              if (_isEdit) ...[
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                      size: 18,
                    ),
                    label: Text(
                      'Remove from scan',
                      style: AppTypography.labelMd
                          .copyWith(color: AppColors.danger),
                    ),
                    onPressed: _delete,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskChip extends StatelessWidget {
  const _RiskChip({
    required this.level,
    required this.selected,
    required this.onTap,
  });
  final RiskLevel level;
  final bool selected;
  final VoidCallback onTap;

  String get _label => switch (level) {
        RiskLevel.none => 'No risk',
        RiskLevel.moderate => 'Caution',
        RiskLevel.severe => 'Severe',
      };

  Color get _color => switch (level) {
        RiskLevel.none => AppColors.success,
        RiskLevel.moderate => AppColors.warning,
        RiskLevel.severe => AppColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected ? _color : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? _color : AppColors.outline),
        ),
        child: Text(
          _label,
          style: AppTypography.labelMd.copyWith(
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// OCR pipeline states
// ─────────────────────────────────────────────────────────────────────────

/// Shown while the async OCR worker is reading the prescription.
class _AnalyzingState extends StatelessWidget {
  const _AnalyzingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Reading your prescription',
            style: AppTypography.titleMd.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Extracting medicines with OCR. This usually takes a few seconds.',
            textAlign: TextAlign.center,
            style:
                AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Shown when the OCR pipeline failed; offers retry or manual entry.
class _FailedState extends StatelessWidget {
  const _FailedState({
    required this.onRetry,
    required this.onManual,
    this.message,
  });

  final VoidCallback onRetry;
  final VoidCallback onManual;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Couldn\'t read this prescription',
          message: message ??
              'Something went wrong while analyzing the image. Try again or add the medicines manually.',
          actionLabel: 'Try again',
          onAction: onRetry,
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          icon: Icons.edit_outlined,
          label: 'Enter medicines manually',
          onPressed: onManual,
        ),
      ],
    );
  }
}
