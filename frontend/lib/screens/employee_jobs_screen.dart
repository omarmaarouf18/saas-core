import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/employee_jobs_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_text_field.dart';
import 'notifications_screen.dart';
import '../utils/logout_helper.dart';

class EmployeeJobsScreen extends StatefulWidget {
  const EmployeeJobsScreen({super.key});

  @override
  State<EmployeeJobsScreen> createState() => _EmployeeJobsScreenState();
}

class _EmployeeJobsScreenState extends State<EmployeeJobsScreen> {
  final _actionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSimulating = false;

  final List<String> _suggestions = [
    "Arrived at Pickup",
    "Job in Route",
    "Arrived at Destination",
    "Job Completed",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshJobs();
    });
  }

  @override
  void dispose() {
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _refreshJobs() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token != null) {
      await Provider.of<EmployeeJobsProvider>(context, listen: false)
          .fetchAssignedJobs(auth.token!);
    }
  }

  Future<void> _submitAction() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<EmployeeJobsProvider>(context, listen: false);
    final email = auth.user?.email ?? '';
    final action = _actionController.text.trim();

    setState(() => _isSimulating = true);

    try {
      await provider.simulateAction(email: email, action: action);
      if (mounted) {
        _actionController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Action logged successfully: \"$action\""),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error simulating action: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSimulating = false);
      }
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
    final jobsProvider = Provider.of<EmployeeJobsProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: const Text("Employee Jobs Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Jobs",
            onPressed: _refreshJobs,
          ),
          _buildNotificationBell(context),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () async {
              await logoutAndClearProviders(context);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshJobs,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(auth.user?.username.isNotEmpty == true
                  ? auth.user!.username
                  : (auth.user?.email ?? '')),
              const SizedBox(height: AppSpacing.lg),
              _buildActionSimulatorCard(),
              const SizedBox(height: AppSpacing.xl),
              const ThemedSectionHeader(title: "Your Assigned Jobs"),
              const SizedBox(height: AppSpacing.sm),
              if (jobsProvider.isLoading && jobsProvider.jobs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40.0),
                  child: ThemedLoadingIndicator(
                      message: "Loading assigned jobs..."),
                )
              else if (jobsProvider.error != null && jobsProvider.jobs.isEmpty)
                ThemedErrorBanner(message: jobsProvider.error!)
              else
                _buildJobsList(jobsProvider.jobs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String displayName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Welcome back!",
          style: AppTypography.headlineLgMobile.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          "Logged in as: $displayName",
          style: AppTypography.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActionSimulatorCard() {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ThemedSectionHeader(
              title: "Employee Action Simulator",
              subtitle:
                  "Log service events directly into the tenant audit trail.",
            ),
            const Divider(
              height: AppSpacing.lg,
              color: AppColors.outlineVariant,
            ),
            ThemedTextField(
              controller: _actionController,
              labelText: "Simulation Action Text",
              hintText: "e.g., Arrived at Pickup, Job in Route",
              prefixIcon: const Icon(Icons.run_circle_outlined,
                  color: AppColors.outline),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Please enter or select an action to simulate";
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.base,
              runSpacing: AppSpacing.xs,
              children: _suggestions.map((suggestion) {
                return SizedBox(
                  width: 175,
                  height: 40,
                  child: SecondaryButton(
                    text: suggestion,
                    isOutlined: true,
                    onPressed: () {
                      setState(() {
                        _actionController.text = suggestion;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              onPressed: _isSimulating ? null : _submitAction,
              icon: Icons.send_outlined,
              text: "Simulate Action",
              isLoading: _isSimulating,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobsList(List<Job> jobs) {
    if (jobs.isEmpty) {
      return const ThemedCard(
        borderRadius: AppRadius.md,
        padding: AppSpacing.lg,
        child: ThemedEmptyState(
          icon: Icons.assignment_late_outlined,
          title: "No Jobs Assigned",
          description: "No jobs currently assigned to you.",
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: jobs.length,
      itemBuilder: (context, index) {
        final job = jobs[index];
        return _buildJobCard(job);
      },
    );
  }

  Widget _buildJobCard(Job job) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ThemedCard(
        borderRadius: AppRadius.md,
        padding: AppSpacing.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "Job ID: ${job.id}",
                    style: AppTypography.bodyMd.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusBadge(status: job.status),
              ],
            ),
            const Divider(
              height: AppSpacing.lg,
              color: AppColors.outlineVariant,
            ),
            _buildJobDetailRow(
              Icons.location_on_outlined,
              "Destination",
              "Lat: ${job.location.latitude.toStringAsFixed(6)}, Lon: ${job.location.longitude.toStringAsFixed(6)}",
            ),
            const SizedBox(height: AppSpacing.xs),
            _buildJobDetailRow(
              Icons.person_outline,
              "Customer ID",
              job.userId,
            ),
            const SizedBox(height: AppSpacing.xs),
            _buildJobDetailRow(
              Icons.payment_outlined,
              "Payment Method",
              job.paymentMethod.toUpperCase(),
            ),
            if (job.lockedEscrowAmount != null &&
                job.lockedEscrowAmount! > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              _buildJobDetailRow(
                Icons.lock_clock_outlined,
                "Escrow Locked",
                "${job.lockedEscrowAmount!.toStringAsFixed(2)} Credits",
              ),
            ],
            if (job.cancellationReason != null &&
                job.cancellationReason!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.defaultBorder,
                ),
                child: Text(
                  "Cancellation Reason: ${job.cancellationReason}",
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJobDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.outline),
        const SizedBox(width: AppSpacing.base),
        Text(
          "$label: ",
          style: AppTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
