import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enum_labels.dart';
import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import '../customer/booking_rules.dart';
import '../customer/order/job_timeline.dart';
import '../customer/order/job_v2_sections.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_nav.dart';
import 'owner_rules.dart';
import 'owner_sheets.dart';
import 'owner_widgets.dart';

/// Owner order detail (O-Order). Reads the job from the loaded owner jobs,
/// so it follows every refresh. Shows only what the owner DTO carries (no
/// customer name); job model v2 (FE-V2-CONSUME): the phase chip, address
/// text, recipient and package with call buttons, the courier's phone, the
/// ETA, the delivery time and the timeline from `status_history` (legacy
/// jobs keep the "ordered" row only).
class OwnerOrderDetailPage extends StatefulWidget {
  const OwnerOrderDetailPage({super.key, required this.jobId});

  final String jobId;

  static Future<void> open(BuildContext context, String jobId) =>
      OwnerNavScope.of(context)
          .push<void>(context, (_) => OwnerOrderDetailPage(jobId: jobId));

  @override
  State<OwnerOrderDetailPage> createState() => _OwnerOrderDetailPageState();
}

class _OwnerOrderDetailPageState extends State<OwnerOrderDetailPage> {
  /// One action at a time: respond (approve / keep) or cancel.
  bool _busy = false;

  Future<void> _respond(Job job, String decision) async {
    if (_busy) return;
    final l10n = context.l10n;
    final data = context.read<OwnerDataController>();
    final owner = context.read<OwnerProvider>();
    final token = context.read<AuthProvider>().token;
    final approve = decision == 'accept';
    final name = courierNameOf(l10n, data, job.employeeId) ?? '';
    final ok = await showOwnerConfirmSheet(
      context,
      key: Key('own_respond_sheet_$decision'),
      title:
          approve ? l10n.ownCancelReqApproveTitle : l10n.ownCancelReqKeepTitle,
      message: approve
          ? l10n.ownCancelReqApproveBody
          : l10n.ownCancelReqKeepBody(name),
      confirmLabel: approve ? l10n.ownCancelReqApprove : l10n.ownCancelReqKeep,
      destructive: approve,
    );
    if (!ok || !mounted || token == null) return;
    setState(() => _busy = true);
    try {
      await owner.respondCancellation(
          jobId: job.id, decision: decision, ownerToken: token);
      if (!mounted) return;
      showOwnerNotice(context,
          approve ? l10n.ownCancelReqApproved : l10n.ownCancelReqDeclined);
    } catch (e) {
      if (!mounted) return;
      if (isConflict(e)) {
        // ADR-0027: the request was resolved meanwhile or ran out.
        showOwnerNotice(context, l10n.ownCancelReqConflict);
        await data.refreshJobs();
      } else {
        showOwnerNotice(context, friendlyErrorMessage(e),
            onRetry: () => _respond(job, decision));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Job job) async {
    if (_busy) return;
    final l10n = context.l10n;
    final owner = context.read<OwnerProvider>();
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    // Same refund wording rule as the old card: non-COD orders return the
    // held amount (else the agreed / proposed / suggested price).
    final cod = isCod(job);
    final held = (job.lockedEscrowAmount ?? 0) > 0
        ? job.lockedEscrowAmount!
        : (job.agreedPrice ?? job.proposedPrice ?? job.suggestedPrice ?? 0);
    setState(() => _busy = true);
    final done = await OwnerCancelOrderSheet.show(
      context,
      body: cod
          ? l10n.ownCancelSheetCod
          : l10n.ownCancelSheetHeld(formatMoney(l10n, held)),
      onConfirm: (reason) =>
          owner.cancelJob(jobId: job.id, reason: reason, ownerToken: token),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (done == true) {
      showOwnerNotice(
          context, cod ? l10n.ownCancelled : l10n.ownCancelledRefunded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final job = data.jobById(widget.jobId);

    if (job == null) {
      return Scaffold(
        backgroundColor: c.surface,
        appBar: ownerAppBar(context, title: l10n.ownOrderFallbackTitle),
        body: RefreshIndicator(
          onRefresh: data.refreshJobs,
          child: OwnerScrollableCenter(
            child: QdEmptyState(
              key: const Key('own_order_missing'),
              icon: Icons.receipt_long_outlined,
              title: l10n.ownOrderMissing,
              actionLabel: l10n.ownRefresh,
              onAction: data.refreshJobs,
            ),
          ),
        ),
      );
    }

    final extras = data.extrasOf(job.id);
    final status = QdJobStatus.fromBackend(job.status);
    final now = data.now();
    final ride = ownerJobIsRide(context.watch<OwnerProvider>().services, job);
    final phase = jobPhaseChip(l10n, job, ride: ride);
    final eta = jobEtaText(context, job, now: now, ride: ride);
    final delivered = jobCompletedAt(job);
    final courier = courierNameOf(l10n, data, job.employeeId);
    void notice(String m) => showOwnerNotice(context, m);
    final timeline = jobHistoryTimeline(context, job,
        key: const Key('own_order_timeline'),
        now: now,
        ride: ride,
        owner: true,
        courierName: courier);
    final r = job.recipient;
    final p = ride ? null : job.packageDetails;
    return Scaffold(
      key: const Key('own_order_page'),
      backgroundColor: c.surface,
      appBar: ownerAppBar(
        context,
        title: l10n.ownOrderTitle(jobRefIsolated(job)),
        trailing: phase == null
            ? QdStatusChip(label: status.label(l10n), tone: status.tone)
            : QdStatusChip(
                key: const Key('own_order_phase'),
                label: phase,
                tone: status.tone),
      ),
      body: RefreshIndicator(
        onRefresh: data.refreshJobs,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
          children: [
            if (hasPendingCancellationRequest(job)) ...[
              _CancellationRequestCard(
                job: job,
                courier: courierNameOf(l10n, data, job.employeeId) ??
                    l10n.ownCourierNone,
                now: data.now(),
                busy: _busy,
                onKeep: () => _respond(job, 'decline'),
                onApprove: () => _respond(job, 'accept'),
              ),
              const SizedBox(height: QdSpace.x4),
            ],
            if (extras.distanceReview != null) ...[
              QdBanner(
                key: const Key('own_distance_review'),
                tone: QdBannerTone.warning,
                icon: Icons.straighten,
                title: l10n.ownDistanceReviewTitle,
                message: l10n.ownDistanceReviewBody(
                  formatKm(extras.distanceReview!.actualKm),
                  formatKm(extras.distanceReview!.bookedKm),
                ),
              ),
              const SizedBox(height: QdSpace.x4),
            ],
            QdCard(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QdRouteLines(
                    compact: true,
                    pickup: jobPlaceLabel(l10n, job.location, withNote: true),
                    dropoff:
                        jobPlaceLabel(l10n, job.destination, withNote: true),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: QdButton.text(
                      key: const Key('own_order_map'),
                      label: l10n.ownSeeOnMap,
                      small: true,
                      onPressed: () => OwnerNavScope.of(context)
                          .openFleetMap(context, employeeId: job.employeeId),
                    ),
                  ),
                ],
              ),
            ),
            if (r != null || p != null) ...[
              const SizedBox(height: QdSpace.x4),
              OwnerInfoGroup(rows: [
                if (r != null)
                  OwnerInfoRow(
                    key: const Key('own_order_recipient'),
                    label: ride ? l10n.ordPassenger : l10n.ordRecipient,
                    value: [
                      if (r.name != null) r.name!,
                      if (r.phone != null) '\u2066${r.phone!}\u2069',
                    ].join(' · '),
                    note: r.notes,
                    trailing: r.phone == null
                        ? null
                        : QdIconButton(
                            key: const Key('own_call_recipient'),
                            icon: Icons.phone_outlined,
                            label: l10n.ownCallRecipient,
                            round: true,
                            onPressed: () =>
                                callPhone(context, r.phone!, notice: notice),
                          ),
                  ),
                if (p != null)
                  OwnerInfoRow(
                    key: const Key('own_order_package'),
                    label: l10n.ordPackage,
                    value: packageSizeLabel(l10n, p.size),
                    note: p.notes,
                  ),
              ]),
            ],
            const SizedBox(height: QdSpace.x4),
            OwnerInfoGroup(rows: [
              OwnerInfoRow(
                label: l10n.ownRowCustomer,
                value: l10n.ownCustomerRef(shortRefIsolated(job.userId)),
              ),
              OwnerInfoRow(
                label: l10n.ownRowCourier,
                value: courier ?? l10n.ownCourierNone,
                trailing: job.courierPhone == null
                    ? null
                    : QdIconButton(
                        key: const Key('own_call_courier'),
                        icon: Icons.phone_outlined,
                        label: l10n.ownCallCourier,
                        round: true,
                        onPressed: () => callPhone(context, job.courierPhone!,
                            notice: notice),
                      ),
              ),
              if (eta != null)
                OwnerInfoRow(
                    key: const Key('own_order_eta'),
                    label: l10n.ownRowEta,
                    value: eta),
              OwnerInfoRow(
                  label: l10n.ownRowPayment, value: _payment(l10n, job)),
              if (extras.actualCashAmount != null)
                OwnerInfoRow(
                  label: l10n.ownRowCashRecorded,
                  value: formatMoney(l10n, extras.actualCashAmount!),
                ),
              if (job.createdAt != null)
                OwnerInfoRow(
                  label: l10n.ownRowOrdered,
                  value: formatWhen(context, job.createdAt!, now: now),
                ),
              if (delivered != null)
                OwnerInfoRow(
                  key: const Key('own_order_delivered'),
                  label: l10n.ownRowDelivered,
                  value: formatWhen(context, delivered, now: now),
                ),
              if ((job.cancellationReason ?? '').trim().isNotEmpty)
                OwnerInfoRow(
                  label: l10n.ownRowCancelReason,
                  value: job.cancellationReason!.trim(),
                ),
            ]),
            if (timeline != null) ...[
              const SizedBox(height: QdSpace.x5),
              Semantics(
                header: true,
                child: Text(l10n.ownTimelineTitle,
                    style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
              ),
              const SizedBox(height: QdSpace.x3),
              timeline,
            ],
            if (ownerCanCancel(job)) ...[
              const SizedBox(height: QdSpace.x5),
              QdButton.destructive(
                key: const Key('own_order_cancel'),
                label: l10n.ownCancelOrder,
                fullWidth: true,
                onPressed: _busy ? null : () => _cancel(job),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _payment(AppLocalizations l10n, Job job) {
    final price = jobPrice(job);
    final method = paymentMethodLabel(l10n, job.paymentMethod);
    if (isCod(job)) {
      return price == null
          ? l10n.ownPayCashNoPrice
          : l10n.ownPayCash(formatMoney(l10n, price));
    }
    return price == null
        ? method
        : l10n.ownPayOther(method, formatMoney(l10n, price));
  }
}

/// O-Order's cancellation request card: who, why, since when; keep or
/// approve.
class _CancellationRequestCard extends StatelessWidget {
  const _CancellationRequestCard({
    required this.job,
    required this.courier,
    required this.now,
    required this.busy,
    required this.onKeep,
    required this.onApprove,
  });

  final Job job;
  final String courier;
  final DateTime now;
  final bool busy;
  final VoidCallback onKeep;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final reason = job.cancellationRequestReason?.trim() ?? '';
    final at = job.cancellationRequestedAt;
    return Container(
      key: const Key('own_cancel_request'),
      padding: const EdgeInsetsDirectional.all(QdSpace.x4),
      decoration: BoxDecoration(
        color: c.warningBg,
        borderRadius: BorderRadius.circular(QdRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: QdSize.icon, color: c.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.ownCancelReqTitle(courier),
                        style:
                            QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                    const SizedBox(height: QdSpace.x1),
                    Text(
                      reason.isEmpty
                          ? l10n.ownCancelReqNoReason
                          : l10n.ownCancelReqQuote(reason),
                      style: QdText.body.copyWith(color: c.textPrimary),
                    ),
                    if (at != null) ...[
                      const SizedBox(height: QdSpace.x1),
                      Text(
                        l10n.ownCancelReqSince(
                            formatAgo(context, at, now: now)),
                        style: QdText.caption.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: QdSpace.x3),
          Row(
            children: [
              Expanded(
                child: QdButton.secondary(
                  key: const Key('own_cancel_request_keep'),
                  label: l10n.ownCancelReqKeep,
                  small: true,
                  fullWidth: true,
                  onPressed: busy ? null : onKeep,
                ),
              ),
              const SizedBox(width: QdSpace.x2),
              Expanded(
                child: QdButton(
                  key: const Key('own_cancel_request_approve'),
                  label: l10n.ownCancelReqApprove,
                  small: true,
                  fullWidth: true,
                  onPressed: busy ? null : onApprove,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
