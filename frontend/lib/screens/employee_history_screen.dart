import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/employee_jobs_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/list_screen_template.dart';
import '../widgets/route_timeline.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/skeleton_loader.dart';

class EmployeeHistoryScreen extends StatefulWidget {
  final bool isEmbeddedInTab;
  const EmployeeHistoryScreen({super.key, this.isEmbeddedInTab = false});

  @override
  State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
}

class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshHistory();
    });
  }

  Future<void> _refreshHistory() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token != null) {
      final jobsProvider =
          Provider.of<EmployeeJobsProvider>(context, listen: false);
      await jobsProvider.fetchAssignedJobs(auth.token!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final jobsProvider = Provider.of<EmployeeJobsProvider>(context);

    final completedJobs = jobsProvider.jobs.where((j) {
      final s = j.status.toLowerCase().trim();
      return s == 'completed' || s == 'cancelled';
    }).toList();

    return ListScreenTemplate<Job>(
      title: l10n.ownerHistoryTitle,
      isEmbeddedInTab: widget.isEmbeddedInTab,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(l10n),
            const SizedBox(height: AppSpacing.lg),
            ThemedSectionHeader(title: context.l10n.recentActivityHeader),
          ],
        ),
      ),
      items: completedJobs,
      isLoading: jobsProvider.isLoading,
      errorMessage: jobsProvider.error,
      onRefresh: _refreshHistory,
      onRetry: _refreshHistory,
      listViewKey: const Key('employee_history_list'),
      loadingWidget: ListView.builder(
        key: const ValueKey('employee_history_skeleton_list'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: 3,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.md),
          child: EmployeeJobCardSkeleton(),
        ),
      ),
      errorWidget: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ThemedErrorBanner(
          key: const ValueKey('employee_history_error'),
          message: jobsProvider.error ?? '',
          onRetry: _refreshHistory,
        ),
      ),
      emptyWidget: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ThemedCard(
          elevation: AppElevation.shadowLevel1List,
          borderRadius: AppRadius.lg,
          padding: AppSpacing.xl,
          child: ThemedEmptyState(
            key: const Key('employee_history_empty_state'),
            icon: Icons.history_outlined,
            title: l10n.ownerHistoryNoJobsTitle,
            description: l10n.ownerHistoryNoJobsDesc,
            actionText: "Refresh History",
            onActionPressed: _refreshHistory,
          ),
        ),
      ),
      listPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      itemSpacing: 0,
      itemBuilder: (context, job, index) {
        return _buildHistoryCard(job);
      },
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.ownerHistoryTitle,
          style: AppTypography.headlineLgMobile.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          context.l10n.employeeHistorySubtitle,
          style: AppTypography.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(Job job) {
    final l10n = context.l10n;
    final isCancelled = job.status.toLowerCase().trim() == 'cancelled';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ThemedCard(
        key: Key('employee_history_card_${job.id}'),
        elevation: AppElevation.shadowLevel1List,
        borderRadius: AppRadius.lg,
        padding: AppSpacing.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.employeeJobsJobId(job.id),
                    style: AppTypography.titleMd.copyWith(
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
            RouteTimeline(
              pickupAddress: "Pickup Location",
              pickupDetail: "Order Dispatched",
              dropoffAddress: "Delivery Destination",
              dropoffDetail: "Customer: ${job.userId}",
              distanceText: job.lockedEscrowAmount != null
                  ? "${job.lockedEscrowAmount!.toStringAsFixed(0)} Credits"
                  : "Route Logged",
              timeText: isCancelled ? "Cancelled" : "Completed",
              cargoText: AppTypography.uppercaseLabel(job.paymentMethod),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _buildChip(
                  Icons.person_outline,
                  l10n.employeeJobsLabelCustomer,
                  job.userId,
                ),
                _buildChip(
                  Icons.payment_outlined,
                  l10n.employeeJobsLabelPayment,
                  AppTypography.uppercaseLabel(job.paymentMethod),
                ),
                if (job.lockedEscrowAmount != null &&
                    job.lockedEscrowAmount! > 0)
                  _buildChip(
                    Icons.lock_clock_outlined,
                    l10n.employeeJobsLabelEscrow,
                    l10n.ownerHomeCreditsAmount(
                        job.lockedEscrowAmount!.toStringAsFixed(2)),
                  ),
              ],
            ),
            if (isCancelled &&
                job.cancellationReason != null &&
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
          ],
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String label, String value) {
    return ThemedPanel(
        color: AppColors.surface,
        borderRadius: AppRadius.smBorder,
        border: Border.all(color: AppColors.outlineVariant),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSize.xs, color: AppColors.onSurfaceVariant),
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
        ));
  }
}
