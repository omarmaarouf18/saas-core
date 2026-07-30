import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/stat_card.dart';
import 'login_screen.dart';
import 'wallet_screen.dart';
import 'employee_screen.dart';
import 'service_screen.dart';
import 'notifications_screen.dart';
import 'subscription_screen.dart';

import 'employee_jobs_screen.dart';
import 'kyc_document_upload_screen.dart';
import 'customer_marketplace_screen.dart';
import 'owner_reconciliation_queue_screen.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/rating_summary_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.fetchUserProfile();
    if (!mounted) return;
    if (auth.user?.role == 'owner') {
      await Provider.of<OwnerProvider>(context, listen: false)
          .fetchDashboardData(auth.token!);
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
        return const CustomerMarketplaceScreen();
      }
      // Non-owner basic dashboard
      return Scaffold(
        backgroundColor: AppColors.scaffoldBackground,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text("Quick Delivery Dashboard"),
          foregroundColor: AppColors.onPrimary,
          actions: [
            _buildNotificationBell(context),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: "Logout",
              onPressed: () async {
                await auth.logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                }
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
        title: const Text("Quick Delivery Owner Dashboard"),
        foregroundColor: AppColors.onPrimary,
        actions: [
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
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
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
                _buildDashboardTab(context, user),
                const WalletScreen(),
                const EmployeeScreen(),
                const ServiceScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.outline,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: "Dashboard",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: "Wallet",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: "Employees",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: "Services",
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context, authUser) {
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
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
            const SizedBox(height: AppSpacing.base),
            Text(
              "Tenant Owner ID: ${authUser.id}",
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Dashboard Metrics Grid
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.3,
              children: [
                _buildMetricCard(
                  title: "Wallet Balance",
                  value: ownerProvider.isLoading
                      ? "..."
                      : "${ownerProvider.walletBalance.toStringAsFixed(2)} Credits",
                  icon: Icons.account_balance_wallet_outlined,
                  color: AppColors.primary,
                ),
                _buildMetricCard(
                  title: "Subscription Tier",
                  value: ownerProvider.isLoading
                      ? "..."
                      : ownerProvider.subscriptionTier
                          .toUpperCase()
                          .replaceAll('_', ' '),
                  icon: Icons.card_membership_outlined,
                  color: ownerProvider.subscriptionTier == "paid"
                      ? AppColors.success
                      : (ownerProvider.subscriptionTier == "pending_payment"
                          ? const Color(0xFF2196F3)
                          : AppColors.warning),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SubscriptionScreen(),
                      ),
                    );
                  },
                ),
                _buildMetricCard(
                  title: "Employee Count",
                  value: "0",
                  subtitle: "N/A (No List API)",
                  icon: Icons.people_outline,
                  color: AppColors.outline,
                ),
                _buildMetricCard(
                  title: "Escrow Review",
                  value: "Queue",
                  subtitle: "Flagged Jobs",
                  icon: Icons.gavel_outlined,
                  color: AppColors.secondary,
                  onTap: () {
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
            const ThemedSectionHeader(title: "Active Jobs"),
            const SizedBox(height: AppSpacing.sm),

            // Active Jobs placeholder stating the API gap
            const ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              child: ThemedEmptyState(
                icon: Icons.assignment_late_outlined,
                title: "No Active Jobs Found",
                description:
                    "Active job tracking is active on the platform, but the user-service does not currently expose an API endpoint to list active jobs for owners.",
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return StatCard(
      label: title,
      value: value,
      trend: subtitle,
      icon: icon,
      iconColor: color,
      onTap: onTap,
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
