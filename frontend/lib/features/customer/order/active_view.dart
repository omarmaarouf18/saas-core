import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../ui/qd_ui.dart';
import '../../account/support/new_complaint_sheet.dart';
import '../customer_format.dart';
import 'job_v2_sections.dart';
import 'order_controller.dart';
import 'order_sections.dart';
import 'track_map.dart';

/// active / assigned (A-Track): the live map on top, then the phase ("on
/// the way to you") and ETA when the job has them, the courier with chat
/// and a call button while the server shares the phone, the timeline
/// (from `status_history`; legacy jobs keep the created-at-only steps),
/// the route, recipient, package and price, and "open a complaint" (the
/// FE-AUTH-ACCOUNT complaint sheet, this order preselected).
class OrderActiveView extends StatefulWidget {
  const OrderActiveView({super.key, required this.job});

  final Job job;

  @override
  State<OrderActiveView> createState() => _OrderActiveViewState();
}

class _OrderActiveViewState extends State<OrderActiveView> {
  final _map = GlobalKey<OrderTrackMapState>();

  Future<void> _refresh() async {
    final ctl = context.read<OrderController>();
    await Future.wait([
      ctl.refresh(),
      if (_map.currentState != null) _map.currentState!.rehydrate(),
    ]);
  }

  Future<void> _complain() async {
    final ticket =
        await NewComplaintSheet.show(context, preselectedJobId: widget.job.id);
    if (ticket != null && mounted) {
      showOrderNotice(context, context.l10n.supSent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final job = widget.job;
    final ctl = context.watch<OrderController>();
    final name = ctl.courierName;
    final now = ctl.now();
    final ride = orderIsRide(context, job);
    final phase = jobPhaseText(l10n, job, ride: ride);
    final eta = jobEtaText(context, job, now: now, ride: ride);
    return OrderLayout(
      key: const Key('ord_view_active'),
      onRefresh: _refresh,
      top: OrderTrackMap(key: _map, job: job),
      children: [
        const SizedBox(height: QdSpace.x3),
        OrderRefRow(job: job),
        const SizedBox(height: QdSpace.x2),
        Semantics(
          header: true,
          child: Text(phase ?? l10n.ordActiveTitle,
              key: const Key('ord_phase'),
              style: QdText.header.copyWith(color: c.textPrimary)),
        ),
        const SizedBox(height: 2),
        Text(eta ?? l10n.ordActiveSub,
            key: eta == null ? null : const Key('ord_eta'),
            style: eta == null
                ? QdText.secondary.copyWith(color: c.textSecondary)
                : QdText.bodyStrong.copyWith(color: c.textPrimary)),
        const SizedBox(height: QdSpace.x4),
        OrderCourierCard(
          key: const Key('ord_courier'),
          name: name,
          title: name ?? l10n.ordCourierFallback,
          subtitle: orderCompanyName(context, job),
          phone: job.courierPhone,
          onChat: () => openCourierChat(context, job),
        ),
        const SizedBox(height: QdSpace.x5),
        jobHistoryTimeline(context, job,
                key: const Key('ord_timeline'),
                now: now,
                ride: ride,
                courierName: name) ??
            OrderTimeline(job: job, courierName: name, now: now),
        const SizedBox(height: QdSpace.x5),
        OrderRouteCard(job: job, priceMode: OrderPriceMode.toPay),
        const SizedBox(height: QdSpace.x2),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: QdButton.text(
            key: const Key('ord_complaint'),
            label: l10n.ordComplaint,
            icon: Icons.report_problem_outlined,
            onPressed: _complain,
          ),
        ),
      ],
    );
  }
}

/// Legacy timeline, for jobs without `status_history` (no per-status
/// times except `created_at`, no picked-up step): ordered → courier
/// accepted → on the way → delivered. `assigned` (client alias) stops at
/// "accepted".
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({
    super.key,
    required this.job,
    required this.now,
    this.courierName,
  });

  final Job job;
  final String? courierName;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final created = job.createdAt;
    final moving = job.status.trim().toLowerCase() == 'active';
    return Semantics(
      label: l10n.ordSteps,
      container: true,
      child: QdTimeline(
        key: const Key('ord_timeline'),
        steps: [
          QdTimelineStep(
            label: l10n.ordStepOrdered,
            state: QdTimelineState.done,
            time:
                created == null ? null : formatWhen(context, created, now: now),
          ),
          QdTimelineStep(
            label: courierName == null
                ? l10n.ordStepAcceptedNoName
                : l10n.ordStepAccepted(courierName!),
            state: moving ? QdTimelineState.done : QdTimelineState.current,
          ),
          QdTimelineStep(
            label: l10n.ordStepOnTheWay,
            state: moving ? QdTimelineState.current : QdTimelineState.upcoming,
            time: moving ? l10n.ordStepNow : null,
          ),
          QdTimelineStep(
            label: l10n.ordStepDelivered,
            state: QdTimelineState.upcoming,
          ),
        ],
      ),
    );
  }
}
