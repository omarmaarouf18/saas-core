import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_success_banner.dart';
import '../widgets/rating_summary_card.dart';
import '../widgets/app_shell.dart';
import '../widgets/cancel_job_dialog.dart';
import '../widgets/dashboard_screen_template.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/skeleton_loader.dart';
import 'login_screen.dart';
import 'wallet_screen.dart';
import 'employee_screen.dart';
import 'service_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'subscription_screen.dart';
import 'owner_configuration_screen.dart';
import 'owner_history_screen.dart';
import 'employee_home_screen.dart';
import 'customer_home_screen.dart';
import 'owner_reconciliation_queue_screen.dart';
import 'owner_fleet_map_screen.dart';

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
              icon: const Icon(Icons.notifications_outlined),
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

    if (user.role == 'employee') {
      return EmployeeHomeScreen(initialTabIndex: widget.initialTabIndex);
    }
    if (user.role == 'user') {
      return const CustomerHomeScreen();
    }
    if (user.role != 'owner') {
      return _buildNonOwnerShell(user, l10n);
    }

    return _buildOwnerShell(user, l10n);
  }

  Widget _buildOwnerShell(UserProfile user, AppLocalizations l10n) {
    return DashboardScreenTemplate(
      backgroundColor: AppColors.scaffoldBackground,
      title: _getTabTitle(context, _currentIndex),
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
      currentIndex: _currentIndex,
      onDestinationSelected: onTabTapped,
      tabs: [
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
      navigationBarKey: const Key('owner_bottom_navigation_bar'),
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
    );
  }

  Widget _buildDashboardTab(BuildContext context, UserProfile authUser) {
    final l10n = AppLocalizations.of(context)!;
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    final walletText = ownerProvider.isLoading
        ? "..."
        : l10n.ownerHomeCreditsAmount(
            ownerProvider.walletBalance.toStringAsFixed(2));

    final subText = ownerProvider.isLoading
        ? "..."
        : AppTypography.uppercaseLabel(ownerProvider.subscriptionTier)
            .replaceAll('_', ' ');

    final subColor = ownerProvider.subscriptionTier == "paid"
        ? AppColors.success
        : (ownerProvider.subscriptionTier == "pending_payment"
            ? AppColors.primary
            : AppColors.warning);

    final totalEmployees = ownerProvider.employees.length;
    final activeEmployees =
        ownerProvider.employees.where((e) => e['is_active'] == true).length;
    final fleetPercent = totalEmployees > 0
        ? (activeEmployees / totalEmployees).clamp(0.0, 1.0)
        : 1.0;

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
                      // 1. Stitch Hero Welcome Banner (Deep Navy + Gold Accent)
                      _buildHeroCard(authUser, walletText, l10n),
                      const SizedBox(height: AppSpacing.lg),

                      // 2. Stitch Metrics Bento Grid
                      _buildMetricsGrid(
                        ownerProvider,
                        activeEmployees,
                        totalEmployees,
                        fleetPercent,
                        l10n,
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // 3. Compact Inline Summary Bar
                      _buildSummaryBar(subText, subColor, l10n),
                      const SizedBox(height: AppSpacing.lg),

                      // 4. Quick Access Management Cards (Wallet & Services & Config)
                      _buildQuickAccessCards(l10n),
                      const SizedBox(height: AppSpacing.lg),

                      // 5. Urgent Actions Split (Stitch Reference)
                      _buildUrgentActions(l10n),
                      const SizedBox(height: AppSpacing.lg),

                      // 6. Fleet Map / Active Zone Preview
                      _buildFleetMapPreview(authUser, auth, l10n),
                      const SizedBox(height: AppSpacing.lg),

                      // 7. Service Reputation
                      _buildReputationSection(auth, l10n),

                      // 8. Active Owner Orders
                      _buildOwnerJobsSection(ownerProvider, auth, l10n),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    UserProfile authUser,
    String walletText,
    AppLocalizations l10n,
  ) {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      topAccentColor: AppColors.secondary,
      topAccentHeight: 3,
      color: AppColors.primaryContainer,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThemedPanel(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  width: 48,
                  height: 48,
                  child: const Center(
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.secondary,
                      size: 26,
                    ),
                  )),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.ownerHomeWelcomeUser(
                        authUser.username.isNotEmpty
                            ? authUser.username
                            : authUser.email,
                      ),
                      style: AppTypography.headlineLgMobile.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.ownerHomeTenantId(authUser.id),
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onPrimaryContainer,
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
                child: ThemedPanel(
                    color: AppColors.secondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: AppColors.secondary,
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.account_balance_wallet,
                          color: AppColors.secondary,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          walletText,
                          style: AppTypography.labelLg.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(
    OwnerProvider ownerProvider,
    int activeEmployees,
    int totalEmployees,
    double fleetPercent,
    AppLocalizations l10n,
  ) {
    return Row(
      children: [
        // Metric Card 1: Active Jobs
        Expanded(
          child: ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppTypography.uppercaseLabel(l10n.ownerHomeOwnerJobs),
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Icon(
                      Icons.assignment_outlined,
                      color: AppColors.outline,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${ownerProvider.ownerJobs.length}',
                  style: AppTypography.headlineLgMobile.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    const Icon(
                      Icons.trending_up,
                      color: AppColors.success,
                      size: 14,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      l10n.jobsTrendChipMock,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),

        // Metric Card 2: Active Fleet
        Expanded(
          child: ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.activeFleetMetricLabel,
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Icon(
                      Icons.local_shipping_outlined,
                      color: AppColors.outline,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$activeEmployees / $totalEmployees',
                  style: AppTypography.headlineLgMobile.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: AppRadius.smBorder,
                  child: LinearProgressIndicator(
                    value: fleetPercent,
                    backgroundColor: AppColors.surfaceContainerHighest,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.secondary,
                    ),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(
    String subText,
    Color subColor,
    AppLocalizations l10n,
  ) {
    return ThemedCard(
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
                    builder: (context) => const SubscriptionScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
                    const SizedBox(height: AppSpacing.xxs),
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
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
          ),

          // Employee Roster Item
          Expanded(
            child: InkWell(
              key: const Key('owner_dashboard_employees_chip'),
              onTap: () {
                onTabTapped(1); // Switch to Employees tab
              },
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
                    const SizedBox(height: AppSpacing.xxs),
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
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
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
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
                    const SizedBox(height: AppSpacing.xxs),
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
    );
  }

  Widget _buildQuickAccessCards(AppLocalizations l10n) {
    return Column(
      children: [
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
                      ThemedPanel(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: const Icon(
                            Icons.account_balance_wallet,
                            color: AppColors.primary,
                            size: 24,
                          )),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.ownerHomeMyWallet,
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              l10n.ownerHomeWalletSub,
                              style: AppTypography.labelMd.copyWith(
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
                      ThemedPanel(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: const Icon(
                            Icons.storefront,
                            color: AppColors.secondary,
                            size: 24,
                          )),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.ownerHomeServices,
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              l10n.ownerHomeServicesSub,
                              style: AppTypography.labelMd.copyWith(
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
        const SizedBox(height: AppSpacing.md),
        InkWell(
          key: const Key('owner_dashboard_config_card'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const OwnerConfigurationScreen(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ThemedCard(
            padding: AppSpacing.md,
            child: Row(
              children: [
                ThemedPanel(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: const Icon(
                      Icons.business_outlined,
                      color: AppColors.secondary,
                      size: 24,
                    )),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.ownerConfigTitle,
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        l10n.quickConfigSubtitle,
                        style: AppTypography.labelMd.copyWith(
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
      ],
    );
  }

  Widget _buildUrgentActions(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThemedSectionHeader(title: l10n.urgentActionsHeader),
        const SizedBox(height: AppSpacing.sm),
        ThemedCard(
          padding: AppSpacing.md,
          child: Column(
            children: [
              // Action 1: Vehicle Maintenance / Fleet Alert
              Row(
                children: [
                  const ThemedPanel(
                      color: AppColors.errorContainer,
                      shape: BoxShape.circle,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.onErrorContainer,
                        size: 22,
                      )),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.vehicleMaintenanceTitle,
                          style: AppTypography.titleMd.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          l10n.vehicleMaintenanceDesc,
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // A8/C1-F1: shared button (inherits A4 in-flight lock).
                  SecondaryButton(
                    text: l10n.scheduleAction,
                    isFullWidth: false,
                    onPressed: () {
                      onTabTapped(1); // Switch to Employees / Fleet tab
                    },
                  ),
                ],
              ),
              const Divider(
                height: AppSpacing.lg,
                color: AppColors.outlineVariant,
              ),
              // Action 2: Pending Reconciliations
              Row(
                children: [
                  ThemedPanel(
                      color: AppColors.secondary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.person_add_outlined,
                        color: AppColors.secondary,
                        size: 22,
                      )),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.pendingReconciliationsHeader,
                          style: AppTypography.titleMd.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          l10n.reconciliationPendingDesc,
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // A8/C1-F1: shared outlined button (inherits A4 lock).
                  SecondaryButton(
                    text: l10n.reviewAction,
                    isOutlined: true,
                    isFullWidth: false,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              const OwnerReconciliationQueueScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFleetMapPreview(
    UserProfile authUser,
    AuthProvider auth,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThemedSectionHeader(title: l10n.fleetOverviewHeader),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => OwnerFleetMapScreen(
                  ownerId: authUser.id,
                  token: auth.token,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ThemedCard(
            padding: 0,
            child: ThemedPanel(
                borderRadius: BorderRadius.circular(AppRadius.md),
                color: AppColors.primaryContainer,
                height: 140,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: Icon(
                          Icons.map_outlined,
                          size: 64,
                          color: AppColors.onPrimaryContainer
                              .withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.md,
                      bottom: AppSpacing.md,
                      right: AppSpacing.md,
                      child: ThemedPanel(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.scrim.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const ThemedPanel(
                                      color: AppColors.secondary,
                                      shape: BoxShape.circle,
                                      width: 10,
                                      height: 10),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    l10n.activeZoneLabel,
                                    style: AppTypography.bodyMd.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                l10n.downtownCoverageLabel,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )),
                    ),
                  ],
                )),
          ),
        ),
      ],
    );
  }

  Widget _buildReputationSection(AuthProvider auth, AppLocalizations l10n) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Provider.of<MarketplaceProvider>(context, listen: false)
          .fetchRatings(auth.token!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: SkeletonLoader(
              height: 70,
              borderRadius: AppRadius.md,
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!;
        final double avg = (data['average_rating'] as num?)?.toDouble() ?? 0.0;
        final int count = (data['count'] as num?)?.toInt() ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThemedSectionHeader(
              title: l10n.ownerHomeServiceReputation,
            ),
            const SizedBox(height: AppSpacing.sm),
            RatingSummaryCard(averageRating: avg, ratingCount: count),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }

  Widget _buildOwnerJobsSection(
    OwnerProvider ownerProvider,
    AuthProvider auth,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              actionText: l10n.manageServicesAction,
              onActionPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ServiceScreen()),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ownerProvider.ownerJobs.length,
            itemBuilder: (context, index) {
              final job = ownerProvider.ownerJobs[index];
              final canCancel =
                  job.status == 'pending' || job.status == 'active';
              final displayJobId = job.id.length > 8
                  ? AppTypography.uppercaseLabel(job.id.substring(0, 8))
                  : AppTypography.uppercaseLabel(job.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ThemedCard(
                  padding: AppSpacing.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "#QD-$displayJobId",
                            style: AppTypography.titleMd.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          StatusBadge(status: job.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.ownerHomeJobId(job.id),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.outline,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.ownerHomePaymentInfo(
                          AppTypography.uppercaseLabel(job.paymentMethod),
                          job.lockedEscrowAmount != null
                              ? ' (\$${job.lockedEscrowAmount!.toStringAsFixed(2)})'
                              : '',
                        ),
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      if (canCancel) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: SecondaryButton(
                            key: Key('cancel_owner_job_button_${job.id}'),
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
                                    final isNonCod =
                                        job.paymentMethod.toLowerCase() !=
                                            'cod';
                                    final msg = isNonCod
                                        ? l10n
                                            .ownerHomeJobCancelledEscrowRefunded
                                        : l10n.ownerHomeJobCancelled;
                                    ThemedSnackBar.showSuccess(context, msg);
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
    );
  }

  Widget _buildNonOwnerShell(UserProfile user, AppLocalizations l10n) {
    return AppShell(
      backgroundColor: AppColors.scaffoldBackground,
      appBarBackgroundColor: Colors.transparent,
      appBarForegroundColor: Theme.of(context).colorScheme.onSurface,
      leading: DashboardScreenTemplate.brandLogo(),
      showBackButton: false,
      title: l10n.quickDeliveryDashboard,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.ownerHomeWelcomeUser(
                user.username.isNotEmpty ? user.username : user.email,
              ),
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
                    l10n.ownerHomeLabelRole,
                    AppTypography.uppercaseLabel(user.role),
                  ),
                ],
              ),
            ),
          ],
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
