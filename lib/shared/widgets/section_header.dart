import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// A section title with an optional trailing text action ("See all →").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTypography.titleMd.copyWith(color: scheme.onSurface),
          ),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Row(
              children: [
                Text(
                  actionLabel!,
                  style: AppTypography.labelMd.copyWith(color: scheme.primary),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
