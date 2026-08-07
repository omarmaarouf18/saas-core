import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/primary_button.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/screens/customer_jobs_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/screens/notifications_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  final int initialTabIndex;
  const CustomerHomeScreen({super.key, this.initialTabIndex = 0});

  @override
  CustomerHomeScreenState createState() => CustomerHomeScreenState();
}

class CustomerHomeScreenState extends State<CustomerHomeScreen> {
  late int _currentIndex;
  final GlobalKey<CustomerMarketplaceScreenState> _marketplaceKey =
      GlobalKey<CustomerMarketplaceScreenState>();

  late Set<int> _visitedTabs;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _visitedTabs = {_currentIndex};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.token != null) {
        Provider.of<MarketplaceProvider>(context, listen: false)
            .fetchCustomerJobs(auth.token!);
      }
    });
  }

  @override
  void didUpdateWidget(CustomerHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      setState(() {
        _currentIndex = widget.initialTabIndex;
        _visitedTabs.add(_currentIndex);
      });
    }
  }

  void onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      _visitedTabs.add(index);
    });
  }

  void _navigateToServicesCategory(String category) {
    setState(() {
      _currentIndex = 1; // Switch to Services tab
      _visitedTabs.add(1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _marketplaceKey.currentState?.selectCategory(category);
    });
  }

  String _getTabTitle(int index, AppLocalizations l10n) {
    switch (index) {
      case 0:
        return l10n.appName;
      case 1:
        return l10n.navServices;
      case 2:
        return l10n.customerJobsTitle;
      case 3:
        return l10n.settingsTitle;
      default:
        return l10n.appName;
    }
  }

  Widget _buildNotificationBell(BuildContext context) {
    return Consumer<NotificationsProvider>(
      builder: (context, provider, child) {
        return SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                key: const Key('notification_bell_button'),
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              if (provider.unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${provider.unreadCount}',
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
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
        ),
        title: Text(
          _getTabTitle(_currentIndex, l10n),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          _buildNotificationBell(context),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _visitedTabs.contains(0)
              ? _CustomerHomeDashboardTab(
                  onCategorySelected: _navigateToServicesCategory,
                  onGoToServices: () => onTabTapped(1),
                  onGoToHistory: () => onTabTapped(2),
                )
              : const SizedBox.shrink(),
          _visitedTabs.contains(1)
              ? CustomerMarketplaceScreen(
                  key: _marketplaceKey,
                  isEmbeddedInTab: true,
                )
              : const SizedBox.shrink(),
          _visitedTabs.contains(2)
              ? const CustomerJobsScreen(
                  isEmbeddedInTab: true,
                )
              : const SizedBox.shrink(),
          _visitedTabs.contains(3)
              ? const SettingsScreen(
                  isEmbeddedInTab: true,
                )
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('customer_bottom_navigation_bar'),
        selectedIndex: _currentIndex,
        onDestinationSelected: onTabTapped,
        destinations: [
          NavigationDestination(
            key: const Key('nav_tab_home'),
            icon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            key: const Key('nav_tab_services'),
            icon: const Icon(Icons.storefront),
            label: l10n.navServices,
          ),
          NavigationDestination(
            key: const Key('nav_tab_history'),
            icon: const Icon(Icons.receipt_long),
            label: l10n.navHistory,
          ),
          NavigationDestination(
            key: const Key('nav_tab_settings'),
            icon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}

class _CustomerHomeDashboardTab extends StatelessWidget {
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onGoToServices;
  final VoidCallback onGoToHistory;

  const _CustomerHomeDashboardTab({
    required this.onCategorySelected,
    required this.onGoToServices,
    required this.onGoToHistory,
  });

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final marketplace = Provider.of<MarketplaceProvider>(context);
    final l10n = context.l10n;
    final username = auth.user?.username ?? 'Customer';

    final activeJobs = marketplace.customerJobs.where((j) {
      final status = j.status.toLowerCase();
      return status == 'pending' || status == 'active' || status == 'assigned';
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting Header
          Text(
            "${l10n.customerHomeGreeting} $username!",
            style: AppTypography.headlineLg.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.customerHomeSub,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Quick Access Categories
          ThemedSectionHeader(
            title: l10n.customerHomeQuickAccess,
            subtitle: l10n.customerHomeSub,
          ),
          const SizedBox(height: AppSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildCategoryTile(
                    context,
                    key: const Key('category_tile_delivery'),
                    title: l10n.customerHomeCatDelivery,
                    icon: Icons.delivery_dining,
                    color: AppColors.success,
                    onTap: () => onCategorySelected('delivery'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildCategoryTile(
                    context,
                    key: const Key('category_tile_transport'),
                    title: l10n.customerHomeCatRide,
                    icon: Icons.directions_car,
                    color: AppColors.primary,
                    onTap: () => onCategorySelected('transport'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildCategoryTile(
                    context,
                    key: const Key('category_tile_shipping'),
                    title: l10n.customerHomeCatShipping,
                    icon: Icons.local_shipping,
                    color: AppColors.warning,
                    onTap: () => onCategorySelected('shipping'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildCategoryTile(
                    context,
                    key: const Key('category_tile_all'),
                    title: l10n.customerHomeCatBrowseAll,
                    icon: Icons.grid_view_rounded,
                    color: AppColors.primary,
                    onTap: () => onCategorySelected('all'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Active Activity Summary
          ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: ThemedSectionHeader(
                        title: l10n.customerHomeRecentActivity,
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('view_all_orders_button'),
                      onPressed: onGoToHistory,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: Text(l10n.customerHomeCatBrowseAll),
                    ),
                  ],
                ),
                const Divider(
                  height: AppSpacing.lg,
                  color: AppColors.outlineVariant,
                ),
                if (activeJobs.isNotEmpty) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.local_shipping_outlined,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${activeJobs.length} Active / Pending Order(s)",
                              style: AppTypography.bodyLg.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            Text(
                              "Latest order status: ${activeJobs.first.status.toUpperCase()}",
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.outline, size: 20),
                      const SizedBox(width: AppSpacing.base),
                      Expanded(
                        child: Text(
                          l10n.customerJobsEmpty,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Quick Action Booking Banner
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.customerHomeQuickBookBanner,
                        style: AppTypography.headlineLgMobile.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.customerHomeSub,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 140,
                  child: PrimaryButton(
                    key: const Key('quick_book_now_button'),
                    text: l10n.customerHomeQuickBookBtn,
                    onPressed: onGoToServices,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(
    BuildContext context, {
    required Key key,
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ThemedCard(
      key: key,
      padding: AppSpacing.md,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                style: AppTypography.labelLg.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
