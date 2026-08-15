import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/reconciliation_job.dart';
import '../providers/reconciliation_provider.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_success_banner.dart';

class OwnerReconciliationQueueScreen extends StatefulWidget {
  const OwnerReconciliationQueueScreen({super.key});

  @override
  State<OwnerReconciliationQueueScreen> createState() =>
      _OwnerReconciliationQueueScreenState();
}

class _OwnerReconciliationQueueScreenState
    extends State<OwnerReconciliationQueueScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ReconciliationProvider>(context, listen: false).fetchQueue();
    });
  }

  Future<void> _showConfirmationDialog({
    required BuildContext context,
    required ReconciliationJob job,
    required String decision,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final isRelease = decision == 'release_to_employee';
    final actionLabel = isRelease
        ? l10n.reconciliationReleaseEmployee
        : l10n.reconciliationRefundCustomer;
    final targetRole = isRelease ? l10n.roleEmployeeTenant : l10n.roleCustomer;

    final confirmed = await ConfirmActionDialog.show(
      context,
      title: l10n.reconciliationConfirmTitle(actionLabel),
      message: l10n.reconciliationConfirmMessage(
        actionLabel,
        job.id,
        job.lockedEscrowAmount.toStringAsFixed(2),
        targetRole,
      ),
      confirmLabel: l10n.reconciliationConfirmTitle(actionLabel),
      cancelLabel: l10n.cancel,
      isDestructive: !isRelease,
    );

    if (confirmed == true && context.mounted) {
      final provider =
          Provider.of<ReconciliationProvider>(context, listen: false);
      final success = await provider.resolveJob(
        jobId: job.id,
        decision: decision,
      );

      if (!context.mounted) return;

      if (success) {
        ThemedSnackBar.showSuccess(
          context,
          isRelease
              ? l10n.reconciliationSuccessRelease
              : l10n.reconciliationSuccessRefund,
        );
      } else {
        final err = provider.error ?? l10n.reconciliationFailed;
        ThemedSnackBar.showError(
          context,
          err,
          onRetry: () => _showConfirmationDialog(
            context: context,
            job: job,
            decision: decision,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(l10n.reconciliationReviewTitle),
        foregroundColor: AppColors.onPrimary,
      ),
      body: Consumer<ReconciliationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.queue.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            );
          }

          if (provider.error != null && provider.queue.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      provider.error!,
                      style:
                          AppTypography.bodyMd.copyWith(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton(
                      onPressed: () => provider.fetchQueue(),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.queue.isEmpty) {
            return RefreshIndicator(
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ThemedEmptyState(
                    icon: Icons.check_circle_outline,
                    title: l10n.reconciliationEmptyTitle,
                    description: l10n.reconciliationEmptyDesc,
                    actionText: "Refresh Queue",
                    onActionPressed: _onRefresh,
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: provider.queue.length,
              itemBuilder: (context, index) {
                final job = provider.queue[index];
                return _buildReconciliationCard(context, job, l10n);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _onRefresh() async {
    await Provider.of<ReconciliationProvider>(context, listen: false)
        .fetchQueue();
  }

  Widget _buildReconciliationCard(
      BuildContext context, ReconciliationJob job, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ThemedCard(
        borderRadius: AppRadius.md,
        padding: AppSpacing.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${l10n.customerJobsOrder}${job.id}',
                    style: AppTypography.headlineLgMobile.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const StatusBadge(
                  status: 'escrow_reconciliation_required',
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(color: AppColors.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            _buildDetailRow(
              l10n.reconciliationFailureReason,
              job.humanReadableFailureReason,
              isBold: true,
              valueColor: AppColors.error,
            ),
            if (job.reconciliationNote.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _buildDetailRow(
                l10n.reconciliationNote,
                job.reconciliationNote,
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            _buildDetailRow(
              l10n.reconciliationLockedEscrow,
              '${job.lockedEscrowAmount.toStringAsFixed(2)} Credits',
              isBold: true,
              valueColor: AppColors.primary,
            ),
            if (job.employeeId != null && job.employeeId!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _buildDetailRow(l10n.reconciliationEmployeeId, job.employeeId!),
            ],
            const SizedBox(height: AppSpacing.xs),
            _buildDetailRow(l10n.reconciliationCustomerId, job.userId),
            const SizedBox(height: AppSpacing.xs),
            _buildDetailRow(l10n.reconciliationServiceId, job.serviceId),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.undo, color: AppColors.error),
                    label: Text(
                      l10n.reconciliationRefundCustomer,
                      style:
                          AppTypography.bodyMd.copyWith(color: AppColors.error),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                    ),
                    onPressed: () {
                      _showConfirmationDialog(
                        context: context,
                        job: job,
                        decision: 'refund_to_customer',
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(l10n.reconciliationReleaseEmployee),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                    ),
                    onPressed: () {
                      _showConfirmationDialog(
                        context: context,
                        job: job,
                        decision: 'release_to_employee',
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMd.copyWith(
                color: valueColor ?? AppColors.onSurface,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
