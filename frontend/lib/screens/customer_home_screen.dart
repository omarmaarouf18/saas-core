import 'package:flutter/material.dart';
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

  String _getTabTitle(int index) {
    switch (index) {
      case 0:
        return "Quick Delivery";
      case 1:
        return "Services Marketplace";
      case 2:
        return "My Orders";
      case 3:
        return "Settings";
      default:
        return "Quick Delivery";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: Text(_getTabTitle(_currentIndex)),
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
        destinations: const [
          NavigationDestination(
            key: Key('nav_tab_home'),
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            key: Key('nav_tab_services'),
            icon: Icon(Icons.storefront),
            label: 'Services',
          ),
          NavigationDestination(
            key: Key('nav_tab_history'),
            icon: Icon(Icons.receipt_long),
            label: 'History',
          ),
          NavigationDestination(
            key: Key('nav_tab_settings'),
            icon: Icon(Icons.settings),
            label: 'Settings',
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
    final user = auth.user;
    final username = user?.username.isNotEmpty == true
        ? user!.username
        : (user?.email ?? 'Customer');

    final activeJobs = marketplace.customerJobs
        .where((j) =>
            j.status.toLowerCase().trim() == 'active' ||
            j.status.toLowerCase().trim() == 'pending' ||
            j.status.toLowerCase().trim() == 'awaiting_price_response')
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting Header
          Text(
            "Welcome back, $username!",
            style: AppTypography.headlineLgMobile.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "What would you like to book today?",
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Quick Access Categories
          const ThemedSectionHeader(
            title: "Quick Services Access",
            subtitle: "Browse available services by category",
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
                    title: "Delivery",
                    icon: Icons.delivery_dining,
                    color: const Color(0xFF15803D),
                    onTap: () => onCategorySelected('delivery'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildCategoryTile(
                    context,
                    key: const Key('category_tile_transport'),
                    title: "Ride",
                    icon: Icons.directions_car,
                    color: const Color(0xFF1D4ED8),
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
                    title: "Shipping",
                    icon: Icons.local_shipping,
                    color: const Color(0xFFB45309),
                    onTap: () => onCategorySelected('shipping'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildCategoryTile(
                    context,
                    key: const Key('category_tile_all'),
                    title: "Browse All",
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
                    const Expanded(
                      child: ThemedSectionHeader(
                        title: "Recent Activity",
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('view_all_orders_button'),
                      onPressed: onGoToHistory,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text("View All"),
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
                          "No active orders right now.",
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
          ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Need a service delivered?",
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "Find nearby verified service providers and book in seconds.",
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  key: const Key('book_now_home_button'),
                  text: "Explore Marketplace",
                  icon: Icons.search,
                  onPressed: onGoToServices,
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
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: AppRadius.mdBorder,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: AppRadius.mdBorder,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdBorder,
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                title,
                style: AppTypography.bodyLg.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
