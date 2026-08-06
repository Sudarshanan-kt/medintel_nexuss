import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Responsive helpers on [BuildContext].
extension ResponsiveContext on BuildContext {
  double get width => MediaQuery.sizeOf(this).width;
  double get height => MediaQuery.sizeOf(this).height;

  bool get isCompact => width < Breakpoints.medium;
  bool get isMedium =>
      width >= Breakpoints.medium && width < Breakpoints.expanded;
  bool get isExpanded => width >= Breakpoints.expanded;

  /// Number of columns the quick-action grid should use.
  int get quickActionColumns => isExpanded ? 8 : (isMedium ? 6 : 4);

  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

/// Time-of-day greeting.
extension GreetingDateTime on DateTime {
  String get greeting {
    final h = hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

extension StringCasing on String {
  String get capitalized =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
