import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/list_screen_template.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_text_field.dart';
import 'job_status_screen.dart';

class CustomerJobsScreen extends StatefulWidget {
  final bool isEmbeddedInTab;
  const CustomerJobsScreen({super.key, this.isEmbeddedInTab = false});

  @override
  State<CustomerJobsScreen> createState() => _CustomerJobsScreenState();
}

class _CustomerJobsScreenState extends State<CustomerJobsScreen> {
  String _selectedFilter =
      'all'; // 'all', 'in_transit', 'completed', 'cancelled'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomerJobs();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerJobs() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token != null) {
      await Provider.of<MarketplaceProvider>(context, listen: false)
          .fetchCustomerJobs(auth.token!);
    }
  }

  List<Job> _filterJobs(List<Job> allJobs) {
    List<Job> jobs = allJobs;
    if (_selectedFilter == 'in_transit') {
      jobs = jobs.where((j) {
        final s = j.status.toLowerCase();
        return s == 'active' ||
            s == 'pending' ||
            s == 'pending_dispatch' ||
            s == 'assigned';
      }).toList();
    } else if (_selectedFilter == 'completed') {
      jobs = jobs.where((j) => j.status.toLowerCase() == 'completed').toList();
    } else if (_selectedFilter == 'cancelled') {
      jobs = jobs.where((j) {
        final s = j.status.toLowerCase();
        return s == 'cancelled' || s == 'unavailable';
      }).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      jobs = jobs.where((j) {
        final matchId = j.id.toLowerCase().contains(q);
        final matchService = j.serviceId.toLowerCase().contains(q);
        final matchPayment = j.paymentMethod.toLowerCase().contains(q);
        return matchId || matchService || matchPayment;
      }).toList();
    }
    return jobs;
  }

  @override
  Widget build(BuildContext context) {
    final marketplace = Provider.of<MarketplaceProvider>(context);
    final l10n = context.l10n;

    final filteredJobs = _filterJobs(marketplace.customerJobs);

    final inTransitCount = marketplace.customerJobs.where((j) {
      final s = j.status.toLowerCase();
      return s == 'active' ||
          s == 'pending' ||
          s == 'pending_dispatch' ||
          s == 'assigned';
    }).length;
    final completedCount = marketplace.customerJobs
        .where((j) => j.status.toLowerCase() == 'completed')
        .length;
    final cancelledCount = marketplace.customerJobs.where((j) {
      final s = j.status.toLowerCase();
      return s == 'cancelled' || s == 'unavailable';
    }).length;

    return ListScreenTemplate<Job>(
      title: l10n.customerJobsTitle,
      isEmbeddedInTab: widget.isEmbeddedInTab,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Page Header (Stitch "My Orders" Header)
          if (!widget.isEmbeddedInTab) _buildHeader(l10n),

          // 2. Search & Filter Bar (Stitch Search and Filter Section)
          _buildSearchAndFilter(
            l10n,
            allCount: marketplace.customerJobs.length,
            inTransitCount: inTransitCount,
            completedCount: completedCount,
            cancelledCount: cancelledCount,
          ),

          const SizedBox(height: AppSpacing.xs),
        ],
      ),
      items: filteredJobs,
      isLoading: marketplace.isLoading,
      errorMessage: marketplace.error,
      onRefresh: () async => _loadCustomerJobs(),
      listViewKey: const Key('customer_jobs_list'),
      loadingWidget: ThemedLoadingIndicator(
        key: const Key('customer_jobs_loading'),
        message: l10n.customerOrdersLoading,
      ),
      errorWidget: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ThemedErrorBanner(
              key: const Key('customer_jobs_error_banner'),
              message: marketplace.error ?? '',
              onRetry: _loadCustomerJobs,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              key: const Key('retry_customer_jobs_button'),
              onPressed: _loadCustomerJobs,
              icon: Icons.refresh,
              text: l10n.retry,
              isFullWidth: false,
            ),
          ],
        ),
      ),
      emptyWidget: ThemedEmptyState(
        key: const Key('customer_jobs_empty_state'),
        icon: Icons.receipt_long_outlined,
        title: l10n.customerJobsEmpty,
        description: l10n.customerJobsEmptyDescription,
        actionText: l10n.browseServicesBtn,
        onActionPressed: () => Navigator.pop(context),
      ),
      listPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      itemSpacing: 0,
      itemBuilder: (context, job, index) {
        return _buildJobCard(context, job, l10n);
      },
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    // Screen title lives in the AppBar; the in-body heading would duplicate
    // it, so only the subtitle stays (same pattern as wallet_screen).
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Text(
        l10n.customerJobsSub,
        style: AppTypography.bodyMd.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(
    AppLocalizations l10n, {
    required int allCount,
    required int inTransitCount,
    required int completedCount,
    required int cancelledCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: ThemedTextField(
            controller: _searchController,
            hintText: l10n.customerJobsSearchHint,
            prefixIcon: const Icon(Icons.search, size: 20),
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
          ),
        ),
        PillFilterBar<String>(
          items: [
            PillFilterItem(
              label: l10n.filterAll,
              value: 'all',
              count: allCount,
            ),
            PillFilterItem(
              label: l10n.customerJobsInTransit,
              value: 'in_transit',
              count: inTransitCount,
            ),
            PillFilterItem(
              label: l10n.statusCompleted,
              value: 'completed',
              count: completedCount,
            ),
            PillFilterItem(
              label: l10n.statusCancelled,
              value: 'cancelled',
              count: cancelledCount,
            ),
          ],
          selectedValue: _selectedFilter,
          onSelected: (val) {
            setState(() => _selectedFilter = val);
          },
        ),
      ],
    );
  }

  Widget _buildJobCard(BuildContext context, Job job, AppLocalizations l10n) {
    final displayPrice =
        job.agreedPrice ?? job.proposedPrice ?? job.suggestedPrice;
    final displayId = job.id.length > 8 ? job.id.substring(0, 8) : job.id;
    final isCompleted = job.status.toLowerCase() == 'completed';
    final isCancelled = job.status.toLowerCase() == 'cancelled';
    final isUnavailable = job.status.toLowerCase() == 'unavailable';
    final isPendingDispatch = job.status.toLowerCase() == 'pending_dispatch';
    final isInTransit =
        !isCompleted && !isCancelled && !isUnavailable && !isPendingDispatch;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ThemedCard(
        key: Key('customer_job_card_${job.id}'),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => JobStatusScreen(job: job),
            ),
          );
        },
        padding: AppSpacing.sm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Tag + Service Name + Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    "${l10n.customerJobsOrder}$displayId",
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusBadge(status: job.status),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Payment & Price Row
            Row(
              children: [
                Icon(
                  Icons.payment,
                  size: AppIconSize.sm,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.paymentMethodLine(
                      AppTypography.uppercaseLabel(job.paymentMethod)),
                  style: AppTypography.bodySm.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isPendingDispatch) ...[
                  const Spacer(),
                  Text(
                    l10n.matchingCourierLabel,
                    style: AppTypography.bodySm.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else if (isUnavailable) ...[
                  const Spacer(),
                  Text(
                    l10n.statusUnavailable,
                    style: AppTypography.bodySm.copyWith(
                      color: context.semanticColors.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ] else if (displayPrice != null) ...[
                  const Spacer(),
                  Text(
                    "\$${displayPrice.toStringAsFixed(2)}",
                    style: AppTypography.titleMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),

            if (isUnavailable) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.allCouriersBusyDesc,
                style: AppTypography.caption.copyWith(
                  color: context.semanticColors.warning,
                ),
              ),
            ],

            // Progress bar (In Transit / Active)
            if (isInTransit) _buildJobProgress(job),

            // Cancellation reason alert
            if (isCancelled &&
                job.cancellationReason != null &&
                job.cancellationReason!.isNotEmpty)
              _buildCancellationReason(job.cancellationReason!),
          ],
        ),
      ),
    );
  }

  Widget _buildJobProgress(Job job) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: AppRadius.xxsBorder,
          child: Container(
            height: 4,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Row(
              children: [
                Expanded(
                  flex: job.status.toLowerCase() == 'active' ? 3 : 1,
                  child: Container(color: AppColors.secondary),
                ),
                Expanded(
                  flex: job.status.toLowerCase() == 'active' ? 1 : 3,
                  child: Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHigh),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCancellationReason(String reason) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: ColoredBox(
            color: AppColors.error.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: AppIconSize.xs,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.reasonLine(reason),
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.error,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
