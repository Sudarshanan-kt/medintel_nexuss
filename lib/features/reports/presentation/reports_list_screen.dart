import 'dart:io' show File;
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/reports_controller.dart';
import '../domain/medical_report.dart';

class ReportsListScreen extends ConsumerStatefulWidget {
  const ReportsListScreen({super.key});

  @override
  ConsumerState<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends ConsumerState<ReportsListScreen> {
  String _searchQuery = '';
  ReportType? _typeFilter;
  bool _searchVisible = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<MedicalReport> _filtered(List<MedicalReport> all) {
    var list = all;
    if (_typeFilter != null) {
      list = list.where((r) => r.type == _typeFilter).toList();
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((r) => r.title.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Future<void> _showUploadSheet(BuildContext context) async {
    await showAppSheet<void>(
      context: context,
      builder: (sheetContext) => _UploadSheet(
        onPicked: (source, type) async {
          Navigator.of(sheetContext).pop();
          await _pickAndUpload(context, source: source, type: type);
        },
        onPickedPdf: (type) async {
          Navigator.of(sheetContext).pop();
          await _pickAndUploadPdf(context, type: type);
        },
      ),
    );
  }

  Future<void> _pickAndUploadPdf(
    BuildContext context, {
    required ReportType type,
  }) async {
    try {
      // `withData: true` guarantees `bytes` is populated on web (where there
      // is no filesystem path). On mobile/desktop a `path` is also returned.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !context.mounted) return;

      final picked = result.files.single;

      // Resolve the PDF bytes + a usable file reference per-platform.
      //  • Web: `path` is unavailable (throws). Use `bytes`; the fileRef is
      //    just the file name (the viewer shows a PDF placeholder anyway).
      //  • Mobile/desktop: keep the real filesystem path; read bytes from it
      //    if the picker didn't already load them.
      Uint8List? bytes = picked.bytes;
      String? fileRef;

      if (kIsWeb) {
        if (bytes == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read the selected PDF.')),
          );
          return;
        }
        fileRef = picked.name;
      } else {
        final path = picked.path;
        if (path == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read the selected PDF.')),
          );
          return;
        }
        fileRef = path;
        try {
          bytes ??= await File(path).readAsBytes();
        } catch (_) {}
      }

      // SHA256 of the PDF bytes for re-upload recognition.
      String? fileSha256;
      if (bytes != null) {
        try {
          fileSha256 = sha256.convert(bytes).toString();
        } catch (_) {}
      }

      dev.log(
        'PDF upload kIsWeb=$kIsWeb name=${picked.name} '
        'bytes=${bytes?.length} sha256=${fileSha256?.substring(0, 8)}…',
        name: 'reports.upload',
      );

      // Real analysis. This used to call addAnalyzedDemo(), which built a
      // fully "analyzed" report synchronously from a random generator —
      // so uploading any PDF produced invented LDL, HbA1c, glucose and TSH
      // figures presented as the patient's own results. A patient can act
      // on numbers like those, so the upload now goes through OCR and the
      // report shows what was actually read, or says it couldn't read it.
      ref.read(reportsControllerProvider.notifier).addUpload(
            title: picked.name,
            type: ReportType.lab,
            fileRef: fileRef,
            fileName: picked.name,
            sha256: fileSha256,
          );

      if (!context.mounted) return;
      context.go(Routes.reports);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Could not pick PDF: $e'),
        ),
      );
    }
  }

  Future<void> _pickAndUpload(
    BuildContext context, {
    required ImageSource source,
    required ReportType type,
  }) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 85);
      if (file == null || !context.mounted) return;

      // Compute SHA256 of the raw image bytes so the same file is always
      // recognised on re-upload, regardless of filename changes.
      String? fileSha256;
      try {
        final bytes = await file.readAsBytes();
        fileSha256 = sha256.convert(bytes).toString();
      } catch (_) {}

      ref.read(reportsControllerProvider.notifier).addUpload(
            title: _suggestedTitle(type),
            type: type,
            fileRef: file.path,
            fileName: file.name,
            sha256: fileSha256,
          );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryDeep,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          margin: const EdgeInsets.all(AppSpacing.lg),
          content: Text(
            'Report uploaded — AI analysis starting',
            style: AppTypography.labelMd.copyWith(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Could not pick file: $e'),
        ),
      );
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, String title) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete report?'),
        content: Text('"$title" will be removed from your records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    MedicalReport report,
  ) async {
    final ctrl = TextEditingController(text: report.title);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename report'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Report name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      ref
          .read(reportsControllerProvider.notifier)
          .rename(report.id, ctrl.text.trim());
    }
    ctrl.dispose();
  }

  String _suggestedTitle(ReportType type) {
    final today = DateFormat.yMMMd().format(DateTime.now());
    return switch (type) {
      ReportType.lab => 'Lab report · $today',
      ReportType.imaging => 'Imaging · $today',
      ReportType.discharge => 'Discharge summary · $today',
      ReportType.prescription => 'Prescription · $today',
    };
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportsControllerProvider);
    final filtered = _filtered(reports);

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart_rounded),
            tooltip: 'Lab trends',
            onPressed: () => context.push(Routes.biomarkerTrends),
          ),
          IconButton(
            icon: Icon(
              _searchVisible ? Icons.search_off_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchQuery = '';
                  _searchCtrl.clear();
                }
              });
            },
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadSheet(context),
        icon: const Icon(Icons.upload_rounded),
        label: const Text('Upload report'),
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────────────
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                0,
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search reports…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() {
                            _searchQuery = '';
                            _searchCtrl.clear();
                          }),
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),

          // ── Type filter chips ─────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _typeFilter == null,
                  onTap: () => setState(() => _typeFilter = null),
                ),
                const SizedBox(width: AppSpacing.sm),
                for (final t in ReportType.values) ...[
                  _FilterChip(
                    label: switch (t) {
                      ReportType.lab => 'Lab Reports',
                      ReportType.imaging => 'Scans',
                      ReportType.discharge => 'Discharge Summaries',
                      ReportType.prescription => 'Prescriptions',
                    },
                    selected: _typeFilter == t,
                    onTap: () => setState(
                      () => _typeFilter = _typeFilter == t ? null : t,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),

          // ── List ──────────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.description_outlined,
                    title: reports.isEmpty ? 'No reports yet' : 'No matches',
                    message: reports.isEmpty
                        ? 'Upload a lab, imaging or discharge report and the AI will summarise it.'
                        : 'Try a different search term or filter.',
                    actionLabel:
                        reports.isEmpty ? 'Upload report' : null,
                    onAction: reports.isEmpty
                        ? () => _showUploadSheet(context)
                        : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.md,
                      AppSpacing.gutter,
                      120,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (_, i) {
                      final report = filtered[i];
                      return Dismissible(
                        key: ValueKey(report.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) =>
                            _confirmDelete(context, report.title),
                        onDismissed: (_) {
                          ref
                              .read(reportsControllerProvider.notifier)
                              .delete(report.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Report deleted')),
                          );
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding:
                              const EdgeInsets.only(right: AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        child: GestureDetector(
                          onLongPress: () async {
                            final action = await showModalBottomSheet<
                                _ListAction>(
                              context: context,
                              builder: (_) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(
                                        Icons.edit_outlined,
                                      ),
                                      title: const Text('Rename'),
                                      onTap: () => Navigator.pop(
                                        context,
                                        _ListAction.rename,
                                      ),
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: AppColors.danger,
                                      ),
                                      title: const Text(
                                        'Delete',
                                        style: TextStyle(
                                          color: AppColors.danger,
                                        ),
                                      ),
                                      onTap: () => Navigator.pop(
                                        context,
                                        _ListAction.delete,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            );
                            if (!context.mounted) return;
                            if (action == _ListAction.rename) {
                              await _showRenameDialog(context, report);
                            } else if (action == _ListAction.delete) {
                              final ok = await _confirmDelete(
                                context,
                                report.title,
                              );
                              if (ok == true && context.mounted) {
                                ref
                                    .read(reportsControllerProvider.notifier)
                                    .delete(report.id);
                              }
                            }
                          },
                          child: _ReportRow(
                            report: report,
                            onTap: () =>
                                context.go(Routes.reportById(report.id)),
                            onDelete: () async {
                              final ok = await _confirmDelete(
                                context,
                                report.title,
                              );
                              if (ok == true) {
                                ref
                                    .read(reportsControllerProvider.notifier)
                                    .delete(report.id);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _ListAction { rename, delete }

// ─── Filter chip ─────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outline,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelMd.copyWith(
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ─── Upload bottom sheet ────────────────────────────────────────────────


class _UploadSheet extends StatefulWidget {
  const _UploadSheet({required this.onPicked, required this.onPickedPdf});
  final void Function(ImageSource source, ReportType type) onPicked;
  final void Function(ReportType type) onPickedPdf;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  ReportType _selectedType = ReportType.lab;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.lg,
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
                'Upload a report',
                style: AppTypography.titleMd
                    .copyWith(color: AppColors.textPrimary, fontSize: 18),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The AI will extract key values and summarise it for you.',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Report type',
                style: AppTypography.labelMd
                    .copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final t in ReportType.values)
                    _TypeChip(
                      type: t,
                      selected: _selectedType == t,
                      onTap: () => setState(() => _selectedType = t),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _SourceTile(
                icon: Icons.photo_camera_rounded,
                title: 'Take a photo',
                subtitle: 'Snap the report with your camera',
                onTap: () => widget.onPicked(ImageSource.camera, _selectedType),
              ),
              const SizedBox(height: AppSpacing.sm),
              _SourceTile(
                icon: Icons.photo_library_rounded,
                title: 'Choose from gallery',
                subtitle: 'Pick an existing image or scan',
                onTap: () =>
                    widget.onPicked(ImageSource.gallery, _selectedType),
              ),
              const SizedBox(height: AppSpacing.sm),
              _SourceTile(
                icon: Icons.picture_as_pdf_rounded,
                title: 'PDF document',
                subtitle: 'Upload a PDF report or prescription',
                onTap: () => widget.onPickedPdf(_selectedType),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });
  final ReportType type;
  final bool selected;
  final VoidCallback onTap;

  String get _label => switch (type) {
        ReportType.lab => 'Lab',
        ReportType.imaging => 'Imaging',
        ReportType.discharge => 'Discharge',
        ReportType.prescription => 'Prescription',
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
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outline,
          ),
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

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  }) : enabled = true;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: enabled ? onTap : null,
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
                decoration: BoxDecoration(
                  color: AppColors.tintBlue,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyLg.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Report row ─────────────────────────────────────────────────────────

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.report,
    required this.onTap,
    this.onDelete,
  });
  final MedicalReport report;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  (IconData, Color) get _icon {
    switch (report.type) {
      case ReportType.lab:
        return (Icons.science_rounded, AppColors.primary);
      case ReportType.imaging:
        return (Icons.image_rounded, AppColors.accentCyan);
      case ReportType.discharge:
        return (Icons.local_hospital_rounded, AppColors.accentViolet);
      case ReportType.prescription:
        return (Icons.medical_services_rounded, AppColors.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _icon;
    return AppCard(
      onTap: onTap,
      accentRail: report.hasRiskFinding ? AppColors.warning : null,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.title,
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      DateFormat.yMMMd().format(report.uploadedAt),
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusPill(
                      label: switch (report.status) {
                        ReportStatus.uploading => 'Uploaded',
                        ReportStatus.processing => 'AI Analysis Started',
                        ReportStatus.analyzed => 'Analysis Complete',
                        ReportStatus.failed => 'Failed',
                      },
                      tone: switch (report.status) {
                        ReportStatus.uploading => PillTone.info,
                        ReportStatus.processing => PillTone.processing,
                        ReportStatus.analyzed => PillTone.success,
                        ReportStatus.failed => PillTone.danger,
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              tooltip: 'Delete report',
              onPressed: onDelete,
            )
          else
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );
  }
}
