import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/care_circle_controller.dart';
import '../data/care_circle_repository.dart';
import '../domain/care_circle_models.dart';

/// Deep-link landing screen for `medintel://invite/<code>` (mapped to the
/// `/invite/:code` route). Requires the invitee to already be signed in —
/// if not, the router's auth redirect sends them to sign in first and they
/// re-open the link afterward (no redirect-memory in v1).
class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<AcceptInviteScreen> createState() =>
      _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  CareCircleInvite? _invite;
  bool _loading = true;
  bool _accepting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final invite =
          await ref.read(careCircleRepositoryProvider).lookupInvite(widget.code);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _loading = false;
        if (invite == null) {
          _error = 'This invite code was not found.';
        } else if (!invite.isPending) {
          _error = 'This invite has expired or was already used.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not look up this invite. Check your connection.';
      });
    }
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await ref
          .read(careCircleControllerProvider.notifier)
          .acceptInvite(widget.code);
      if (!mounted) return;
      context.go(Routes.careCircle);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('Join Care Circle')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.danger,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: AppTypography.bodyMd
                                  .copyWith(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_invite != null) ...[
                    Text(
                      "You've been invited",
                      style: AppTypography.headlineMd
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${_invite!.patientDisplayName} wants to share their '
                      'medicine adherence with you as a caregiver. You will '
                      'be able to see whether doses were taken or missed — '
                      'not their full health profile.',
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      label: 'Accept & join',
                      icon: Icons.check_circle_rounded,
                      isLoading: _accepting,
                      onPressed: _accept,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
