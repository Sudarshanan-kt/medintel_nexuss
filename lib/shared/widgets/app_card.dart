import 'package:flutter/material.dart';

import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';

/// The standard grounded surface card — soft shadow, rounded corners,
/// optional tap. Use this for content that sits *on* the page; use
/// [GlassContainer] for surfaces that *float* above it.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.radius = AppRadius.lg,
    this.accentRail,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  /// Optional colored rail down the leading edge — used to signal status
  /// (e.g. amber for a risk alert) without shouting.
  final Color? accentRail;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).cardColor;

    Widget body = Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: accentRail == null
            // No rail → simple padded child (no stretch, no infinite-height
            // risk in unbounded scroll contexts).
            ? Padding(padding: padding, child: child)
            // With a rail we need equal-height columns. IntrinsicHeight gives
            // the Row a bounded height so CrossAxisAlignment.stretch is safe.
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: accentRail),
                    Expanded(
                      child: Padding(padding: padding, child: child),
                    ),
                  ],
                ),
              ),
      ),
    );

    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: body,
        ),
      );
    }
    return body;
  }
}
