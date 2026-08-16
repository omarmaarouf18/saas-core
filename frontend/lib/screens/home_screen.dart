import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_success_banner.dart';
import 'login_screen.dart';
import 'wallet_screen.dart';
import 'employee_screen.dart';
import 'service_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'subscription_screen.dart';

import 'owner_history_screen.dart';
import 'employee_home_screen.dart';
import 'customer_home_screen.dart';
import 'owner_reconciliation_queue_screen.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/rating_summary_card.dart';
import '../widgets/cancel_job_dialog.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/skeleton_loader.dart';

class HomeScreen extends StatefulWidget {
  final int initialTabIndex;
  const HomeScreen({super.key, this.initialTabIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _currentIndex;
  late Set<int> _visitedTabs;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _visitedTabs = {_currentIndex};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
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

  String _getTabTitle(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context)!;
    switch (index) {
      case 0:
        return l10n.ownerHomeTabTitleDashboard;
      case 1:
        return l10n.ownerHomeTabTitleWorkers;
      case 2:
        return l10n.ownerHistoryTitle;
      case 3:
        return l10n.settingsTitle;
      default:
        return l10n.ownerHomeTabTitleDashboard;
    }
  }

  Future<void> _refreshData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.fetchUserProfile();
    if (!mounted) return;
    if (auth.user?.role == 'owner') {
      final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
      await ownerProvider.fetchDashboardData(auth.token!);
      await ownerProvider.fetchOwnerJobs(auth.token!);
    }
  }

  Widget _buildNotificationBell(BuildContext context) {
    return Consumer<NotificationsProvider>(
      builder: (context, provider, child) {
        final l10n = AppLocalizations.of(context)!;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications),
              tooltip: l10n.ownerHomeTooltipNotifications,
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
                  padding: const EdgeInsetsDirectional.all(AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(AppRadius.radiusSmMd),
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
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final user = auth.user;

    if (user == null) {
      return const LoginScreen();
    }

    final isOwner = user.role == "owner";

    if (!isOwner) {
      if (user.role == 'employee') {
        return EmployeeHomeScreen(initialTabIndex: widget.initialTabIndex);
      }
      if (user.role == 'user') {
        return const CustomerHomeScreen();
      }
      // Non-owner basic dashboard
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
            l10n.quickDeliveryDashboard,
            style: AppTypography.titleMd
                .copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
          actions: [
            _buildNotificationBell(context),
            IconButton(
              key: const Key('settings_button'),
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.ownerHomeTooltipSettings,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.ownerHomeWelcomeUser(
                    user.username.isNotEmpty ? user.username : user.email),
                style: AppTypography.headlineLgMobile.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                l10n.ownerHomeAccountId(user.id),
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ThemedCard(
                borderRadius: AppRadius.md,
                padding: AppSpacing.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThemedSectionHeader(title: l10n.ownerHomeProfileInfo),
                    const Divider(
                      height: AppSpacing.lg,
                      color: AppColors.outlineVariant,
                    ),
                    _buildDetailRow(l10n.ownerHomeLabelUsername, user.username),
                    _buildDetailRow(l10n.ownerHomeLabelEmail, user.email),
                    _buildDetailRow(
                        l10n.ownerHomeLabelRole, user.role.toUpperCase()),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
          _getTabTitle(context, _currentIndex),
          style: AppTypography.titleMd
              .copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.gavel_outlined),
            tooltip: l10n.ownerHomeTooltipEscrowReconciliation,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const OwnerReconciliationQueueScreen(),
                ),
              );
            },
          ),
          _buildNotificationBell(context),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _visitedTabs.contains(0)
                    ? _buildDashboardTab(context, user)
                    : const SizedBox.shrink(),
                _visitedTabs.contains(1)
                    ? const EmployeeScreen()
                    : const SizedBox.shrink(),
                _visitedTabs.contains(2)
                    ? const OwnerHistoryScreen(isEmbeddedInTab: true)
                    : const SizedBox.shrink(),
                _visitedTabs.contains(3)
                    ? const SettingsScreen(isEmbeddedInTab: true)
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('owner_bottom_navigation_bar'),
        selectedIndex: _currentIndex,
        onDestinationSelected: onTabTapped,
        destinations: [
          NavigationDestination(
            key: const Key('owner_nav_tab_home'),
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.ownerHomeNavHome,
          ),
          NavigationDestination(
            key: const Key('owner_nav_tab_employees'),
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: l10n.ownerHomeNavEmployees,
          ),
          NavigationDestination(
            key: const Key('owner_nav_tab_history'),
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l10n.ownerHomeNavHistory,
          ),
          NavigationDestination(
            key: const Key('owner_nav_tab_settings'),
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.ownerHomeNavSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context, authUser) {
    final l10n = AppLocalizations.of(context)!;
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    final walletText = ownerProvider.isLoading
        ? "..."
        : l10n.ownerHomeCreditsAmount(
            ownerProvider.walletBalance.toStringAsFixed(2));

    final subText = ownerProvider.isLoading
        ? "..."
        : ownerProvider.subscriptionTier.toUpperCase().replaceAll('_', ' ');

    final subColor = ownerProvider.subscriptionTier == "paid"
        ? AppColors.success
        : (ownerProvider.subscriptionTier == "pending_payment"
            ? AppColors.primary
            : AppColors.warning);

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AnimatedSwitcher(
          duration: AppMotion.durationMedium,
          switchInCurve: AppMotion.curveStateChange,
          switchOutCurve: AppMotion.curveStateChange,
          child: ownerProvider.isLoading
              ? const HomeDashboardSkeleton(
                  key: ValueKey('home_dashboard_skeleton'),
                )
              : TweenAnimationBuilder<double>(
                  key: const ValueKey('home_dashboard_content'),
                  duration: AppMotion.durationMediumSlow,
                  curve: AppMotion.curveEntrance,
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  builder: (context, animValue, child) {
                    return Opacity(
                      opacity: animValue,
                      child: Transform.translate(
                        offset: Offset(0, 15 * (1 - animValue)),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Section with Welcome Greeting & Compact Wallet Balance Badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.ownerHomeWelcomeUser(
                                      authUser.username.isNotEmpty
                                          ? authUser.username
                                          : authUser.email),
                                  style:
                                      AppTypography.headlineLgMobile.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  l10n.ownerHomeTenantId(authUser.id),
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          InkWell(
                            key: const Key('owner_dashboard_wallet_badge'),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const WalletScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.full),
                                border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    walletText,
                                    style: AppTypography.labelLg.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Compact Inline Summary Card replacing dense StatCard grid
                      ThemedCard(
                        borderRadius: AppRadius.md,
                        padding: AppSpacing.md,
                        child: Row(
                          children: [
                            // Subscription Tier Item
                            Expanded(
                              child: InkWell(
                                key: const Key('owner_dashboard_sub_chip'),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SubscriptionScreen(),
                                    ),
                                  );
                                },
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.xs),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.card_membership_outlined,
                                        color: subColor,
                                        size: 22,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        subText,
                                        style: AppTypography.labelLg.copyWith(
                                          color: subColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        l10n.ownerHomeSubTitle,
                                        style: AppTypography.labelMd.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            Container(
                              height: 36,
                              width: 1,
                              color: AppColors.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),

                            // Employee Roster Item
                            Expanded(
                              child: InkWell(
                                key:
                                    const Key('owner_dashboard_employees_chip'),
                                onTap: () {
                                  onTabTapped(1); // Switch to Employees tab
                                },
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.xs),
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.people_outline,
                                        color: AppColors.primary,
                                        size: 22,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        l10n.ownerHomeRosterTitle,
                                        style: AppTypography.labelLg.copyWith(
                                          color: AppColors.onSurface,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        l10n.ownerHomeEmployeesSub,
                                        style: AppTypography.labelMd.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            Container(
                              height: 36,
                              width: 1,
                              color: AppColors.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),

                            // Escrow Review Item
                            Expanded(
                              child: InkWell(
                                key: const Key('owner_dashboard_escrow_chip'),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const OwnerReconciliationQueueScreen(),
                                    ),
                                  );
                                },
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.xs),
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.gavel_outlined,
                                        color: AppColors.secondary,
                                        size: 22,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        l10n.ownerHomeEscrowTitle,
                                        style: AppTypography.labelLg.copyWith(
                                          color: AppColors.secondary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        l10n.ownerHomeReviewQueueSub,
                                        style: AppTypography.labelMd.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.lg),
                      // Quick Access Management Cards
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              key: const Key('owner_dashboard_wallet_card'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const WalletScreen(),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: ThemedCard(
                                padding: AppSpacing.md,
                                child: Row(
                                  children: [
                                    Container(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.sm),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: const Icon(
                                        Icons.account_balance_wallet,
                                        color: AppColors.primary,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l10n.ownerHomeMyWallet,
                                            style:
                                                AppTypography.titleMd.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            l10n.ownerHomeWalletSub,
                                            style:
                                                AppTypography.labelMd.copyWith(
                                              color: AppColors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: AppColors.onSurfaceVariant,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: InkWell(
                              key: const Key('owner_dashboard_services_card'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const ServiceScreen(),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: ThemedCard(
                                padding: AppSpacing.md,
                                child: Row(
                                  children: [
                                    Container(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.sm),
                                      decoration: BoxDecoration(
                                        color: AppColors.secondary
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: const Icon(
                                        Icons.storefront,
                                        color: AppColors.secondary,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l10n.ownerHomeServices,
                                            style:
                                                AppTypography.titleMd.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            l10n.ownerHomeServicesSub,
                                            style:
                                                AppTypography.labelMd.copyWith(
                                              color: AppColors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: AppColors.onSurfaceVariant,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.lg),
                      FutureBuilder<Map<String, dynamic>>(
                        future: Provider.of<MarketplaceProvider>(context,
                                listen: false)
                            .fetchRatings(auth.token!),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding:
                                  EdgeInsets.symmetric(vertical: AppSpacing.sm),
                              child: SkeletonLoader(
                                height: 70,
                                borderRadius: AppRadius.md,
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return const SizedBox.shrink();
                          }
                          final data = snapshot.data;
                          if (data == null) {
                            return const SizedBox.shrink();
                          }
                          final double avg =
                              (data['average_rating'] as num?)?.toDouble() ??
                                  0.0;
                          final int count =
                              (data['count'] as num?)?.toInt() ?? 0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ThemedSectionHeader(
                                title: l10n.ownerHomeServiceReputation,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              RatingSummaryCard(
                                  averageRating: avg, ratingCount: count),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: AppSpacing.xl),
                      ThemedSectionHeader(title: l10n.ownerHomeOwnerJobs),
                      const SizedBox(height: AppSpacing.sm),

                      if (ownerProvider.ownerJobs.isEmpty)
                        ThemedCard(
                          borderRadius: AppRadius.md,
                          padding: AppSpacing.lg,
                          child: ThemedEmptyState(
                            icon: Icons.assignment_outlined,
                            title: l10n.ownerHomeNoJobsTitle,
                            description: l10n.ownerHomeNoJobsDesc,
                            actionText: "Manage Services",
                            onActionPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ServiceScreen())),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: ownerProvider.ownerJobs.length,
                          itemBuilder: (context, index) {
                            final job = ownerProvider.ownerJobs[index];
                            final canCancel = job.status == 'pending' ||
                                job.status == 'active';
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.md),
                              child: ThemedCard(
                                padding: AppSpacing.md,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          l10n.ownerHomeJobId(job.id),
                                          style: AppTypography.titleMd.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        StatusBadge(status: job.status),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      l10n.ownerHomePaymentInfo(
                                          job.paymentMethod.toUpperCase(),
                                          job.lockedEscrowAmount != null
                                              ? ' (\$${job.lockedEscrowAmount!.toStringAsFixed(2)})'
                                              : ''),
                                      style: AppTypography.bodyMd.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                    if (canCancel) ...[
                                      const SizedBox(height: AppSpacing.sm),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: SecondaryButton(
                                          key: Key(
                                              'cancel_owner_job_button_${job.id}'),
                                          text: l10n.ownerHomeCancelJob,
                                          icon: Icons.cancel_outlined,
                                          isOutlined: true,
                                          onPressed: () async {
                                            await CancelJobDialog.show(
                                              context,
                                              jobId: job.id,
                                              onConfirm: (reason) async {
                                                await ownerProvider.cancelJob(
                                                  jobId: job.id,
                                                  reason: reason,
                                                  ownerToken: auth.token!,
                                                );
                                                if (context.mounted) {
                                                  final isNonCod = job
                                                          .paymentMethod
                                                          .toLowerCase() !=
                                                      'cod';
                                                  final msg = isNonCod
                                                      ? l10n
                                                          .ownerHomeJobCancelledEscrowRefunded
                                                      : l10n
                                                          .ownerHomeJobCancelled;
                                                  ThemedSnackBar.showSuccess(
                                                      context, msg);
                                                }
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodyMd.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMd.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
