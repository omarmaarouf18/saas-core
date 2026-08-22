import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_text_field.dart';

class OwnerHistoryScreen extends StatefulWidget {
  final bool isEmbeddedInTab;
  const OwnerHistoryScreen({super.key, this.isEmbeddedInTab = false});

  @override
  State<OwnerHistoryScreen> createState() => _OwnerHistoryScreenState();
}

class _OwnerHistoryScreenState extends State<OwnerHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _jobsSearchController = TextEditingController();
  String _jobsStatusFilter = 'all';

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
    _jobsSearchController.dispose();
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

    return AppShell(
      title: l10n.ownerHistoryTitle,
      isEmbeddedInTab: widget.isEmbeddedInTab,
      useSafeArea: !widget.isEmbeddedInTab,
      bottom: widget.isEmbeddedInTab ? null : _buildTabBar(l10n),
      body: widget.isEmbeddedInTab
          ? Column(
              children: [
                Material(
                  color: AppColors.primary,
                  child: _buildTabBar(l10n),
                ),
                Expanded(child: tabBarView),
              ],
            )
          : tabBarView,
    );
  }

  PreferredSizeWidget _buildTabBar(AppLocalizations l10n) {
    return TabBar(
      controller: _tabController,
      indicatorColor: AppColors.secondary,
      indicatorWeight: 3,
      labelColor: AppColors.onPrimary,
      unselectedLabelColor: AppColors.onPrimary.withValues(alpha: 0.7),
      labelStyle: AppTypography.bodySm.copyWith(
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelStyle: AppTypography.bodySm,
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
                        return _buildActivityCard(
                          ownerProvider.auditLogEntries[index],
                          l10n,
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> entry, AppLocalizations l10n) {
    final rawAction = entry['action']?.toString() ?? 'Unknown Action';
    final actionTitle =
        AppTypography.uppercaseLabel(rawAction.replaceAll('_', ' '));
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
  }

  Widget _buildCompletedJobsTab(OwnerProvider ownerProvider) {
    final l10n = AppLocalizations.of(context)!;
    final List<Job> completedJobs = ownerProvider.ownerJobs
        .where((j) => j.status == 'completed' || j.status == 'cancelled')
        .toList();

    final query = _jobsSearchController.text.trim().toLowerCase();
    final filteredJobs = completedJobs.where((j) {
      final matchesQuery = query.isEmpty ||
          j.id.toLowerCase().contains(query) ||
          j.userId.toLowerCase().contains(query) ||
          (j.cancellationReason ?? '').toLowerCase().contains(query);
      if (!matchesQuery) return false;

      if (_jobsStatusFilter == 'completed') return j.status == 'completed';
      if (_jobsStatusFilter == 'cancelled') return j.status == 'cancelled';
      return true;
    }).toList();

    final totalCompleted =
        completedJobs.where((j) => j.status == 'completed').length;
    final totalCancelled =
        completedJobs.where((j) => j.status == 'cancelled').length;

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
                  // Search & Pill Filter Bar
                  ThemedTextField(
                    key: const Key('owner_jobs_search_field'),
                    controller: _jobsSearchController,
                    hintText: l10n.ownerJobsSearchHint,
                    prefixIcon:
                        const Icon(Icons.search, color: AppColors.outline),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PillFilterBar<String>(
                    key: const Key('owner_jobs_pill_filter_bar'),
                    padding: EdgeInsets.zero,
                    items: [
                      PillFilterItem(
                        label: l10n.filterAll,
                        value: "all",
                        count: completedJobs.length,
                      ),
                      PillFilterItem(
                        label: l10n.statusCompleted,
                        value: "completed",
                        count: totalCompleted,
                      ),
                      PillFilterItem(
                        label: l10n.statusCancelled,
                        value: "cancelled",
                        count: totalCancelled,
                      ),
                    ],
                    selectedValue: _jobsStatusFilter,
                    onSelected: (val) =>
                        setState(() => _jobsStatusFilter = val),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                  else if (filteredJobs.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Center(
                        child: Text(
                          l10n.noJobsMatchFilter,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredJobs.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        return _buildJobHistoryCard(filteredJobs[index], l10n);
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildJobHistoryCard(Job job, AppLocalizations l10n) {
    final isCancelled = job.status == 'cancelled';
    return ThemedCard(
      padding: AppSpacing.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              AppTypography.uppercaseLabel(job.paymentMethod),
              job.lockedEscrowAmount != null
                  ? ' (\$${job.lockedEscrowAmount!.toStringAsFixed(2)})'
                  : '',
            ),
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          if (isCancelled &&
              job.cancellationReason != null &&
              job.cancellationReason!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.ownerHistoryCancellationReason(job.cancellationReason!),
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.error,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
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
                        return _buildLedgerCard(
                          ownerProvider.ledgerEntries[index],
                          l10n,
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildLedgerCard(Map<String, dynamic> entry, AppLocalizations l10n) {
    final rawType = entry['type']?.toString() ?? '';
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0.0;
    final balanceAfter = (entry['balance_after'] as num?)?.toDouble() ?? 0.0;
    final description = entry['description']?.toString() ?? '';
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
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: ColoredBox(
              color: color.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(icon, color: color, size: 24),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description.isNotEmpty
                      ? description
                      : AppTypography.uppercaseLabel(rawType),
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.ownerHistoryBalanceAfter(
                    balanceAfter.toStringAsFixed(2),
                    jobId.isNotEmpty ? ' • Job #$jobId' : '',
                  ),
                  style: AppTypography.labelMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
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
              color: isPositive ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
