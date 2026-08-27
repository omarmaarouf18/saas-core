import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/employee_jobs_provider.dart';
import '../providers/employee_location_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/primary_button.dart';
import '../widgets/route_timeline.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/app_shell.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_success_banner.dart';
import '../widgets/themed_text_field.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'kyc_document_upload_screen.dart';

class EmployeeJobsScreen extends StatefulWidget {
  final bool isEmbeddedInTab;
  const EmployeeJobsScreen({super.key, this.isEmbeddedInTab = false});

  @override
  State<EmployeeJobsScreen> createState() => _EmployeeJobsScreenState();
}

class _EmployeeJobsScreenState extends State<EmployeeJobsScreen> {
  final _actionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSimulating = false;
  // Declutter V2: subordinate info chips collapse behind a per-card toggle.
  final Set<String> _expandedJobCardIds = <String>{};
  String? _completingJobId;
  String? _completeError;
  String? _completeErrorJobId;

  List<String> _getSuggestions(AppLocalizations l10n) => [
        l10n.employeeJobsSuggestionArrivedPickup,
        l10n.employeeJobsSuggestionInRoute,
        l10n.employeeJobsSuggestionArrivedDestination,
        l10n.employeeJobsSuggestionCompleted,
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
        ThemedSnackBar.showSuccess(context, l10n.actionLoggedSuccess(action));
      }
    } catch (e) {
      debugPrint('Error simulating action: $e');
      if (mounted) {
        ThemedSnackBar.showError(
          context,
          friendlyErrorMessage(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSimulating = false);
      }
    }
  }

  Future<void> _confirmAndCompleteJob(Job job) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<EmployeeJobsProvider>(context, listen: false);
    final isCod = job.paymentMethod.toLowerCase().trim() == 'cod';

    final String title = isCod
        ? l10n.employeeJobsConfirmCodTitle
        : l10n.employeeJobsConfirmNonCodButton;

    final String message = isCod
        ? l10n.employeeJobsConfirmCodMessage(
            job.lockedEscrowAmount?.toStringAsFixed(2) ?? '0.00', job.id)
        : l10n.employeeJobsConfirmNonCodMessage(job.id);

    final String confirmLabel = isCod
        ? l10n.employeeJobsConfirmCodButton
        : l10n.employeeJobsConfirmNonCodButton;

    final IconData icon =
        isCod ? Icons.payments_outlined : Icons.check_circle_outline;

    final confirmed = await ConfirmActionDialog.show(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: l10n.cancel,
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
        ThemedSnackBar.showSuccess(context, l10n.jobMarkedCompletedSuccess);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = Provider.of<AuthProvider>(context);
    final jobsProvider = Provider.of<EmployeeJobsProvider>(context);

    final activeJobs = jobsProvider.jobs.where((j) {
      final status = j.status.toLowerCase().trim();
      return status != 'completed' && status != 'cancelled';
    }).toList();

    final bodyContent = RefreshIndicator(
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
            ThemedSectionHeader(title: l10n.employeeJobsSectionAssigned),
            const SizedBox(height: AppSpacing.sm),
            AnimatedSwitcher(
              duration: AppMotion.durationMedium,
              switchInCurve: AppMotion.curveStateChange,
              switchOutCurve: AppMotion.curveStateChange,
              child: (jobsProvider.isLoading && jobsProvider.jobs.isEmpty)
                  ? Column(
                      key: const ValueKey('employee_jobs_skeleton_list'),
                      children: List.generate(
                        3,
                        (index) => const EmployeeJobCardSkeleton(),
                      ),
                    )
                  : (jobsProvider.error != null && jobsProvider.jobs.isEmpty)
                      ? ThemedErrorBanner(
                          key: const ValueKey('employee_jobs_error'),
                          message: jobsProvider.error!,
                          onRetry: _refreshJobs,
                        )
                      : KeyedSubtree(
                          key: const ValueKey('employee_jobs_content'),
                          child: _buildJobsList(activeJobs),
                        ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _buildActionSimulatorCard(),
          ],
        ),
      ),
    );

    if (widget.isEmbeddedInTab) {
      return bodyContent;
    }

    return AppShell(
      title: l10n.employeeJobsTitle,
      actions: [
        IconButton(
          key: const Key('employee_verification_button'),
          icon: Icon(
            Icons.verified_user_outlined,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
        IconButton(
          key: const Key('settings_button'),
          icon: Icon(
            Icons.settings_outlined,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
      body: bodyContent,
    );
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

  Widget _buildHeader(String displayName) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<EmployeeLocationProvider>(
      builder: (context, locationProvider, child) {
        final isTracking =
            locationProvider.status == LocationSharingStatus.tracking;
        final isDenied = locationProvider.status ==
                LocationSharingStatus.permissionDenied ||
            locationProvider.status == LocationSharingStatus.serviceDisabled;

        return ThemedPanel(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.08),
                Theme.of(context).colorScheme.surface,
              ],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            borderRadius: AppRadius.lgBorder,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15),
            ),
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                ThemedPanel(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.badge_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    )),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.employeeJobsLoggedInAs(displayName),
                    style: AppTypography.titleMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isTracking || isDenied)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.8, end: 1.0),
                    duration: AppMotion.durationMedium,
                    curve: AppMotion.curveEntrance,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: child,
                      );
                    },
                    child: ThemedPanel(
                        color: isTracking
                            ? context.semanticColors.success
                                .withValues(alpha: 0.12)
                            : context.semanticColors.warning
                                .withValues(alpha: 0.12),
                        borderRadius: AppRadius.smBorder,
                        border: Border.all(
                          color: isTracking
                              ? context.semanticColors.success
                                  .withValues(alpha: 0.4)
                              : context.semanticColors.warning
                                  .withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ThemedPanel(
                                shape: BoxShape.circle,
                                color: isTracking
                                    ? context.semanticColors.success
                                    : context.semanticColors.warning,
                                width: 8,
                                height: 8),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              isTracking
                                  ? l10n.employeeJobsGpsLive
                                  : l10n.employeeJobsGpsOff,
                              style: AppTypography.labelMd.copyWith(
                                color: isTracking
                                    ? context.semanticColors.success
                                    : context.semanticColors.warning,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )),
                  ),
              ],
            ));
      },
    );
  }

  Widget _buildActionSimulatorCard() {
    final l10n = AppLocalizations.of(context)!;
    final suggestions = _getSuggestions(l10n);

    return ThemedCard(
      elevation: AppElevation.shadowLevel2List,
      borderRadius: AppRadius.lg,
      padding: AppSpacing.lg,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ThemedPanel(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smBorder,
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: const Icon(
                      Icons.bolt_outlined,
                      color: AppColors.secondary,
                      size: 20,
                    )),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.employeeJobsSimulatorTitle,
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.employeeJobsSimulatorDesc,
              style: AppTypography.bodyMd.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(
              height: AppSpacing.lg,
              color: AppColors.outlineVariant,
            ),
            ThemedTextField(
              controller: _actionController,
              labelText: l10n.employeeJobsSimulatorLabel,
              hintText: l10n.employeeJobsSimulatorHint,
              prefixIcon: const Icon(
                Icons.run_circle_outlined,
                color: AppColors.outline,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.employeeJobsSimulatorValidation;
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: suggestions.map((suggestion) {
                final isSelected = _actionController.text.trim() == suggestion;
                return ChoiceChip(
                  label: Text(suggestion),
                  selected: isSelected,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  labelStyle: AppTypography.labelMd.copyWith(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
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
              trailingIcon: Icons.arrow_forward,
              text: l10n.employeeJobsSimulateButton,
              isLoading: _isSimulating,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobsList(List<Job> jobs) {
    final l10n = AppLocalizations.of(context)!;
    if (jobs.isEmpty) {
      return ThemedCard(
        elevation: AppElevation.shadowLevel1List,
        borderRadius: AppRadius.lg,
        padding: AppSpacing.xl,
        child: ThemedEmptyState(
          icon: Icons.assignment_late_outlined,
          title: l10n.employeeJobsNoJobsTitle,
          description: l10n.employeeJobsNoJobsDesc,
          actionText: l10n.refreshJobsBtn,
          onActionPressed: _refreshJobs,
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
    final l10n = AppLocalizations.of(context)!;
    final isActive = job.status.toLowerCase().trim() == 'active';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ThemedCard(
        elevation: AppElevation.shadowLevel2List,
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
                      ThemedPanel(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.smBorder,
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: Icon(
                            Icons.local_shipping_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 18,
                          )),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          l10n.employeeJobsJobId(job.id),
                          style: AppTypography.titleMd.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
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
            // Route Timeline Card Module
            RouteTimeline(
              pickupAddress: l10n.pickupLocationLabel,
              pickupDetail: l10n.clientAddressConfirmedLabel,
              dropoffAddress: l10n.deliveryDestinationLabel,
              dropoffDetail: l10n.employeeJobsDestinationCoordinates,
              distanceText: job.lockedEscrowAmount != null
                  ? "${job.lockedEscrowAmount!.toStringAsFixed(0)} Credits"
                  : l10n.standardRouteLabel,
              timeText: isActive
                  ? l10n.inProgressLabel
                  : AppTypography.uppercaseLabel(job.status),
              cargoText: AppTypography.uppercaseLabel(job.paymentMethod),
            ),
            const SizedBox(height: AppSpacing.md),
            // Subordinate Info Badges / Chips — collapsed by default
            // (declutter V2); expand via the details toggle.
            InkWell(
              key: Key('job_card_details_toggle_${job.id}'),
              onTap: () => setState(() {
                if (!_expandedJobCardIds.add(job.id)) {
                  _expandedJobCardIds.remove(job.id);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _expandedJobCardIds.contains(job.id)
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      l10n.jobCardDetailsToggle,
                      style: AppTypography.labelMd.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expandedJobCardIds.contains(job.id))
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _buildSubordinateChip(
                    Icons.person_outline,
                    l10n.employeeJobsLabelCustomer,
                    job.userId,
                  ),
                  _buildSubordinateChip(
                    Icons.payment_outlined,
                    l10n.employeeJobsLabelPayment,
                    AppTypography.uppercaseLabel(job.paymentMethod),
                  ),
                  if (job.lockedEscrowAmount != null &&
                      job.lockedEscrowAmount! > 0)
                    _buildSubordinateChip(
                      Icons.lock_clock_outlined,
                      l10n.employeeJobsLabelEscrow,
                      l10n.ownerHomeCreditsAmount(
                          job.lockedEscrowAmount!.toStringAsFixed(2)),
                    ),
                ],
              ),
            if (job.cancellationReason != null &&
                job.cancellationReason!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ThemedPanel(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.defaultBorder,
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    l10n.employeeJobsCancellationReason(
                        job.cancellationReason!),
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.error,
                    ),
                  )),
            ],
            if (isActive) ...[
              Consumer<EmployeeLocationProvider>(
                builder: (context, locationProvider, child) {
                  if (locationProvider.status ==
                          LocationSharingStatus.permissionDenied ||
                      locationProvider.status ==
                          LocationSharingStatus.serviceDisabled) {
                    return ThemedPanel(
                        color: context.semanticColors.warning
                            .withValues(alpha: 0.1),
                        borderRadius: AppRadius.defaultBorder,
                        border:
                            Border.all(color: context.semanticColors.warning),
                        key: const Key('location_permission_denied_banner'),
                        margin: const EdgeInsets.only(top: AppSpacing.sm),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.location_off_outlined,
                                    color: context.semanticColors.warning,
                                    size: 20),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    l10n.employeeJobsLocationPermissionTitle,
                                    style: AppTypography.bodyMd.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: context.semanticColors.warning,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              l10n.employeeJobsLocationPermissionDesc,
                              style: AppTypography.bodyMd.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            SecondaryButton(
                              key: const Key('open_app_settings_button'),
                              text: l10n.employeeJobsOpenAppSettings,
                              icon: Icons.settings_outlined,
                              isOutlined: true,
                              onPressed: () {
                                Geolocator.openAppSettings();
                              },
                            ),
                          ],
                        ));
                  }

                  if (locationProvider.status ==
                      LocationSharingStatus.tracking) {
                    return ThemedPanel(
                        color: context.semanticColors.success
                            .withValues(alpha: 0.1),
                        borderRadius: AppRadius.smBorder,
                        border: Border.all(
                            color: context.semanticColors.success
                                .withValues(alpha: 0.3)),
                        key: const Key('location_sharing_indicator'),
                        margin: const EdgeInsets.only(top: AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ThemedPanel(
                                shape: BoxShape.circle,
                                color: context.semanticColors.success,
                                width: 8,
                                height: 8),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              l10n.employeeJobsSharingLiveLocation,
                              style: AppTypography.labelMd.copyWith(
                                color: context.semanticColors.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ));
                  }

                  if (locationProvider.status == LocationSharingStatus.error &&
                      locationProvider.error != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: ThemedErrorBanner(
                        message: locationProvider.error!,
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
              if (_completeErrorJobId == job.id && _completeError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ThemedErrorBanner(
                  message: _completeError!,
                  onRetry: () => _confirmAndCompleteJob(job),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.lg),
            // Action buttons bar
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    key: Key('employee_chat_button_${job.id}'),
                    text: l10n.employeeJobsChatButton,
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
                      text: l10n.employeeJobsCompleteJobButton,
                      icon: Icons.check_circle_outline,
                      trailingIcon: Icons.arrow_forward,
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
    return ThemedPanel(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.smBorder,
        border: Border.all(color: AppColors.outlineVariant),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Text(
              "$label: ",
              style: AppTypography.labelLg.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
            Text(
              value,
              style: AppTypography.labelLg.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ));
  }
}
