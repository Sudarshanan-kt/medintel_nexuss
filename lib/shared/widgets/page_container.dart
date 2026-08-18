import 'package:flutter/widgets.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/page_insets.dart';

/// Centres a page's content and stops it stretching past [maxContent].
///
/// Use this for bodies that are *not* their own scroll view. A scrolling page
/// should pass [pageInsets] to the scroll view's own `padding:` instead —
/// wrapping the scroll view would pull the scrollbar off the window edge and
/// park it against the content, which reads as broken on desktop.
///
/// At phone widths this collapses to nothing more than the [gutter] padding
/// the screen already had, so the mobile app is unaffected.
class PageContainer extends StatelessWidget {
  const PageContainer({
    super.key,
    required this.child,
    this.maxContent = ContentWidth.standard,
    this.gutter = AppSpacing.gutter,
    this.top = 0,
    this.bottom = 0,
  });

  final Widget child;
  final double maxContent;
  final double gutter;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: pageInsets(
          constraints.maxWidth,
          top: top,
          bottom: bottom,
          gutter: gutter,
          maxContent: maxContent,
        ),
        child: child,
      ),
    );
  }
}
