import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';

class OwnerHistoryScreen extends StatefulWidget {
  final bool isEmbeddedInTab;
  const OwnerHistoryScreen({super.key, this.isEmbeddedInTab = false});

  @override
  State<OwnerHistoryScreen> createState() => _OwnerHistoryScreenState();
}

class _OwnerHistoryScreenState extends State<OwnerHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDataForCurrentTab();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    _refreshDataForCurrentTab();
  }

  Future<void> _refreshDataForCurrentTab() async {
    final index = _tabController.index;
    if (index == 0) {
      await _refreshAuditLog();
    } else if (index == 1) {
      await _refreshJobs();
    } else if (index == 2) {
      await _refreshLedger();
    }
  }

  Future<void> _refreshAuditLog() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    if (auth.token != null && auth.user != null) {
      await ownerProvider.fetchAuditLog(
        tenantId: auth.user!.id,
        requesterToken: auth.token!,
      );
    }
  }

  Future<void> _refreshJobs() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    if (auth.token != null) {
      await ownerProvider.fetchOwnerJobs(auth.token!);
    }
  }

  Future<void> _refreshLedger() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    if (auth.token != null) {
      await ownerProvider.fetchDashboardData(auth.token!);
    }
  }

  Widget _buildTabBar(AppLocalizations l10n) {
    return Material(
      color: AppColors.primary,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.secondary,
        indicatorWeight: 3,
        labelColor: AppColors.onPrimary,
        unselectedLabelColor: AppColors.onPrimary.withValues(alpha: 0.7),
        labelStyle: AppTypography.titleMd.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        unselectedLabelStyle: AppTypography.titleMd.copyWith(fontSize: 13),
        tabs: [
          Tab(
            key: const Key('history_tab_activity'),
            text: l10n.ownerHistoryTabActivity,
            icon: const Icon(Icons.history_outlined, size: 20),
          ),
          Tab(
            key: const Key('history_tab_jobs'),
            text: l10n.ownerHistoryTabJobs,
            icon: const Icon(Icons.assignment_turned_in_outlined, size: 20),
          ),
          Tab(
            key: const Key('history_tab_ledger'),
            text: l10n.ownerHistoryTabLedger,
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityLogTab(OwnerProvider ownerProvider) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _refreshAuditLog,
      child: ownerProvider.isLoading && ownerProvider.auditLogEntries.isEmpty
          ? const Center(child: ThemedLoadingIndicator())
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ownerProvider.error != null) ...[
                    ThemedErrorBanner(
                      message: ownerProvider.error!,
                      onRetry: _refreshDataForCurrentTab,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ownerProvider.auditLogEntries.isEmpty)
                    ThemedCard(
                      borderRadius: AppRadius.md,
                      padding: AppSpacing.lg,
                      child: ThemedEmptyState(
                        key: const Key('empty_audit_log_state'),
                        icon: Icons.history_outlined,
                        title: l10n.ownerHistoryNoActivityTitle,
                        description: l10n.ownerHistoryNoActivityDesc,
                        actionText: "Refresh History",
                        onActionPressed: _refreshDataForCurrentTab,
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ownerProvider.auditLogEntries.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final entry = ownerProvider.auditLogEntries[index];
                        final rawAction =
                            entry['action']?.toString() ?? 'Unknown Action';
                        final actionTitle =
                            rawAction.replaceAll('_', ' ').toUpperCase();
                        final details = entry['details']?.toString() ?? '';
                        final actorId = entry['actor_id']?.toString() ?? '';
                        final rawTs = entry['timestamp']?.toString() ?? '';

                        DateTime? timestamp;
                        if (rawTs.isNotEmpty) {
                          try {
                            timestamp = DateTime.parse(rawTs).toLocal();
                          } catch (_) {}
                        }

                        final dateStr = timestamp != null
                            ? "${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} ${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}"
                            : rawTs;

                        return ThemedCard(
                          padding: AppSpacing.md,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      actionTitle,
                                      style: AppTypography.titleMd.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.admin_panel_settings_outlined,
                                    size: 20,
                                    color: AppColors.outline,
                                  ),
                                ],
                              ),
                              if (details.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  details,
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  if (actorId.isNotEmpty)
                                    Text(
                                      l10n.ownerHistoryActorId(actorId),
                                      style: AppTypography.labelMd.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  Text(
                                    dateStr,
                                    style: AppTypography.labelMd.copyWith(
                                      color: AppColors.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildCompletedJobsTab(OwnerProvider ownerProvider) {
    final l10n = AppLocalizations.of(context)!;
    final List<Job> completedJobs = ownerProvider.ownerJobs
        .where((j) => j.status == 'completed' || j.status == 'cancelled')
        .toList();

    return RefreshIndicator(
      onRefresh: _refreshJobs,
      child: ownerProvider.isLoading && ownerProvider.ownerJobs.isEmpty
          ? const Center(child: ThemedLoadingIndicator())
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ownerProvider.error != null) ...[
                    ThemedErrorBanner(
                      message: ownerProvider.error!,
                      onRetry: _refreshDataForCurrentTab,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (completedJobs.isEmpty)
                    ThemedCard(
                      borderRadius: AppRadius.md,
                      padding: AppSpacing.lg,
                      child: ThemedEmptyState(
                        key: const Key('empty_jobs_state'),
                        icon: Icons.assignment_turned_in_outlined,
                        title: l10n.ownerHistoryNoJobsTitle,
                        description: l10n.ownerHistoryNoJobsDesc,
                        actionText: "Refresh History",
                        onActionPressed: _refreshDataForCurrentTab,
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: completedJobs.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final job = completedJobs[index];
                        final isCancelled = job.status == 'cancelled';
                        return ThemedCard(
                          padding: AppSpacing.md,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    l10n.ownerHomeJobId(job.id),
                                    style: AppTypography.titleMd.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  StatusBadge(status: job.status),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                l10n.ownerHomePaymentInfo(
                                    job.paymentMethod.toUpperCase(),
                                    job.lockedEscrowAmount != null
                                        ? ' (\$${job.lockedEscrowAmount!.toStringAsFixed(2)})'
                                        : ''),
                                style: AppTypography.bodyMd.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              if (isCancelled &&
                                  job.cancellationReason != null &&
                                  job.cancellationReason!.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  l10n.ownerHistoryCancellationReason(
                                      job.cancellationReason!),
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.error,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildWalletLedgerTab(OwnerProvider ownerProvider) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _refreshLedger,
      child: ownerProvider.isLoading && ownerProvider.ledgerEntries.isEmpty
          ? const Center(child: ThemedLoadingIndicator())
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ownerProvider.error != null) ...[
                    ThemedErrorBanner(
                      message: ownerProvider.error!,
                      onRetry: _refreshLedger,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ownerProvider.ledgerEntries.isEmpty)
                    ThemedCard(
                      borderRadius: AppRadius.md,
                      padding: AppSpacing.lg,
                      child: ThemedEmptyState(
                        key: const Key('empty_ledger_state'),
                        icon: Icons.receipt_long_outlined,
                        title: l10n.ownerHistoryNoLedgerTitle,
                        description: l10n.ownerHistoryNoLedgerDesc,
                        actionText: "Refresh History",
                        onActionPressed: _refreshLedger,
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ownerProvider.ledgerEntries.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final entry = ownerProvider.ledgerEntries[index];
                        final rawType = entry['type']?.toString() ?? '';
                        final amount =
                            (entry['amount'] as num?)?.toDouble() ?? 0.0;
                        final balanceAfter =
                            (entry['balance_after'] as num?)?.toDouble() ?? 0.0;
                        final description =
                            entry['description']?.toString() ?? '';
                        final jobId = entry['job_id']?.toString() ?? '';
                        final rawTs = entry['timestamp']?.toString() ?? '';

                        DateTime? timestamp;
                        if (rawTs.isNotEmpty) {
                          try {
                            timestamp = DateTime.parse(rawTs).toLocal();
                          } catch (_) {}
                        }

                        final dateStr = timestamp != null
                            ? "${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} ${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}"
                            : rawTs;

                        IconData icon;
                        Color color;
                        switch (rawType) {
                          case 'deposit':
                            icon = Icons.add_circle_outline_rounded;
                            color = AppColors.success;
                            break;
                          case 'escrow_lock':
                            icon = Icons.lock_outline_rounded;
                            color = AppColors.warning;
                            break;
                          case 'escrow_release':
                            icon = Icons.lock_open_rounded;
                            color = AppColors.primary;
                            break;
                          case 'refund':
                            icon = Icons.replay_rounded;
                            color = AppColors.success;
                            break;
                          case 'fee_deduction':
                            icon = Icons.remove_circle_outline_rounded;
                            color = AppColors.error;
                            break;
                          default:
                            icon = Icons.monetization_on_outlined;
                            color = AppColors.outline;
                        }

                        final isPositive = rawType == 'deposit' ||
                            rawType == 'refund' ||
                            rawType == 'escrow_release';

                        return ThemedCard(
                          padding: AppSpacing.md,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Icon(icon, color: color, size: 24),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      description.isNotEmpty
                                          ? description
                                          : rawType.toUpperCase(),
                                      style: AppTypography.titleMd.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      l10n.ownerHistoryBalanceAfter(
                                          balanceAfter.toStringAsFixed(2),
                                          jobId.isNotEmpty
                                              ? ' • Job #$jobId'
                                              : ''),
                                      style: AppTypography.labelMd.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dateStr,
                                      style: AppTypography.labelMd.copyWith(
                                        color: AppColors.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                "${isPositive ? '+' : '-'}\$${amount.toStringAsFixed(2)}",
                                style: AppTypography.titleMd.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isPositive
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ownerProvider = Provider.of<OwnerProvider>(context);

    final tabBarView = TabBarView(
      controller: _tabController,
      children: [
        _buildActivityLogTab(ownerProvider),
        _buildCompletedJobsTab(ownerProvider),
        _buildWalletLedgerTab(ownerProvider),
      ],
    );

    if (widget.isEmbeddedInTab) {
      return Column(
        children: [
          _buildTabBar(l10n),
          Expanded(child: tabBarView),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: Text(l10n.ownerHistoryTitle),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.secondary,
          indicatorWeight: 3,
          labelColor: AppColors.onPrimary,
          unselectedLabelColor: AppColors.onPrimary.withValues(alpha: 0.7),
          tabs: [
            Tab(
              key: const Key('history_tab_activity'),
              text: l10n.ownerHistoryTabActivity,
              icon: const Icon(Icons.history_outlined, size: 20),
            ),
            Tab(
              key: const Key('history_tab_jobs'),
              text: l10n.ownerHistoryTabJobs,
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 20),
            ),
            Tab(
              key: const Key('history_tab_ledger'),
              text: l10n.ownerHistoryTabLedger,
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
            ),
          ],
        ),
      ),
      body: tabBarView,
    );
  }
}
