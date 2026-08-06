import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Themed text field with an optional floating label, helper text, prefix
/// icon and error handling. Wraps the theme's `inputDecorationTheme`.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.prefixIcon,
    this.suffix,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.onChanged,
    this.textInputAction,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final IconData? prefixIcon;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool enabled;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTypography.labelMd.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          textInputAction: textInputAction,
          enabled: enabled,
          textCapitalization: textCapitalization,
          style: AppTypography.bodyLg.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            helperStyle: AppTypography.caption
                .copyWith(color: AppColors.textTertiary),
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, color: AppColors.textSecondary),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}
