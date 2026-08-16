import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/employee_jobs_provider.dart';
import '../providers/notifications_provider.dart';
import 'employee_jobs_screen.dart';
import 'employee_history_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'kyc_document_upload_screen.dart';

class EmployeeHomeScreen extends StatefulWidget {
  final int initialTabIndex;
  const EmployeeHomeScreen({super.key, this.initialTabIndex = 0});

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  late int _currentIndex;
  late Set<int> _visitedTabs;

  NotificationsProvider? _notificationsProvider;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _visitedTabs = {_currentIndex};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
      if (mounted) {
        _notificationsProvider =
            Provider.of<NotificationsProvider>(context, listen: false);
        _notificationsProvider?.addListener(_onNotificationsChanged);
      }
    });
  }

  @override
  void dispose() {
    _notificationsProvider?.removeListener(_onNotificationsChanged);
    super.dispose();
  }

  void _onNotificationsChanged() {
    if (!mounted || _notificationsProvider == null) return;
    final notifs = _notificationsProvider!.notifications;
    if (notifs.isNotEmpty && notifs.first.type == 'job_alert') {
      _refreshData();
    }
  }

  @override
  void didUpdateWidget(EmployeeHomeScreen oldWidget) {
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
    final l10n = context.l10n;
    switch (index) {
      case 0:
        return l10n.employeeJobsTitle;
      case 1:
        return l10n.ownerHistoryTitle;
      case 2:
        return l10n.settingsTitle;
      default:
        return l10n.employeeJobsTitle;
    }
  }

  Future<void> _refreshData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token != null) {
      final jobsProvider =
          Provider.of<EmployeeJobsProvider>(context, listen: false);
      await jobsProvider.fetchAssignedJobs(auth.token!);
    }
  }

  Widget _buildNotificationBell(BuildContext context) {
    final l10n = context.l10n;
    return Consumer<NotificationsProvider>(
      builder: (context, provider, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications),
              tooltip: l10n.tooltipNotifications,
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
          _getTabTitle(context, _currentIndex),
          style: AppTypography.titleMd.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            key: const Key('employee_verification_button'),
            icon: Icon(Icons.verified_user_outlined,
                color: Theme.of(context).colorScheme.onSurface),
            tooltip: l10n.employeeJobsTooltipVerification,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const KycDocumentUploadScreen(),
                ),
              );
            },
          ),
          _buildNotificationBell(context),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _visitedTabs.contains(0)
              ? const EmployeeJobsScreen(isEmbeddedInTab: true)
              : const SizedBox.shrink(),
          _visitedTabs.contains(1)
              ? const EmployeeHistoryScreen(isEmbeddedInTab: true)
              : const SizedBox.shrink(),
          _visitedTabs.contains(2)
              ? const SettingsScreen(isEmbeddedInTab: true)
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('employee_bottom_navigation_bar'),
        selectedIndex: _currentIndex,
        onDestinationSelected: onTabTapped,
        destinations: [
          NavigationDestination(
            key: const Key('employee_nav_tab_home'),
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: l10n.employeeJobsTitle,
          ),
          NavigationDestination(
            key: const Key('employee_nav_tab_history'),
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l10n.ownerHistoryTitle,
          ),
          NavigationDestination(
            key: const Key('employee_nav_tab_settings'),
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.settingsTitle,
          ),
        ],
      ),
    );
  }
}
