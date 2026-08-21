import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'app_shell.dart';

/// DashboardScreenTemplate is the standardized composition template for
/// tabbed dashboard/home shells (owner dashboard, customer home, employee home).
/// It encapsulates:
/// - Screen scaffold & navigation chrome via [AppShell]
/// - The canonical brand logo badge ([DashboardScreenTemplate.brandLogo])
/// - A lazy-hydrated [IndexedStack] tab body (callers resolve laziness per tab)
/// - A [NavigationBar] wired to [currentIndex]/[onDestinationSelected]
class DashboardScreenTemplate extends StatelessWidget {
  /// Title of the currently visible tab.
  final String? title;

  /// Optional custom title widget overriding [title].
  final Widget? titleWidget;

  /// Leading widget for the AppBar. Defaults to the Quick Delivery brand logo.
  final Widget? leading;

  /// Action widgets displayed on the trailing end of the AppBar.
  final List<Widget>? actions;

  /// Whether this screen is embedded within a parent navigation tab.
  final bool isEmbeddedInTab;

  /// Background color of the scaffold canvas.
  final Color? backgroundColor;

  /// Background color of the AppBar. Defaults to transparent (dashboard style).
  final Color? appBarBackgroundColor;

  /// Foreground color of the AppBar. Defaults to the theme on-surface color.
  final Color? appBarForegroundColor;

  /// Index of the currently selected tab.
  final int currentIndex;

  /// Called when a navigation destination is tapped.
  final ValueChanged<int> onDestinationSelected;

  /// Tab body widgets rendered inside the [IndexedStack].
  /// Callers decide lazy hydration (e.g. `_visitedTabs.contains(i) ? w : SizedBox.shrink()`).
  final List<Widget> tabs;

  /// Destinations for the [NavigationBar].
  final List<NavigationDestination> destinations;

  /// Key applied to the [NavigationBar].
  final Key? navigationBarKey;

  const DashboardScreenTemplate({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.isEmbeddedInTab = false,
    this.backgroundColor,
    this.appBarBackgroundColor,
    this.appBarForegroundColor,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.tabs,
    required this.destinations,
    this.navigationBarKey,
  });

  /// The canonical Quick Delivery brand logo badge used as dashboard leading chrome.
  static Widget brandLogo() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
      child: Center(
        child: Container(
          key: const Key('app_header_logo'),
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: const Icon(
            Icons.storefront,
            color: AppColors.secondary,
            size: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      titleWidget: titleWidget,
      leading: leading ?? brandLogo(),
      showBackButton: false,
      actions: actions,
      isEmbeddedInTab: isEmbeddedInTab,
      backgroundColor: backgroundColor,
      appBarBackgroundColor:
          appBarBackgroundColor ?? Colors.transparent,
      appBarForegroundColor:
          appBarForegroundColor ?? Theme.of(context).colorScheme.onSurface,
      body: IndexedStack(
        index: currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        key: navigationBarKey,
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      ),
    );
  }
}
