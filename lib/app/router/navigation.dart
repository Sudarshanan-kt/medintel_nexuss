import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'route_names.dart';

/// Navigation that leaves a back stack behind it.
///
/// go_router's `go()` *replaces* the current location rather than stacking on
/// it. Used for forward navigation — opening a report, a reminder, a
/// patient — it leaves nothing to pop, so the system back gesture finds an
/// empty stack and closes the app instead of returning to the previous
/// screen. That was the behaviour across almost every screen here: 45 `go()`
/// calls against 2 `push()`.
///
/// The distinction these helpers encode:
///
///   * [openScreen] — going *into* something. Pushes, so back returns.
///   * [backOr]     — coming *out* of something. Pops if there's anything to
///                    pop, otherwise lands on a sensible root.
///
/// Tabs are the exception. The five shell branches are siblings, not a stack:
/// switching to one should replace, exactly as tapping the bottom bar does.
/// Pushing a tab route would mount a second copy of that branch on top of the
/// shell, complete with its own bottom bar.
extension AppNavigation on BuildContext {
  /// Opens [location] as a screen the user can back out of.
  ///
  /// Switches branches for a bottom-nav tab, pushes for anything else, so
  /// callers don't have to know which is which — including callers handed a
  /// route path at runtime, like the dashboard's quick actions.
  void openScreen(String location, {Object? extra}) {
    if (_isShellTab(location)) {
      go(location, extra: extra);
    } else {
      push<void>(location, extra: extra);
    }
  }

  /// Returns to the previous screen, or to [fallback] when this screen was
  /// opened without one (a deep link, a notification tap, or a redirect).
  ///
  /// Every in-app back affordance should use this, so the button in the app
  /// bar and the system gesture agree with each other.
  void backOr(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }

  /// Whether [location] is one of the persistent bottom-nav branches.
  ///
  /// Compares the first path segment, so `/reports/abc123` is recognised as
  /// living inside the reports tab while still being pushable.
  static bool _isShellTab(String location) {
    final path = Uri.parse(location).path;
    return Routes.shellTabs.contains(path);
  }
}
