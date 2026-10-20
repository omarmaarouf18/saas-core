import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/job_rules.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../models/marketplace_service.dart';
import '../../providers/marketplace_provider.dart';
import '../../ui/qd_ui.dart';
import 'customer_format.dart';
import 'customer_jobs_controller.dart';
import 'customer_nav.dart';

enum OrdersTab { ongoing, past }

/// My orders (A-Orders): ongoing and past tabs split by core/job_rules.dart
/// (so awaiting-price and dispatching jobs are "ongoing"). Jobs that are
/// neither ongoing nor finished (unknown status) are listed under past.
class CustomerOrdersPage extends StatefulWidget {
  const CustomerOrdersPage(
      {super.key, required this.onBrowseServices, this.now});

  final VoidCallback onBrowseServices;

  /// Clock for "Today · time" (tests).
  final DateTime Function()? now;

  @override
  State<CustomerOrdersPage> createState() => _CustomerOrdersPageState();
}

class _CustomerOrdersPageState extends State<CustomerOrdersPage> {
  OrdersTab _tab = OrdersTab.ongoing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final jobsCtl = context.watch<CustomerJobsController>();
    final marketplace = context.watch<MarketplaceProvider>();
    final all = sortNewestFirst(marketplace.customerJobs);
    final ongoing = all.where(isOngoing).toList();
    final past = all.where((j) => !isOngoing(j)).toList();
    final shown = _tab == OrdersTab.ongoing ? ongoing : past;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, 28, QdSpace.gutter, QdSpace.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(l10n.custOrdersTitle,
                      style: QdText.screenTitle.copyWith(color: c.textPrimary)),
                ),
                const SizedBox(height: QdSpace.x4),
                Semantics(
                  label: l10n.custOrdersKind,
                  container: true,
                  child: QdSegmented<OrdersTab>(
                    key: const Key('cust_orders_tabs'),
                    selected: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                    segments: [
                      QdSegment(
                          value: OrdersTab.ongoing,
                          label: l10n.custTabOngoing(ongoing.length)),
                      QdSegment(value: OrdersTab.past, label: l10n.custTabPast),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: jobsCtl.refresh,
              child: _list(context, jobsCtl, shown, marketplace.services),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, CustomerJobsController jobsCtl,
      List<Job> jobs, List<MarketplaceService> services) {
    final l10n = context.l10n;
    // Every state stays scrollable so pull-to-refresh always works.
    Widget scrollableCenter(Widget child, Key key) => LayoutBuilder(
          key: key,
          builder: (context, box) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(child: child),
            ),
          ),
        );

    if (jobs.isEmpty) {
      if (jobsCtl.loading || !jobsCtl.loaded) {
        return scrollableCenter(const CircularProgressIndicator(),
            const Key('cust_orders_loading'));
      }
      if (jobsCtl.error != null) {
        return scrollableCenter(
          QdErrorState(
            title: l10n.custJobsLoadError,
            onRetry: jobsCtl.refresh,
          ),
          const Key('cust_orders_error'),
        );
      }
      final ongoingTab = _tab == OrdersTab.ongoing;
      return scrollableCenter(
        QdEmptyState(
          icon: Icons.receipt_long_outlined,
          title: ongoingTab ? l10n.custNoOngoingTitle : l10n.custNoPastTitle,
          body: l10n.custOrdersEmptyBody,
          actionLabel: l10n.custBrowseServices,
          onAction: widget.onBrowseServices,
        ),
        const Key('cust_orders_empty'),
      );
    }

    return ListView.separated(
      key: const Key('cust_orders_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(
          QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x5),
      itemCount: jobs.length + (jobsCtl.error != null ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: QdSpace.x3),
      itemBuilder: (context, i) {
        // Stale list + failed refresh: say so above the cards.
        if (jobsCtl.error != null) {
          if (i == 0) {
            return QdBanner(
              tone: QdBannerTone.danger,
              icon: Icons.error_outline,
              message: l10n.custJobsLoadError,
              actionLabel: l10n.retry,
              onAction: jobsCtl.refresh,
            );
          }
          i -= 1;
        }
        final job = jobs[i];
        return _OrderCard(
          key: Key('cust_order_${job.id}'),
          job: job,
          service: serviceOfJob(job, services),
          now: widget.now,
          onTap: () async {
            await CustomerNavScope.of(context).openOrder(context, job);
            if (mounted) await jobsCtl.refresh();
          },
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    super.key,
    required this.job,
    required this.service,
    required this.onTap,
    this.now,
  });

  final Job job;
  final MarketplaceService? service;
  final VoidCallback onTap;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ongoing = isOngoing(job);
    final created = job.createdAt;
    final when = created == null
        ? jobRef(job)
        : formatWhen(context, created, now: now?.call());
    final price = jobPrice(job);
    final cancelled =
        QdJobStatus.fromBackend(job.status) == QdJobStatus.cancelled;
    final title = service == null
        ? l10n.custOrderFallback
        : categoryLabel(l10n, service!.category);
    final priceText = price == null
        ? null
        : Text(
            formatMoney(l10n, price),
            style: (ongoing ? QdText.rowTitleSm : QdText.bodyStrong).copyWith(
              fontWeight: FontWeight.w700,
              // Strike-through old price: the one allowed use of textMuted.
              color: cancelled ? c.textMuted : c.textPrimary,
              decoration: cancelled ? TextDecoration.lineThrough : null,
              decorationColor: c.textMuted,
            ),
          );

    final header = Row(
      children: [
        QdIconTile(
          icon: categoryIcon(service?.category),
          tone: ongoing ? QdIconTileTone.gold : QdIconTileTone.muted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
              const SizedBox(height: 2),
              Text(
                ongoing
                    ? when
                    : '$when · ${l10n.custToPlace(jobPlaceLabel(l10n, job.destination))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QdText.caption.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: QdSpace.x2),
        // Capped width: long chips ("No courier available") wrap or
        // ellipsize instead of overflowing at 360 dp, and the title keeps
        // the rest of the row.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kChipsMaxWidth),
          child: ongoing
              ? QdJobStatusChips(
                  status: job.status,
                  cancellationRequestStatus: job.cancellationRequestStatus,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (priceText != null) ...[
                      priceText,
                      const SizedBox(height: QdSpace.x1),
                    ],
                    QdJobStatusChips(
                      status: job.status,
                      cancellationRequestStatus: job.cancellationRequestStatus,
                    ),
                  ],
                ),
        ),
      ],
    );

    if (!ongoing) {
      return QdCard(
        onTap: onTap,
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: QdSpace.x4, vertical: 14),
        child: header,
      );
    }

    return QdCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: QdSpace.x3),
          QdRouteLines(
            compact: true,
            pickup: jobPlaceLabel(l10n, job.location),
            dropoff: jobPlaceLabel(l10n, job.destination),
          ),
          const SizedBox(height: QdSpace.x3),
          Container(height: 1, color: c.fillMuted),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: job.paymentMethod.trim().toLowerCase() == 'cod'
                    ? Text(l10n.custCashOnDelivery,
                        style:
                            QdText.secondary.copyWith(color: c.textSecondary))
                    : const SizedBox.shrink(),
              ),
              if (priceText != null) priceText,
            ],
          ),
        ],
      ),
    );
  }
}
