import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import '../theme/app_spacing.dart';

/// Horizontal inset that holds a page's content to [maxContent] and centres
/// it once there is more room than that.
///
/// Pass the width of the box the content actually sits in — a
/// `LayoutBuilder`'s `constraints.maxWidth`, not `MediaQuery.sizeOf`. On wide
/// layouts the shell spends 240 logical pixels on the side rail, and sizing
/// the gutters against the window instead of the remaining column centres the
/// content against the wrong box: it lands visibly left of centre and comes
/// out narrower than [maxContent].
///
/// Below [maxContent] this returns [gutter] unchanged, so phone widths keep
/// the exact padding they had before any of this existed.
double pageSideInset(
  double availableWidth, {
  double gutter = AppSpacing.gutter,
  double maxContent = ContentWidth.standard,
}) =>
    math.max(gutter, (availableWidth - maxContent) / 2);

/// [pageSideInset] as page padding with explicit vertical values — the shape
/// a scrolling page's `padding:` argument wants.
EdgeInsets pageInsets(
  double availableWidth, {
  double top = 0,
  double bottom = 0,
  double gutter = AppSpacing.gutter,
  double maxContent = ContentWidth.standard,
}) {
  final side =
      pageSideInset(availableWidth, gutter: gutter, maxContent: maxContent);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}
