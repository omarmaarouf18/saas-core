import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomerJobs();
    });
  }

  void _loadCustomerJobs() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final marketplace =
        Provider.of<MarketplaceProvider>(context, listen: false);
    marketplace.fetchCustomerJobs(auth.token);
  }

  @override
  Widget build(BuildContext context) {
    final marketplace = Provider.of<MarketplaceProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: widget.isEmbeddedInTab
          ? null
          : AppBar(
              title: const Text("My Orders"),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              actions: [
                IconButton(
                  key: const Key('refresh_customer_jobs_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: "Refresh",
                  onPressed: _loadCustomerJobs,
                ),
              ],
            ),
      body: Builder(
        builder: (context) {
          if (marketplace.isLoading && marketplace.customerJobs.isEmpty) {
            return const ThemedLoadingIndicator(
              key: Key('customer_jobs_loading'),
              message: "Loading orders...",
            );
          }

          if (marketplace.error != null && marketplace.customerJobs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ThemedErrorBanner(
                    key: const Key('customer_jobs_error_banner'),
                    message: marketplace.error!,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton.icon(
                    key: const Key('retry_customer_jobs_button'),
                    onPressed: _loadCustomerJobs,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Retry"),
                  ),
                ],
              ),
            );
          }

          if (marketplace.customerJobs.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => _loadCustomerJobs(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: AppSpacing.xl),
                  ThemedEmptyState(
                    key: Key('customer_jobs_empty_state'),
                    icon: Icons.receipt_long_outlined,
                    title: "No Orders Found",
                    description:
                        "You haven't placed any orders yet. Explore services in the marketplace to get started.",
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
              itemCount: marketplace.customerJobs.length,
              itemBuilder: (context, index) {
                final job = marketplace.customerJobs[index];
                final displayPrice =
                    job.agreedPrice ?? job.proposedPrice ?? job.suggestedPrice;

                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => JobStatusScreen(job: job),
                        ),
                      );
                    },
                    child: ThemedCard(
                      key: Key('customer_job_card_${job.id}'),
                      padding: AppSpacing.md,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  "Order #${job.id.length > 8 ? job.id.substring(0, 8) : job.id}",
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
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              const Icon(
                                Icons.payment,
                                size: 16,
                                color: AppColors.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                "Payment: ${job.paymentMethod.toUpperCase()}",
                                style: AppTypography.bodyMd.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 12,
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
                            const SizedBox(height: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.xs + 2),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: AppColors.error,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      "Reason: ${job.cancellationReason}",
                                      style: AppTypography.bodyMd.copyWith(
                                        color: AppColors.error,
                                        fontSize: 12,
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
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
