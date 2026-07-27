import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/reconciliation_job.dart';
import '../providers/reconciliation_provider.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';

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
    final isRelease = decision == 'release_to_employee';
    final actionLabel =
        isRelease ? 'Release to Employee' : 'Refund to Customer';
    final targetRole = isRelease ? 'employee/tenant' : 'customer';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Confirm $actionLabel',
          style: AppTypography.headlineLgMobile.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to $actionLabel for Job #${job.id}?\n\n'
          'This will transfer ${job.lockedEscrowAmount.toStringAsFixed(2)} Credits back to the $targetRole. Real funds will be moved.',
          style: AppTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isRelease ? AppColors.primary : AppColors.error,
              foregroundColor: AppColors.onPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Confirm $actionLabel'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final provider =
          Provider.of<ReconciliationProvider>(context, listen: false);
      final success = await provider.resolveJob(
        jobId: job.id,
        decision: decision,
      );

      if (!context.mounted) return;

      if (success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isRelease
                  ? 'Escrow resolved: funds released to employee/tenant'
                  : 'Escrow resolved: funds refunded to customer',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        final err = provider.error ?? 'Failed to resolve reconciliation';
        messenger.showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Escrow Reconciliation Review'),
        foregroundColor: AppColors.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Queue',
            onPressed: () {
              Provider.of<ReconciliationProvider>(context, listen: false)
                  .fetchQueue();
            },
          ),
        ],
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
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.queue.isEmpty) {
            return const RefreshIndicator(
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: ThemedEmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'No jobs pending reconciliation',
                    description:
                        'All escrow transactions are healthy. No flagged jobs require manual review.',
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.fetchQueue(),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: provider.queue.length,
              itemBuilder: (context, index) {
                final job = provider.queue[index];
                return _buildReconciliationCard(context, job);
              },
            ),
          );
        },
      ),
    );
  }

  static Future<void> _onRefresh() async {}

  Widget _buildReconciliationCard(BuildContext context, ReconciliationJob job) {
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
                    'Job #${job.id}',
                    style: AppTypography.headlineLgMobile.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: AppRadius.smBorder,
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Text(
                    'RECONCILIATION REQUIRED',
                    style: AppTypography.labelMd.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(color: AppColors.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            _buildDetailRow(
              'Failure Reason',
              job.humanReadableFailureReason,
              isBold: true,
              valueColor: AppColors.error,
            ),
            if (job.reconciliationNote.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _buildDetailRow(
                'Note',
                job.reconciliationNote,
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            _buildDetailRow(
              'Locked Escrow',
              '${job.lockedEscrowAmount.toStringAsFixed(2)} Credits',
              isBold: true,
              valueColor: AppColors.primary,
            ),
            if (job.employeeId != null && job.employeeId!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _buildDetailRow('Employee ID', job.employeeId!),
            ],
            const SizedBox(height: AppSpacing.xs),
            _buildDetailRow('Customer ID', job.userId),
            const SizedBox(height: AppSpacing.xs),
            _buildDetailRow('Service ID', job.serviceId),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.undo, color: AppColors.error),
                    label: const Text(
                      'Refund to Customer',
                      style: TextStyle(color: AppColors.error),
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
                    label: const Text('Release to Employee'),
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
      padding: const EdgeInsets.symmetric(vertical: 2.0),
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
