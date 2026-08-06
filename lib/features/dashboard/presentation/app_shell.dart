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
      return Material(
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
      );
    }

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          _SideRail(
            currentIndex: navigationShell.currentIndex,
            onTap: _onTap,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
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
