import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/job_rules.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import '../customer/order/job_v2_sections.dart';
import 'order_detail_page.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_nav.dart';
import 'owner_rules.dart';
import 'owner_widgets.dart';

/// Owner orders (O-Orders): ongoing / done / cancelled tabs
/// ([ownerOrdersTabOf], on core/job_rules.dart), search by order id or
/// courier name, pull to refresh, tap → [OwnerOrderDetailPage].
///
/// A shell tab by default; [standalone] pushes it as its own page with a
/// back button (a courier's "all orders" link, prefilled with their name).
class OwnerOrdersPage extends StatefulWidget {
  const OwnerOrdersPage(
      {super.key, this.initialQuery = '', this.standalone = false});

  final String initialQuery;
  final bool standalone;

  static Future<void> open(BuildContext context, {String query = ''}) =>
      OwnerNavScope.of(context).push<void>(context,
          (_) => OwnerOrdersPage(initialQuery: query, standalone: true));

  @override
  State<OwnerOrdersPage> createState() => _OwnerOrdersPageState();
}

class _OwnerOrdersPageState extends State<OwnerOrdersPage> {
  OwnerOrdersTab _tab = OwnerOrdersTab.ongoing;
  late final TextEditingController _search =
      TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final all = sortNewestFirst(data.jobs);
    final byTab = {
      for (final t in OwnerOrdersTab.values)
        t: all.where((j) => ownerOrdersTabOf(j) == t).toList(),
    };
    final query = _search.text;
    final shown = byTab[_tab]!
        .where((j) => orderMatchesQuery(
            j, query, data.employeeById(j.employeeId)?.displayName,
            customerName: data.extrasOf(j.id).customerName))
        .toList();

    final header = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(QdSpace.gutter,
          widget.standalone ? QdSpace.x2 : 28, QdSpace.gutter, QdSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.standalone) ...[
            Semantics(
              header: true,
              child: Text(l10n.ownOrdersTitle,
                  style: QdText.screenTitle.copyWith(color: c.textPrimary)),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            key: const Key('own_orders_search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: QdText.body.copyWith(color: c.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.ownOrdersSearchHint,
              prefixIcon: Icon(Icons.search, color: c.textSecondary),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.ownClearSearch,
                      icon: Icon(Icons.close, color: c.textSecondary),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: l10n.ownOrdersKind,
            container: true,
            child: QdSegmented<OwnerOrdersTab>(
              key: const Key('own_orders_tabs'),
              selected: _tab,
              onChanged: (t) => setState(() => _tab = t),
              segments: [
                QdSegment(
                    value: OwnerOrdersTab.ongoing,
                    label: l10n
                        .ownTabOngoing(byTab[OwnerOrdersTab.ongoing]!.length)),
                QdSegment(value: OwnerOrdersTab.done, label: l10n.ownTabDone),
                QdSegment(
                    value: OwnerOrdersTab.cancelled,
                    label: l10n.ownTabCancelled),
              ],
            ),
          ),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: RefreshIndicator(
            onRefresh: data.refresh,
            child: _list(context, data, shown, byTab[_tab]!.isEmpty),
          ),
        ),
      ],
    );

    if (widget.standalone) {
      return Scaffold(
        key: const Key('own_orders_page'),
        backgroundColor: c.surface,
        appBar: ownerAppBar(context, title: l10n.ownOrdersTitle),
        body: body,
      );
    }
    return SafeArea(
        key: const Key('own_orders_page'), bottom: false, child: body);
  }

  Widget _list(BuildContext context, OwnerDataController data, List<Job> jobs,
      bool tabEmpty) {
    final l10n = context.l10n;
    if (jobs.isEmpty) {
      if (!data.loaded) {
        return const OwnerScrollableCenter(
          key: Key('own_orders_loading'),
          child: CircularProgressIndicator(),
        );
      }
      if (data.jobsError != null && data.jobs.isEmpty) {
        return OwnerScrollableCenter(
          key: const Key('own_orders_error'),
          child: QdErrorState(
            title: l10n.ownOrdersLoadError,
            retrying: data.loading,
            onRetry: data.refresh,
          ),
        );
      }
      if (!tabEmpty) {
        return OwnerScrollableCenter(
          key: const Key('own_orders_no_match'),
          child: QdEmptyState(
            icon: Icons.search_off_outlined,
            title: l10n.ownOrdersNoMatch,
            actionLabel: l10n.ownClearSearch,
            onAction: () => setState(_search.clear),
          ),
        );
      }
      return OwnerScrollableCenter(
        key: const Key('own_orders_empty'),
        child: QdEmptyState(
          icon: Icons.receipt_long_outlined,
          title: switch (_tab) {
            OwnerOrdersTab.ongoing => l10n.ownNoOngoing,
            OwnerOrdersTab.done => l10n.ownNoDone,
            OwnerOrdersTab.cancelled => l10n.ownNoCancelled,
          },
          body: l10n.ownOrdersEmptyBody,
        ),
      );
    }

    final c = QdColors.of(context);
    return ListView(
      key: const Key('own_orders_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(
          QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x5),
      children: [
        // Stale list + failed refresh: say so above the rows.
        if (data.jobsError != null) ...[
          QdBanner(
            key: const Key('own_orders_stale'),
            tone: QdBannerTone.danger,
            icon: Icons.error_outline,
            message: l10n.ownRefreshFailed,
            actionLabel: l10n.retry,
            onAction: data.refresh,
          ),
          const SizedBox(height: QdSpace.x3),
        ],
        // Rows paint their own fill, so the border is a foreground
        // decoration on top of them.
        ClipRRect(
          borderRadius: BorderRadius.circular(QdRadius.card),
          child: Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(QdRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < jobs.length; i++) ...[
                  if (i > 0) Container(height: 1, color: c.fillMuted),
                  OwnerOrderRow(job: jobs[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One O-Orders row: reference · courier, a one-line state summary and the
/// status chips (with "cancellation requested"; the phase, e.g. "Picked
/// up", instead of "Active" when the job has one). A row with a pending
/// request is tinted.
class OwnerOrderRow extends StatelessWidget {
  const OwnerOrderRow({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final courier = data.employeeById(job.employeeId)?.displayName;
    // The customer's name when the server has it (USER-AUTH-BE item 3);
    // the courier then moves to the summary line.
    final customer = data.extrasOf(job.id).customerName;
    final title = customer != null
        ? '$customer · ${jobRefIsolated(job)}'
        : courier == null
            ? jobRefIsolated(job)
            : '${jobRefIsolated(job)} · $courier';
    final requested = hasPendingCancellationRequest(job);
    final phase = jobPhaseChip(l10n, job,
        ride: ownerJobIsRide(context.watch<OwnerProvider>().services, job));
    return Material(
      color: requested ? c.fillSubtle : c.surface,
      child: InkWell(
        key: Key('own_order_${job.id}'),
        onTap: () => OwnerOrderDetailPage.open(context, job.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: QdSpace.x4, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        customer != null && courier != null
                            ? '$courier · ${_summary(context, data)}'
                            : _summary(context, data),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QdText.caption.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: QdSpace.x3),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: requested ? 180 : 140),
                  // A pending request is what the owner must act on, so it
                  // replaces the status chip here (O-Orders); the detail
                  // page shows both.
                  child: requested
                      ? QdStatusChip(
                          label: QdJobStatus.cancellationRequested.label(l10n),
                          tone: QdJobStatus.cancellationRequested.tone,
                        )
                      : phase != null
                          ? QdStatusChip(
                              label: phase,
                              tone: QdJobStatus.fromBackend(job.status).tone)
                          : QdJobStatusChips(status: job.status),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _summary(BuildContext context, OwnerDataController data) {
    final l10n = context.l10n;
    final status = QdJobStatus.fromBackend(job.status);
    final proposed = job.proposedPrice;
    final base = job.agreedPrice ?? job.suggestedPrice;
    if (status == QdJobStatus.awaitingPrice && proposed != null) {
      return base == null
          ? l10n.ownProposalOnly(formatMoney(l10n, proposed))
          : l10n.ownProposalLine(
              formatMoney(l10n, proposed), formatMoney(l10n, base));
    }
    if (status == QdJobStatus.pendingDispatch) {
      final offered = courierNameOf(l10n, data, job.currentOfferedEmployeeId);
      if (offered != null) return l10n.ownOfferedTo(offered);
    }
    final to = l10n.custToPlace(jobPlaceLabel(l10n, job.destination));
    if (isOngoing(job) || job.createdAt == null) return to;
    return '${formatWhen(context, job.createdAt!, now: data.now())} · $to';
  }
}
