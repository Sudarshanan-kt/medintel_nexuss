import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../push/application/push_controller.dart';
import '../../reminders/reminders_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/extensions.dart';
import '../../../shared/widgets/widgets.dart';

/// Persistent shell hosted by [StatefulShellRoute.indexedStack].
///
/// The [navigationShell] keeps every tab's branch alive in an IndexedStack
/// underneath, so switching tabs is instant and the screen state survives.
/// On compact widths we render the glass [AppBottomNav]; on medium/expanded
/// widths we render a side [NavigationRail]-style menu instead.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the reminder scheduler alive while the app is open so notifications
    // fire even when the reminders screen isn't the active tab.
    ref.watch(remindersControllerProvider);
    // Keep push-notification registration alive the same way.
    ref.watch(pushControllerProvider);

    final compact = context.isCompact;

    if (compact) {
      // NB: Column, not Scaffold. Each child screen has its own Scaffold
      // via GradientScaffold, and nested Scaffolds broke layout on Android
      // 15+ edge-to-edge.
      return _BackToHome(
        navigationShell: navigationShell,
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              Expanded(child: navigationShell),
              SafeArea(
                top: false,
                child: AppBottomNav(
                  currentIndex: navigationShell.currentIndex,
                  onTap: _onTap,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _BackToHome(
      navigationShell: navigationShell,
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          children: [
            _SideRail(
              currentIndex: navigationShell.currentIndex,
              onTap: _onTap,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _ContentArea(child: navigationShell)),
          ],
        ),
      ),
    );
  }
}

/// Makes the content column report its own width to everything inside it.
///
/// Screens size their gutters off `MediaQuery`, which reports the *window*.
/// Once the rail has taken its 240 logical pixels off the left, a screen
/// sizing itself against the window is centring against the wrong box: the
/// content lands left of centre and comes out wider than it was capped at.
///
/// Overriding the size here fixes every screen at once, and means no screen
/// needs a `LayoutBuilder` of its own just to find out how much room it got.
///
/// Only the wide branch wraps this. On compact the window *is* the content
/// area, so the phone app never sees the override.
class _ContentArea extends StatelessWidget {
  const _ContentArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: Size(constraints.maxWidth, constraints.maxHeight),
        ),
        child: child,
      ),
    );
  }
}

/// Makes the system back gesture return to the Home tab before it leaves the
/// app.
///
/// The five branches are siblings, not a stack, so standing on Reports with
/// nothing pushed leaves the back gesture with nothing to pop — and Android
/// reads an unhandled back as "close the app". Tapping four tabs and swiping
/// back would drop the user straight to the launcher.
///
/// Only the last step out of Home is allowed through. [PopScope.canPop] is
/// true there rather than intercepting and calling `SystemNavigator.pop()`,
/// which keeps Android's predictive-back animation working: the system needs
/// to know in advance that this gesture will exit in order to draw it.
class _BackToHome extends StatelessWidget {
  const _BackToHome({required this.navigationShell, required this.child});

  final StatefulNavigationShell navigationShell;
  final Widget child;

  static const int _homeBranch = 0;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: navigationShell.currentIndex == _homeBranch,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        navigationShell.goBranch(_homeBranch);
      },
      child: child,
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                AppConstants.appName,
                style: AppTypography.titleMd
                    .copyWith(color: AppColors.textPrimary, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          for (var i = 0; i < AppBottomNav.destinations(context).length; i++)
            _RailItem(
              destination: AppBottomNav.destinations(context)[i],
              selected: currentIndex == i,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.tintBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                selected ? destination.activeIcon : destination.icon,
                color: selected ? AppColors.primary : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                destination.label,
                style: AppTypography.labelMd.copyWith(
                  color:
                      selected ? AppColors.primaryDeep : AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
