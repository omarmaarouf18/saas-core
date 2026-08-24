import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/dashboard_screen_template.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';
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
        return quickDeliveryAppName;
      case 1:
        return l10n.navServices;
      case 2:
        return l10n.customerJobsTitle;
      case 3:
        return l10n.settingsTitle;
      default:
        return quickDeliveryAppName;
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
                tooltip: context.l10n.tooltipNotifications,
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
                  child: ThemedPanel(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(AppRadius.radiusSmMd),
                      padding: const EdgeInsetsDirectional.all(AppSpacing.xxs),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${provider.unreadCount}',
                        style: AppTypography.labelMd.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      )),
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
    return DashboardScreenTemplate(
      title: _getTabTitle(_currentIndex, l10n),
      actions: [
        _buildNotificationBell(context),
      ],
      currentIndex: _currentIndex,
      onDestinationSelected: onTabTapped,
      tabs: [
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
      navigationBarKey: const Key('customer_bottom_navigation_bar'),
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
    );
  }
}

class _CustomerHomeDashboardTab extends StatefulWidget {
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onGoToServices;
  final VoidCallback onGoToHistory;

  const _CustomerHomeDashboardTab({
    required this.onCategorySelected,
    required this.onGoToServices,
    required this.onGoToHistory,
  });

  @override
  State<_CustomerHomeDashboardTab> createState() =>
      _CustomerHomeDashboardTabState();
}

class _CustomerHomeDashboardTabState extends State<_CustomerHomeDashboardTab> {
  DateTime? _lastTileTapTime;

  void _handleDebouncedTap(VoidCallback action) {
    final now = DateTime.now();
    if (_lastTileTapTime != null &&
        now.difference(_lastTileTapTime!) < AppMotion.debounceGuard) {
      return;
    }
    _lastTileTapTime = now;
    action();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final marketplace = Provider.of<MarketplaceProvider>(context);
    final l10n = context.l10n;
    final username = auth.user?.username ?? l10n.quickDeliveryUserFallback;

    final activeJobs = marketplace.customerJobs.where((j) {
      final status = j.status.toLowerCase();
      return status == 'pending' || status == 'active' || status == 'assigned';
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Welcome Hero Banner (Stitch Welcome Banner)
          _buildWelcomeBanner(l10n, username),
          const SizedBox(height: AppSpacing.lg),

          // 2. "Where to deliver?" Quick Search Card
          _buildQuickSearchCard(),
          const SizedBox(height: AppSpacing.xl),

          // 3. Core Services Grid (Stitch 2x2 Services Grid)
          _buildCoreServicesSection(context, l10n),
          const SizedBox(height: AppSpacing.xl),

          // 4. Active Jobs Section (Stitch Active Jobs List)
          _buildActiveJobsSection(l10n, activeJobs, marketplace.error),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner(AppLocalizations l10n, String username) {
    return ThemedPanel(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.mdBorder,
        boxShadow: AppElevation.shadowLevel2List,
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Decorative Gold Ambient Glow
            Positioned(
              right: -20,
              top: -20,
              child: ThemedPanel(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  width: 100,
                  height: 100),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${l10n.customerHomeGreeting} $username!",
                  style: AppTypography.headlineLgMobile.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.customerHomeSub,
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: 170,
                      child: PrimaryButton(
                        key: const Key('quick_book_now_button'),
                        text: l10n.customerHomeQuickBookBtn,
                        icon: Icons.local_shipping_outlined,
                        trailingIcon: Icons.arrow_forward,
                        onPressed: widget.onGoToServices,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ));
  }

  Widget _buildQuickSearchCard() {
    return ThemedCard(
      key: const Key('customer_quick_booking_card'),
      padding: AppSpacing.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.secondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Icon(
                    Icons.near_me,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  )),
              const SizedBox(width: AppSpacing.sm),
              // A8/B1-F1: ellipsized within Expanded — this row overflowed
              // by 56px at 360dp with long localized titles.
              Expanded(
                child: Text(
                  context.l10n.customerHomeWhereDeliver,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: widget.onGoToServices,
            borderRadius: AppRadius.smBorder,
            child: ThemedPanel(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.smBorder,
                border: Border.all(
                  color: AppColors.outlineVariant,
                  width: 1,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: AppIconSize.md,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        context.l10n.customerHomeSearchHint,
                        style: AppTypography.bodyMd.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            key: const Key('find_couriers_button'),
            text: context.l10n.findNearbyCouriers,
            icon: Icons.search,
            trailingIcon: Icons.arrow_forward,
            onPressed: widget.onGoToServices,
          ),
        ],
      ),
    );
  }

  Widget _buildCoreServicesSection(
      BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                child: _buildServiceCard(
                  context,
                  key: const Key('category_tile_delivery'),
                  title: l10n.customerHomeCatDelivery,
                  description: l10n.customerHomeTileDeliveryDesc,
                  icon: Icons.inventory_2_outlined,
                  iconBgColor:
                      AppColors.primaryContainer.withValues(alpha: 0.1),
                  iconColor: AppColors.primaryContainer,
                  onTap: () => widget.onCategorySelected('delivery'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildServiceCard(
                  context,
                  key: const Key('category_tile_transport'),
                  title: l10n.customerHomeCatRide,
                  description: l10n.customerHomeTileRideDesc,
                  icon: Icons.local_shipping_outlined,
                  iconBgColor: AppColors.secondary.withValues(alpha: 0.2),
                  iconColor: AppColors.secondary,
                  onTap: () => widget.onCategorySelected('transport'),
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
                child: _buildServiceCard(
                  context,
                  key: const Key('category_tile_shipping'),
                  title: l10n.customerHomeCatShipping,
                  description: l10n.customerHomeTileCleaningDesc,
                  icon: Icons.home_repair_service_outlined,
                  iconBgColor:
                      context.semanticColors.success.withValues(alpha: 0.15),
                  iconColor: context.semanticColors.success,
                  onTap: () => widget.onCategorySelected('shipping'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildServiceCard(
                  context,
                  key: const Key('category_tile_all'),
                  title: l10n.customerHomeCatBrowseAll,
                  description: l10n.customerHomeTileBrowseAllDesc,
                  icon: Icons.grid_view_rounded,
                  iconBgColor: AppColors.primary.withValues(alpha: 0.1),
                  iconColor: AppColors.primary,
                  onTap: () => widget.onCategorySelected('all'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveJobsSection(
      AppLocalizations l10n, List<dynamic> activeJobs, String? fetchError) {
    return Column(
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
              onPressed: widget.onGoToHistory,
              icon: const Icon(Icons.arrow_forward, size: AppIconSize.sm),
              label: Text(
                l10n.customerHomeCatBrowseAll,
                style: AppTypography.labelLg.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // A8/B1-F1: surface marketplace fetch failures instead of silently
        // rendering stale/empty activity content.
        if (fetchError != null && activeJobs.isEmpty)
          ThemedErrorBanner(
            key: const Key('customer_home_activity_error'),
            message: fetchError,
            onRetry: () {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              if (auth.token != null) {
                Provider.of<MarketplaceProvider>(context, listen: false)
                    .fetchCustomerJobs(auth.token!);
              }
            },
          ),
        if (activeJobs.isNotEmpty) ...[
          Column(
            children: activeJobs.map((job) {
              final displayId = job.id.length > 8
                  ? AppTypography.uppercaseLabel(job.id.substring(0, 8))
                  : AppTypography.uppercaseLabel(job.id);
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ThemedCard(
                  onTap: widget.onGoToHistory,
                  padding: AppSpacing.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "#QD-$displayId",
                                style: AppTypography.caption.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                job.serviceId.isNotEmpty
                                    ? job.serviceId
                                    : l10n.expressDeliveryFallbackLabel,
                                style: AppTypography.titleMd.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          StatusBadge(status: job.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // 2-Phase Progress Bar
                      ClipRRect(
                        borderRadius: AppRadius.smBorder,
                        child: Container(
                          height: 6,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          child: Row(
                            children: [
                              Expanded(
                                flex: job.status.toLowerCase() == 'completed'
                                    ? 4
                                    : 2,
                                child: Container(
                                    color: AppColors.primaryContainer),
                              ),
                              if (job.status.toLowerCase() == 'active' ||
                                  job.status.toLowerCase() == 'assigned')
                                Expanded(
                                  flex: 1,
                                  child: Container(color: AppColors.secondary),
                                ),
                              if (job.status.toLowerCase() == 'pending')
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHigh),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(context.l10n.commonOrigin,
                              style: AppTypography.caption.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          Text(context.l10n.commonDestination,
                              style: AppTypography.caption.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Divider(height: 1, color: AppColors.outlineVariant),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          ThemedPanel(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              shape: BoxShape.circle,
                              width: 32,
                              height: 32,
                              child: Icon(Icons.person,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  job.employeeId != null
                                      ? context.l10n.courierAssignedLabel
                                      : context.l10n.findingCourierLabel,
                                  style: AppTypography.bodySm.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  context.l10n.paymentMethodLine(
                                      AppTypography.uppercaseLabel(
                                          job.paymentMethod)),
                                  style: AppTypography.caption.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (job.agreedPrice != null ||
                              job.suggestedPrice != null)
                            Text(
                              "\$${(job.agreedPrice ?? job.suggestedPrice ?? 0).toStringAsFixed(2)}",
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ] else ...[
          ThemedCard(
            padding: AppSpacing.lg,
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.outline, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.customerJobsEmpty,
                    style: AppTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildServiceCard(
    BuildContext context, {
    required Key key,
    required String title,
    required String description,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return ThemedCard(
      key: key,
      padding: AppSpacing.md,
      child: InkWell(
        onTap: () => _handleDebouncedTap(onTap),
        borderRadius: AppRadius.smBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ThemedPanel(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Icon(icon, color: iconColor, size: AppIconSize.md)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  title,
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: AppTypography.caption.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
