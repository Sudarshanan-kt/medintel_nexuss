import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Scaffold with a soft aurora-mesh background — the standard screen
/// container for MedIntel Nexus. Honours dark mode.
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.showMesh = true,
    this.extendBody = false,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool showMesh;
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: extendBody,
      extendBodyBehindAppBar: appBar != null,
      resizeToAvoidBottomInset: true,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Stack(
        children: [
          if (showMesh) _AuroraMesh(isDark: isDark),
          SafeArea(bottom: false, child: body),
        ],
      ),
    );
  }
}

class _AuroraMesh extends StatelessWidget {
  const _AuroraMesh({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceMuted
                : AppColors.surfaceMuted,
          ),
          child: Stack(
            children: [
              _blob(
                top: -120,
                left: -80,
                size: 320,
                color: AppColors.primary
                    .withValues(alpha: isDark ? 0.22 : 0.16),
              ),
              _blob(
                top: 60,
                right: -110,
                size: 280,
                color: AppColors.accentCyan
                    .withValues(alpha: isDark ? 0.18 : 0.14),
              ),
              _blob(
                bottom: -140,
                left: -60,
                size: 360,
                color: AppColors.accentViolet
                    .withValues(alpha: isDark ? 0.16 : 0.10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blob({
    double? top,
    double? left,
    double? right,
    double? bottom,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
