import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/employee_jobs_provider.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
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

    final bodyContent = RefreshIndicator(
      onRefresh: _refreshHistory,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: AppMotion.durationMedium,
              switchInCurve: AppMotion.curveStateChange,
              switchOutCurve: AppMotion.curveStateChange,
              child: (jobsProvider.isLoading && completedJobs.isEmpty)
                  ? Column(
                      key: const ValueKey('employee_history_skeleton_list'),
                      children: List.generate(
                        3,
                        (index) => const EmployeeJobCardSkeleton(),
                      ),
                    )
                  : (jobsProvider.error != null && completedJobs.isEmpty)
                      ? ThemedErrorBanner(
                          key: const ValueKey('employee_history_error'),
                          message: jobsProvider.error!,
                          onRetry: _refreshHistory,
                        )
                      : KeyedSubtree(
                          key: const ValueKey('employee_history_content'),
                          child: _buildHistoryList(completedJobs),
                        ),
            ),
          ],
        ),
      ),
    );

    if (widget.isEmbeddedInTab) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l10n.ownerHistoryTitle,
          style: AppTypography.titleMd.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: bodyContent,
    );
  }

  Widget _buildHistoryList(List<Job> jobs) {
    final l10n = context.l10n;
    if (jobs.isEmpty) {
      return ThemedCard(
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
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: jobs.length,
      itemBuilder: (context, index) {
        final job = jobs[index];
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
                      job.paymentMethod.toUpperCase(),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: AppRadius.defaultBorder,
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      l10n.employeeJobsCancellationReason(
                          job.cancellationReason!),
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
      },
    );
  }

  Widget _buildChip(IconData icon, String label, String value) {
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
