import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/generated/app_localizations.dart';

/// A bottom-nav destination descriptor.
class NavDestination {
  const NavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The 5-slot bottom navigation: Home · Assistant · Scan · Reports · Profile.
///
/// The bar is a floating frosted pill. The selected destination expands into a
/// tinted pill carrying its label, and the others sit as bare icons — so the
/// bar reads as one active place rather than five equal labels competing for
/// attention. **Scan** breaks out of the bar entirely as a raised gradient
/// button, because it's the action the whole app is built around.
///
/// Unselected items have no visible text, so each is given a [Semantics] label
/// and a tooltip — the label is hidden visually, never from assistive tech.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Total height including the part of the scan button that rises above the
  /// bar. Sizing the widget to include the overhang keeps the button inside
  /// its own bounds, so it stays tappable — an overflowing child would paint
  /// fine and then quietly refuse taps.
  static const double _barHeight = 64;
  static const double _scanSize = 58;
  static const double _overhang = 22;

  static List<NavDestination> destinations(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return [
      NavDestination(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: t.navHome,
      ),
      NavDestination(
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome_rounded,
        label: t.navAssistant,
      ),
      NavDestination(
        icon: Icons.center_focus_strong_outlined,
        activeIcon: Icons.center_focus_strong_rounded,
        label: t.navScan,
      ),
      NavDestination(
        icon: Icons.description_outlined,
        activeIcon: Icons.description_rounded,
        label: t.navReports,
      ),
      NavDestination(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: t.navProfile,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = destinations(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SizedBox(
        height: _barHeight + _overhang,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            _Bar(
              height: _barHeight,
              isDark: isDark,
              // Two equal halves either side of a fixed centre gap. Laying it
              // out as one five-child row instead lets the gap drift off
              // centre the moment one side's pill expands, which slides that
              // pill under the scan button.
              child: Row(
                children: [
                  Expanded(
                    child: _Half(
                      children: [
                        _NavPill(
                          destination: items[0],
                          selected: currentIndex == 0,
                          onTap: () => onTap(0),
                        ),
                        _NavPill(
                          destination: items[1],
                          selected: currentIndex == 1,
                          onTap: () => onTap(1),
                        ),
                      ],
                    ),
                  ),
                  // The raised button's footprint plus clearance either side.
                  const SizedBox(width: _scanSize + 16),
                  Expanded(
                    child: _Half(
                      children: [
                        _NavPill(
                          destination: items[3],
                          selected: currentIndex == 3,
                          onTap: () => onTap(3),
                        ),
                        _NavPill(
                          destination: items[4],
                          selected: currentIndex == 4,
                          onTap: () => onTap(4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: _ScanButton(
                size: _scanSize,
                label: items[2].label,
                selected: currentIndex == 2,
                onTap: () => onTap(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frosted pill the destinations sit in.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.child,
    required this.height,
    required this.isDark,
  });

  final Widget child;
  final double height;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          // Two shadows: a tight one to seat the bar, and a wide soft one so
          // it reads as floating well above the page rather than stuck to it.
          BoxShadow(
            color:
                const Color(0xFF0B2B22).withValues(alpha: isDark ? 0.5 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color:
                const Color(0xFF0B2B22).withValues(alpha: isDark ? 0.4 : 0.07),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF101B24).withValues(alpha: 0.82)
                  : Colors.white.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.85),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One side of the bar: two destinations sharing the space beside the centre
/// button.
///
/// The [FittedBox] is the safety net. A 360dp phone has barely enough room for
/// an expanded pill next to a bare icon, and a long translation or a large
/// system font scale would push it over. Scaling the pair down a few percent
/// is invisible; a RenderFlex overflow is not.
class _Half extends StatelessWidget {
  const _Half({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          children[0],
          const SizedBox(width: 4),
          children[1],
        ],
      ),
    );
  }
}

/// One destination. Collapsed to an icon when idle, expanded into a tinted
/// pill with its label when selected.
class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idle = isDark ? AppColors.darkTextSecondary : AppColors.textTertiary;

    return Semantics(
      label: destination.label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: destination.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.base,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 11 : 9,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: AppMotion.base,
                  curve: Curves.easeOutBack,
                  scale: selected ? 1.06 : 1,
                  child: Icon(
                    selected ? destination.activeIcon : destination.icon,
                    size: 22,
                    color: selected ? AppColors.primaryDeep : idle,
                  ),
                ),
                // The label only exists while selected; AnimatedSize turns
                // that into a slide rather than a pop.
                AnimatedSize(
                  duration: AppMotion.base,
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ConstrainedBox(
                            // Long translations (and large font scales) must
                            // truncate rather than overflow the bar.
                            constraints: const BoxConstraints(maxWidth: 54),
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDeep,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Scan — raised out of the bar, with a press-in response.
class _ScanButton extends StatefulWidget {
  const _ScanButton({
    required this.size,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final double size;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      label: widget.label,
      selected: widget.selected,
      button: true,
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: AnimatedScale(
            duration: AppMotion.fast,
            curve: Curves.easeOut,
            scale: _down ? 0.92 : 1,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
                // The ring is the page colour, so the button reads as punched
                // through the bar rather than sitting on top of it.
                border: Border.all(
                  color: isDark ? AppColors.darkSurfaceMuted : Colors.white,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryDeep.withValues(alpha: 0.42),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.center_focus_strong_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
