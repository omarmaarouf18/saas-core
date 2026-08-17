import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomerJobs();
    });
  }

  Future<void> _loadCustomerJobs() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token != null) {
      await Provider.of<MarketplaceProvider>(context, listen: false)
          .fetchCustomerJobs(auth.token!);
    }
  }

  List<Job> _filterJobs(List<Job> allJobs) {
    if (_selectedFilter == 'all') return allJobs;
    if (_selectedFilter == 'in_transit') {
      return allJobs.where((j) {
        final s = j.status.toLowerCase();
        return s == 'active' || s == 'pending' || s == 'assigned';
      }).toList();
    }
    if (_selectedFilter == 'completed') {
      return allJobs
          .where((j) => j.status.toLowerCase() == 'completed')
          .toList();
    }
    if (_selectedFilter == 'cancelled') {
      return allJobs
          .where((j) => j.status.toLowerCase() == 'cancelled')
          .toList();
    }
    return allJobs;
  }

  @override
  Widget build(BuildContext context) {
    final marketplace = Provider.of<MarketplaceProvider>(context);
    final l10n = context.l10n;

    final filteredJobs = _filterJobs(marketplace.customerJobs);

    final inTransitCount = marketplace.customerJobs.where((j) {
      final s = j.status.toLowerCase();
      return s == 'active' || s == 'pending' || s == 'assigned';
    }).length;
    final completedCount = marketplace.customerJobs
        .where((j) => j.status.toLowerCase() == 'completed')
        .length;
    final cancelledCount = marketplace.customerJobs
        .where((j) => j.status.toLowerCase() == 'cancelled')
        .length;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: widget.isEmbeddedInTab
          ? null
          : AppBar(
              title: Text(l10n.customerJobsTitle),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
      body: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          // Horizontal Pill Filter Bar
          PillFilterBar<String>(
            items: [
              PillFilterItem(
                label: 'All',
                value: 'all',
                count: marketplace.customerJobs.length,
              ),
              PillFilterItem(
                label: 'In Transit',
                value: 'in_transit',
                count: inTransitCount,
              ),
              PillFilterItem(
                label: 'Completed',
                value: 'completed',
                count: completedCount,
              ),
              PillFilterItem(
                label: 'Cancelled',
                value: 'cancelled',
                count: cancelledCount,
              ),
            ],
            selectedValue: _selectedFilter,
            onSelected: (val) {
              setState(() => _selectedFilter = val);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: Builder(
              builder: (context) {
                if (marketplace.isLoading && marketplace.customerJobs.isEmpty) {
                  return ThemedLoadingIndicator(
                    key: const Key('customer_jobs_loading'),
                    message: l10n.customerOrdersLoading,
                  );
                }

                if (marketplace.error != null &&
                    marketplace.customerJobs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ThemedErrorBanner(
                          key: const Key('customer_jobs_error_banner'),
                          message: marketplace.error!,
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
                  );
                }

                if (filteredJobs.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => _loadCustomerJobs(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: AppSpacing.xl),
                        ThemedEmptyState(
                          key: const Key('customer_jobs_empty_state'),
                          icon: Icons.receipt_long_outlined,
                          title: l10n.customerJobsEmpty,
                          description: l10n.customerJobsEmptyDescription,
                          actionText: "Browse Services",
                          onActionPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _loadCustomerJobs(),
                  child: ListView.builder(
                    key: const Key('customer_jobs_list'),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: filteredJobs.length,
                    itemBuilder: (context, index) {
                      final job = filteredJobs[index];
                      final displayPrice = job.agreedPrice ??
                          job.proposedPrice ??
                          job.suggestedPrice;

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
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      "${l10n.customerJobsOrder}${job.id.length > 8 ? job.id.substring(0, 8) : job.id}",
                                      style: AppTypography.titleMd.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  StatusBadge(status: job.status),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.payment,
                                    size: AppIconSize.sm,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    "Payment: ${job.paymentMethod.toUpperCase()}",
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  if (displayPrice != null) ...[
                                    const Spacer(),
                                    Text(
                                      "\$${displayPrice.toStringAsFixed(2)}",
                                      style: AppTypography.titleMd.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (job.status == 'cancelled' &&
                                  job.cancellationReason != null &&
                                  job.cancellationReason!.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.xs),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.error.withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xs),
                                  ),
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
                                          "Reason: ${job.cancellationReason!}",
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
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
