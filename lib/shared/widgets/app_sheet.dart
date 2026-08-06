import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/extensions.dart';

/// Responsive modal presenter.
///
/// On compact (phone) widths this shows a Material **bottom sheet** — the
/// native mobile pattern. On medium/expanded (tablet + web/desktop) widths it
/// shows a **centered, width-constrained dialog** instead, so modals no longer
/// stretch full-width or overflow the bottom of the window on the web build.
///
/// In both modes the content is made scrollable, which removes the
/// "BOTTOM OVERFLOWED" errors when a sheet is taller than the available space
/// (e.g. long forms, or when the on-screen keyboard is up).
///
/// Call sites pass the same [builder] they used with `showModalBottomSheet`;
/// the content widget is expected to provide its own surface (background +
/// rounded corners), which every sheet in this app already does.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 480,
}) {
  if (context.isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScrollableSheetBody(child: builder(ctx)),
    );
  }

  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.9;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: SingleChildScrollView(child: builder(ctx)),
          ),
        ),
      );
    },
  );
}

/// On compact bottom sheets, lets tall content scroll instead of overflowing.
/// Caps height at 92% of the screen and respects the keyboard inset.
class _ScrollableSheetBody extends StatelessWidget {
  const _ScrollableSheetBody({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: child),
    );
  }
}
