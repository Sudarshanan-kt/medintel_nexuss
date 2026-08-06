import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';

/// Frosted-glass panel — the signature floating surface of the design system.
///
/// Backdrop blur + translucent fill + hairline stroke + feathered glass
/// shadow. Used for the bottom nav, search bar, assistant bubbles and any
/// surface that floats above content.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 18,
    this.radius = AppRadius.lg,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.showShadow = true,
  });

  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? AppColors.darkGlassFill : AppColors.glassFill;
    final stroke = isDark ? AppColors.darkGlassStroke : AppColors.glassStroke;

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: stroke),
          ),
          child: child,
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: showShadow ? AppShadows.glass : null,
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}
