import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../models/job.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/auth_provider.dart';
import '../providers/employee_jobs_provider.dart';
import '../providers/employee_location_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/confirm_action_dialog.dart';
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
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'kyc_document_upload_screen.dart';

class EmployeeJobsScreen extends StatefulWidget {
  const EmployeeJobsScreen({super.key});

  @override
  State<EmployeeJobsScreen> createState() => _EmployeeJobsScreenState();
}

class _EmployeeJobsScreenState extends State<EmployeeJobsScreen> {
  final _actionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSimulating = false;
  String? _completingJobId;
  String? _completeError;
  String? _completeErrorJobId;

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
  void deactivate() {
    Provider.of<EmployeeLocationProvider>(context, listen: false)
        .stopTracking(notify: false);
    super.deactivate();
  }

  @override
  void dispose() {
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _refreshJobs() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token != null) {
      final jobsProvider =
          Provider.of<EmployeeJobsProvider>(context, listen: false);
      await jobsProvider.fetchAssignedJobs(auth.token!);
      if (mounted) {
        final locationProvider =
            Provider.of<EmployeeLocationProvider>(context, listen: false);
        final activeJobs = jobsProvider.jobs
            .where((j) => j.status.toLowerCase().trim() == 'active')
            .toList();
        if (activeJobs.isNotEmpty) {
          await locationProvider.startTracking(
              activeJobs.first.id, auth.token!);
        } else {
          await locationProvider.stopTracking();
        }
      }
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
        final l10n = AppLocalizations.of(context)!;
        _actionController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.actionLoggedSuccess(action)),
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

  Future<void> _confirmAndCompleteJob(Job job) async {
    final provider = Provider.of<EmployeeJobsProvider>(context, listen: false);
    final isCod = job.paymentMethod.toLowerCase().trim() == 'cod';

    final String title =
        isCod ? "Confirm Cash Collection & Complete" : "Complete Job";

    final String message = isCod
        ? "Confirm you have physically collected the cash payment of \$${job.lockedEscrowAmount?.toStringAsFixed(2) ?? '0.00'} (COD) from the customer.\n\nThis will deduct the platform fee from the owner's wallet and mark Job #${job.id} as completed."
        : "Are you sure you want to mark Job #${job.id} as completed?";

    final String confirmLabel =
        isCod ? "Confirm Cash Collected & Complete" : "Complete Job";

    final IconData icon =
        isCod ? Icons.payments_outlined : Icons.check_circle_outline;

    final confirmed = await ConfirmActionDialog.show(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: "Cancel",
      icon: icon,
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _completingJobId = job.id;
      _completeError = null;
      _completeErrorJobId = null;
    });

    try {
      await provider.completeJob(job.id, cashCollected: isCod);
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        Provider.of<EmployeeLocationProvider>(context, listen: false)
            .stopTracking();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.jobMarkedCompletedSuccess),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error completing job: $e');
      if (mounted) {
        setState(() {
          _completeError = friendlyErrorMessage(e);
          _completeErrorJobId = job.id;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _completingJobId = null;
        });
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
    final l10n = AppLocalizations.of(context)!;
    final auth = Provider.of<AuthProvider>(context);
    final jobsProvider = Provider.of<EmployeeJobsProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l10n.employeeJobsTitle,
          style: AppTypography.titleMd.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh,
                color: Theme.of(context).colorScheme.onSurface),
            tooltip: "Refresh Jobs",
            onPressed: _refreshJobs,
          ),
          IconButton(
            key: const Key('employee_verification_button'),
            icon: Icon(Icons.verified_user_outlined,
                color: Theme.of(context).colorScheme.onSurface),
            tooltip: "Verification Documents",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const KycDocumentUploadScreen(),
                ),
              );
            },
          ),
          _buildNotificationBell(context),
          IconButton(
            key: const Key('settings_button'),
            icon: Icon(Icons.settings_outlined,
                color: Theme.of(context).colorScheme.onSurface),
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
    return Consumer<EmployeeLocationProvider>(
      builder: (context, locationProvider, child) {
        final isTracking =
            locationProvider.status == LocationSharingStatus.tracking;
        final isDenied = locationProvider.status ==
                LocationSharingStatus.permissionDenied ||
            locationProvider.status == LocationSharingStatus.serviceDisabled;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.08),
                AppColors.surface,
              ],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            borderRadius: AppRadius.lgBorder,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isTracking || isDenied)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: isTracking
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: AppRadius.smBorder,
                      border: Border.all(
                        color: isTracking
                            ? AppColors.success.withValues(alpha: 0.4)
                            : AppColors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isTracking
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          isTracking ? "GPS Live" : "GPS Off",
                          style: AppTypography.labelMd.copyWith(
                            color: isTracking
                                ? AppColors.success
                                : AppColors.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionSimulatorCard() {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      padding: AppSpacing.lg,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smBorder,
                  ),
                  child: const Icon(
                    Icons.bolt_outlined,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    "Employee Action Simulator",
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Log service events directly into the tenant audit trail.",
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
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
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: _suggestions.map((suggestion) {
                final isSelected = _actionController.text.trim() == suggestion;
                return ChoiceChip(
                  label: Text(suggestion),
                  selected: isSelected,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  backgroundColor: AppColors.surface,
                  labelStyle: AppTypography.labelMd.copyWith(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.outlineVariant,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      _actionController.text = suggestion;
                    });
                  },
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
        borderRadius: AppRadius.lg,
        padding: AppSpacing.xl,
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
    final isActive = job.status.toLowerCase().trim() == 'active';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ThemedCard(
        borderRadius: AppRadius.lg,
        padding: AppSpacing.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.smBorder,
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          "Job #${job.id}",
                          style: AppTypography.titleMd.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: job.status),
              ],
            ),
            const Divider(
              height: AppSpacing.lg,
              color: AppColors.outlineVariant,
            ),
            // Primary Info: Destination
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: AppRadius.smBorder,
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Destination Coordinates",
                          style: AppTypography.labelLg.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          "Lat: ${job.location.latitude.toStringAsFixed(6)}, Lon: ${job.location.longitude.toStringAsFixed(6)}",
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Subordinate Info Badges / Chips
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _buildSubordinateChip(
                  Icons.person_outline,
                  "Customer",
                  job.userId,
                ),
                _buildSubordinateChip(
                  Icons.payment_outlined,
                  "Payment",
                  job.paymentMethod.toUpperCase(),
                ),
                if (job.lockedEscrowAmount != null &&
                    job.lockedEscrowAmount! > 0)
                  _buildSubordinateChip(
                    Icons.lock_clock_outlined,
                    "Escrow",
                    "${job.lockedEscrowAmount!.toStringAsFixed(2)} Credits",
                  ),
              ],
            ),
            if (job.cancellationReason != null &&
                job.cancellationReason!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.defaultBorder,
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Text(
                  "Cancellation Reason: ${job.cancellationReason}",
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
            if (isActive) ...[
              Consumer<EmployeeLocationProvider>(
                builder: (context, locationProvider, child) {
                  if (locationProvider.status ==
                          LocationSharingStatus.permissionDenied ||
                      locationProvider.status ==
                          LocationSharingStatus.serviceDisabled) {
                    return Container(
                      key: const Key('location_permission_denied_banner'),
                      margin: const EdgeInsets.only(top: AppSpacing.sm),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: AppRadius.defaultBorder,
                        border: Border.all(color: AppColors.warning),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_off_outlined,
                                  color: AppColors.warning, size: 20),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                "Location Permission Required",
                                style: AppTypography.bodyMd.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            "Location sharing is required to share your live delivery progress with the customer.",
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SecondaryButton(
                            key: const Key('open_app_settings_button'),
                            text: "Open App Settings",
                            icon: Icons.settings_outlined,
                            isOutlined: true,
                            onPressed: () {
                              Geolocator.openAppSettings();
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  if (locationProvider.status ==
                      LocationSharingStatus.tracking) {
                    return Container(
                      key: const Key('location_sharing_indicator'),
                      margin: const EdgeInsets.only(top: AppSpacing.sm),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: AppRadius.smBorder,
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            "Sharing live location",
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (locationProvider.status == LocationSharingStatus.error &&
                      locationProvider.error != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child:
                          ThemedErrorBanner(message: locationProvider.error!),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
              if (_completeErrorJobId == job.id && _completeError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ThemedErrorBanner(message: _completeError!),
              ],
            ],
            const SizedBox(height: AppSpacing.lg),
            // Action buttons bar
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    key: Key('employee_chat_button_${job.id}'),
                    text: "Chat",
                    icon: Icons.chat_outlined,
                    isOutlined: true,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            jobId: job.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      key: Key('complete_job_button_${job.id}'),
                      text: "Complete Job",
                      icon: Icons.check_circle_outline,
                      isLoading: _completingJobId == job.id,
                      onPressed: _completingJobId != null
                          ? null
                          : () => _confirmAndCompleteJob(job),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubordinateChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.smBorder,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(
            "$label: ",
            style: AppTypography.labelLg.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: AppTypography.labelLg.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
