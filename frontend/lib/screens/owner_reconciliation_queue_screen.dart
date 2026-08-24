import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/reconciliation_job.dart';
import '../providers/reconciliation_provider.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/list_screen_template.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_success_banner.dart';
import '../widgets/themed_text_field.dart';

class OwnerReconciliationQueueScreen extends StatefulWidget {
  const OwnerReconciliationQueueScreen({super.key});

  @override
  State<OwnerReconciliationQueueScreen> createState() =>
      _OwnerReconciliationQueueScreenState();
}

class _OwnerReconciliationQueueScreenState
    extends State<OwnerReconciliationQueueScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'all';
  // In-flight guard (QA audit A4): resolveJob releases escrow / refunds the
  // customer — a second confirm while the first POST is pending must be
  // impossible. Set before the dialog opens, cleared when the await settles.
  String? _resolvingJobId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ReconciliationProvider>(context, listen: false).fetchQueue();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await Provider.of<ReconciliationProvider>(context, listen: false)
        .fetchQueue();
  }

  Future<void> _showConfirmationDialog({
    required BuildContext context,
    required ReconciliationJob job,
    required String decision,
  }) async {
    // Re-entrancy guard (QA audit A4): resolveJob moves escrow (release to
    // employee / refund to customer). While one resolution POST is in
    // flight the action buttons are disabled AND this entry point refuses
    // re-entry, so a second confirm can never fire a duplicate money-moving
    // request. The modal dialog itself protects the decision phase; the
    // flag below covers the vulnerable window AFTER confirm while the call
    // is still awaiting the backend.
    if (_resolvingJobId != null) return;
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
      setState(() => _resolvingJobId = job.id);
      try {
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
      } finally {
        if (mounted) {
          setState(() => _resolvingJobId = null);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Consumer<ReconciliationProvider>(
      builder: (context, provider, child) {
        final query = _searchController.text.trim().toLowerCase();
        final filteredQueue = provider.queue.where((j) {
          final reason =
              '${j.humanReadableFailureReason} ${j.escrowFailureReason}'
                  .toLowerCase();
          final matchesQuery = query.isEmpty ||
              j.id.toLowerCase().contains(query) ||
              j.userId.toLowerCase().contains(query) ||
              (j.employeeId ?? '').toLowerCase().contains(query) ||
              reason.contains(query) ||
              j.reconciliationNote.toLowerCase().contains(query);
          if (!matchesQuery) return false;

          if (_selectedCategory == 'distance') {
            return reason.contains('distance');
          }
          if (_selectedCategory == 'time') {
            return reason.contains('time') || reason.contains('speed');
          }
          if (_selectedCategory == 'other') {
            return !reason.contains('distance') &&
                !reason.contains('time') &&
                !reason.contains('speed');
          }
          return true;
        }).toList();

        final distanceCount = provider.queue.where((j) {
          final reason =
              '${j.humanReadableFailureReason} ${j.escrowFailureReason}'
                  .toLowerCase();
          return reason.contains('distance');
        }).length;

        final timeCount = provider.queue.where((j) {
          final reason =
              '${j.humanReadableFailureReason} ${j.escrowFailureReason}'
                  .toLowerCase();
          return reason.contains('time') || reason.contains('speed');
        }).length;

        final otherCount = provider.queue.where((j) {
          final reason =
              '${j.humanReadableFailureReason} ${j.escrowFailureReason}'
                  .toLowerCase();
          return !reason.contains('distance') &&
              !reason.contains('time') &&
              !reason.contains('speed');
        }).length;

        return ListScreenTemplate<ReconciliationJob>(
          titleWidget: Row(
            children: [
              const Icon(Icons.assignment,
                  color: AppColors.secondary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  l10n.reconciliationReviewTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          isLoading: provider.isLoading && provider.queue.isEmpty,
          errorMessage: provider.queue.isEmpty ? provider.error : null,
          onRetry: () => provider.fetchQueue(),
          onRefresh: _onRefresh,
          errorWidget: provider.error != null && provider.queue.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: ThemedErrorBanner(
                      key: const Key('reconciliation_error_banner'),
                      message: provider.error!,
                      onRetry: () => provider.fetchQueue(),
                    ),
                  ),
                )
              : null,
          emptyWidget: provider.queue.isEmpty
              ? ThemedEmptyState(
                  icon: Icons.check_circle_outline,
                  title: l10n.reconciliationEmptyTitle,
                  description: l10n.reconciliationEmptyDesc,
                  actionText: l10n.refreshQueueBtn,
                  onActionPressed: _onRefresh,
                )
              : null,
          header: provider.queue.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ThemedTextField(
                        key: const Key('reconciliation_search_field'),
                        controller: _searchController,
                        hintText: l10n.reconQueueSearchHint,
                        prefixIcon:
                            const Icon(Icons.search, color: AppColors.outline),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      PillFilterBar<String>(
                        key: const Key('reconciliation_pill_filter_bar'),
                        padding: EdgeInsets.zero,
                        items: [
                          PillFilterItem(
                            label: l10n.filterAll,
                            value: "all",
                            count: provider.queue.length,
                          ),
                          PillFilterItem(
                            label: l10n.reconFilterDistance,
                            value: "distance",
                            count: distanceCount,
                          ),
                          PillFilterItem(
                            label: l10n.reconFilterTimeSpeed,
                            value: "time",
                            count: timeCount,
                          ),
                          PillFilterItem(
                            label: l10n.reconFilterOther,
                            value: "other",
                            count: otherCount,
                          ),
                        ],
                        selectedValue: _selectedCategory,
                        onSelected: (val) =>
                            setState(() => _selectedCategory = val),
                      ),
                      if (filteredQueue.isEmpty &&
                          provider.queue.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Center(
                          child: Text(
                            l10n.noReconMatchFilter,
                            style: AppTypography.bodyMd.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
          items: provider.queue.isEmpty ? const [] : filteredQueue,
          itemSpacing: 0,
          listPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemBuilder: (context, job, index) =>
              _buildReconciliationCard(context, job, l10n),
        );
      },
    );
  }

  Widget _buildReconciliationCard(
    BuildContext context,
    ReconciliationJob job,
    AppLocalizations l10n,
  ) {
    final isHighRisk =
        job.humanReadableFailureReason.toLowerCase().contains('damage') ||
            job.humanReadableFailureReason.toLowerCase().contains('dispute') ||
            job.escrowFailureReason.toLowerCase().contains('over_distance');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ThemedCard(
        borderRadius: AppRadius.md,
        padding: AppSpacing.lg,
        topAccentColor: isHighRisk ? AppColors.error : AppColors.secondary,
        topAccentHeight: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${l10n.customerJobsOrder}${job.id}',
                    style: AppTypography.titleMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
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
              valueColor: Theme.of(context).colorScheme.primary,
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
                  child: SecondaryButton(
                    isFullWidth: false,
                    isOutlined: true,
                    isDestructive: true,
                    icon: Icons.undo,
                    text: l10n.reconciliationRefundCustomer,
                    isLoading: _resolvingJobId == job.id,
                    onPressed: _resolvingJobId != null
                        ? null
                        : () {
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
                  child: PrimaryButton(
                    isFullWidth: false,
                    icon: Icons.check_circle_outline,
                    trailingIcon: Icons.arrow_forward,
                    text: l10n.reconciliationReleaseEmployee,
                    isLoading: _resolvingJobId == job.id,
                    onPressed: _resolvingJobId != null
                        ? null
                        : () {
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMd.copyWith(
                color: valueColor ?? Theme.of(context).colorScheme.onSurface,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
