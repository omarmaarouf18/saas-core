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
import 'login_screen.dart';
import 'wallet_screen.dart';
import 'employee_screen.dart';
import 'service_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'subscription_screen.dart';

import 'owner_history_screen.dart';
import 'employee_jobs_screen.dart';
import 'kyc_document_upload_screen.dart';
import 'customer_home_screen.dart';
import 'kyb_kye_review_screen.dart';
import 'owner_reconciliation_queue_screen.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/rating_summary_card.dart';
import '../widgets/cancel_job_dialog.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';

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

  String _getTabTitle(int index) {
    switch (index) {
      case 0:
        return "Quick Delivery Owner Dashboard";
      case 1:
        return "Manage Workers";
      case 2:
        return "Settings";
      case 3:
        return "History & Audit Logs";
      default:
        return "Quick Delivery Owner Dashboard";
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
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications),
              tooltip: 'Notifications',
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
    final status = user.effectiveKycStatus;
    final isKycPending = status == "pending_super_admin_approval";
    final isKycRejected = status == "rejected";
    final isKycUnverified =
        status.isEmpty || status == "none" || status == "unverified";

    if (!isOwner) {
      if (user.role == 'employee') {
        return const EmployeeJobsScreen();
      }
      if (user.role == 'user') {
        return const CustomerHomeScreen();
      }
      if (user.role == 'reviewer' || user.role == 'admin') {
        return const KybKyeReviewScreen();
      }
      // Non-owner basic dashboard
      return Scaffold(
        backgroundColor: AppColors.scaffoldBackground,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: Text(l10n.quickDeliveryDashboard),
          foregroundColor: AppColors.onPrimary,
          actions: [
            if (user.role == 'reviewer' || user.role == 'admin')
              IconButton(
                key: const Key('reviewer_queue_button'),
                icon: const Icon(Icons.fact_check_outlined),
                tooltip: "KYB/KYE Review Queue",
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const KybKyeReviewScreen(),
                    ),
                  );
                },
              ),
            _buildNotificationBell(context),
            IconButton(
              key: const Key('settings_button'),
              icon: const Icon(Icons.settings_outlined),
              tooltip: "Settings",
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
                "Welcome back, ${user.username.isNotEmpty ? user.username : user.email}!",
                style: AppTypography.headlineLgMobile.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                "Account ID: ${user.id}",
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
                    const ThemedSectionHeader(title: "Profile Information"),
                    const Divider(
                      height: AppSpacing.lg,
                      color: AppColors.outlineVariant,
                    ),
                    _buildDetailRow("Username", user.username),
                    _buildDetailRow("Email", user.email),
                    _buildDetailRow("Role", user.role.toUpperCase()),
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
        backgroundColor: AppColors.primary,
        title: Text(_getTabTitle(_currentIndex)),
        foregroundColor: AppColors.onPrimary,
        actions: [
          if (user.role == 'reviewer' || user.role == 'admin')
            IconButton(
              key: const Key('reviewer_queue_button'),
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: "KYB/KYE Review Queue",
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const KybKyeReviewScreen(),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: "Verification Documents",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const KycDocumentUploadScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.gavel_outlined),
            tooltip: "Escrow Reconciliation",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const OwnerReconciliationQueueScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Data",
            onPressed: _refreshData,
          ),
          _buildNotificationBell(context),
          IconButton(
            key: const Key('settings_button'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Settings",
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isKycPending)
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const KycDocumentUploadScreen(),
                  ),
                );
              },
              child: Container(
                color: AppColors.warning,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.onPrimary, size: 28),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        "KYC Pending Approval: Your account documents are being reviewed. Click to view submitted files.",
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios,
                        color: AppColors.onPrimary, size: 16),
                  ],
                ),
              ),
            )
          else if (isKycUnverified || isKycRejected)
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const KycDocumentUploadScreen(),
                  ),
                );
              },
              child: Container(
                color: isKycRejected ? AppColors.error : AppColors.secondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      isKycRejected
                          ? Icons.error_outline
                          : Icons.shield_outlined,
                      color: AppColors.onPrimary,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        isKycRejected
                            ? "Verification Rejected: Please tap here to re-upload your verification documents."
                            : "Account Unverified: Upload your KYB verification documents to activate your account.",
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios,
                        color: AppColors.onPrimary, size: 16),
                  ],
                ),
              ),
            ),
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
                    ? const SettingsScreen(isEmbeddedInTab: true)
                    : const SizedBox.shrink(),
                _visitedTabs.contains(3)
                    ? const OwnerHistoryScreen(isEmbeddedInTab: true)
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
        destinations: const [
          NavigationDestination(
            key: Key('owner_nav_tab_home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            key: Key('owner_nav_tab_employees'),
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Employees',
          ),
          NavigationDestination(
            key: Key('owner_nav_tab_settings'),
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
          NavigationDestination(
            key: Key('owner_nav_tab_history'),
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context, authUser) {
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    final walletText = ownerProvider.isLoading
        ? "..."
        : "${ownerProvider.walletBalance.toStringAsFixed(2)} Credits";

    final subText = ownerProvider.isLoading
        ? "..."
        : ownerProvider.subscriptionTier.toUpperCase().replaceAll('_', ' ');

    final subColor = ownerProvider.subscriptionTier == "paid"
        ? AppColors.success
        : (ownerProvider.subscriptionTier == "pending_payment"
            ? const Color(0xFF1D4ED8)
            : AppColors.warning);

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
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
                          "Welcome back, ${authUser.username.isNotEmpty ? authUser.username : authUser.email}!",
                          style: AppTypography.headlineLgMobile.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          "Tenant Owner ID: ${authUser.id}",
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
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
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
                              builder: (context) => const SubscriptionScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(AppRadius.sm),
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
                                "Subscription",
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
                                "Roster",
                                style: AppTypography.labelLg.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Employees",
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
                                "Escrow",
                                style: AppTypography.labelLg.copyWith(
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Review Queue",
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
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "My Wallet",
                                    style: AppTypography.titleMd.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Ledger & balance",
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
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.secondary.withValues(alpha: 0.1),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Services",
                                    style: AppTypography.titleMd.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Rates & config",
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

              const SizedBox(height: AppSpacing.lg),
              FutureBuilder<Map<String, dynamic>>(
                future: Provider.of<MarketplaceProvider>(context, listen: false)
                    .fetchRatings(auth.token!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
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
                      (data['average_rating'] as num?)?.toDouble() ?? 0.0;
                  final int count = (data['count'] as num?)?.toInt() ?? 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ThemedSectionHeader(
                        title: "Your Service Reputation",
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      RatingSummaryCard(averageRating: avg, ratingCount: count),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  );
                },
              ),

              const SizedBox(height: AppSpacing.xl),
              const ThemedSectionHeader(title: "Owner Jobs"),
              const SizedBox(height: AppSpacing.sm),

              if (ownerProvider.ownerJobs.isEmpty)
                const ThemedCard(
                  borderRadius: AppRadius.md,
                  padding: AppSpacing.lg,
                  child: ThemedEmptyState(
                    icon: Icons.assignment_outlined,
                    title: "No Owner Jobs Found",
                    description:
                        "You currently have no jobs registered under your tenant account.",
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
                                  "Job #${job.id}",
                                  style: AppTypography.titleMd.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                StatusBadge(status: job.status),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              "Payment: ${job.paymentMethod.toUpperCase()}${job.lockedEscrowAmount != null ? ' (\$${job.lockedEscrowAmount!.toStringAsFixed(2)})' : ''}",
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            if (canCancel) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Align(
                                alignment: Alignment.centerRight,
                                child: SecondaryButton(
                                  key: Key('cancel_owner_job_button_${job.id}'),
                                  text: "Cancel Job",
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
                                              ? "Job cancelled successfully. Escrow refunded to wallet."
                                              : "Job cancelled successfully.";
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(msg),
                                              backgroundColor:
                                                  AppColors.success,
                                            ),
                                          );
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
