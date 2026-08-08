import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/server_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';

/// Lets the user point the app at a different backend.
///
/// Exists because the server runs on a laptop with a DHCP address: moving
/// between networks changes it, and it used to be compiled into the build.
/// A wrong address here is harmless and reversible — the only cost is that
/// scanning and reports say they can't reach the analyser until it's fixed.
Future<void> showServerSettingsSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => const _ServerSettingsSheet(),
  );
}

class _ServerSettingsSheet extends ConsumerStatefulWidget {
  const _ServerSettingsSheet();

  @override
  ConsumerState<_ServerSettingsSheet> createState() =>
      _ServerSettingsSheetState();
}

enum _ProbeState { idle, testing, reachable, unreachable }

class _ServerSettingsSheetState extends ConsumerState<_ServerSettingsSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(serverConfigProvider));
  _ProbeState _probe = _ProbeState.idle;
  String? _detail;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Checks the address before it's saved, so a typo is caught here rather
  /// than surfacing later as a mysteriously broken scan.
  Future<void> _test() async {
    final url = ServerConfig.normalise(_controller.text);
    if (url.isEmpty) return;

    setState(() {
      _probe = _ProbeState.testing;
      _detail = null;
    });

    try {
      final res = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      ).get<Map<String, dynamic>>('$url/health');

      final ok = res.data?['status'] == 'ok';
      if (!mounted) return;
      setState(() {
        _probe = ok ? _ProbeState.reachable : _ProbeState.unreachable;
        _detail = ok ? null : 'Something answered, but it isn\'t this app\'s '
            'backend.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probe = _ProbeState.unreachable;
        _detail = 'Nothing answered at that address. Check the backend is '
            'running with --host 0.0.0.0, and that the phone is on the same '
            'Wi-Fi.';
      });
    }
  }

  Future<void> _save() async {
    await ref
        .read(serverConfigProvider.notifier)
        .setBaseUrl(_controller.text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                'Server address',
                style: AppTypography.titleMd
                    .copyWith(color: AppColors.textPrimary, fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text(
                'Where the app finds its backend for prescription scanning '
                'and report analysis. The address changes when the computer '
                'running it joins a different network.',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _controller,
                label: 'Address',
                hint: '192.168.0.10:8000',
                keyboardType: TextInputType.url,
                onChanged: (_) {
                  if (_probe != _ProbeState.idle) {
                    setState(() {
                      _probe = _ProbeState.idle;
                      _detail = null;
                    });
                  }
                },
              ),
              if (_probe != _ProbeState.idle) ...[
                const SizedBox(height: AppSpacing.md),
                _ProbeResult(state: _probe, detail: _detail),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      icon: Icons.wifi_tethering_rounded,
                      label: _probe == _ProbeState.testing
                          ? 'Testing…'
                          : 'Test',
                      onPressed:
                          _probe == _ProbeState.testing ? null : _test,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: PrimaryButton(
                      icon: Icons.check_rounded,
                      label: 'Save',
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () async {
                    await ref.read(serverConfigProvider.notifier).reset();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(
                    'Reset to the built-in address',
                    style: AppTypography.labelMd
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProbeResult extends StatelessWidget {
  const _ProbeResult({required this.state, this.detail});
  final _ProbeState state;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final reachable = state == _ProbeState.reachable;
    final testing = state == _ProbeState.testing;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: testing
            ? AppColors.neutral100
            : reachable
                ? AppColors.tintGreen
                : AppColors.tintRed,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            testing
                ? Icons.hourglass_top_rounded
                : reachable
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
            size: 18,
            color: testing
                ? AppColors.textSecondary
                : reachable
                    ? AppColors.success
                    : AppColors.dangerDeep,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              testing
                  ? 'Testing…'
                  : detail ?? 'Backend reachable.',
              style: AppTypography.caption.copyWith(
                color: testing
                    ? AppColors.textSecondary
                    : reachable
                        ? AppColors.successDeep
                        : AppColors.dangerDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
