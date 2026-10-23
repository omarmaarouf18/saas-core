import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../ui/qd_ui.dart';
import '../customer_format.dart';
import 'job_v2_sections.dart';
import 'order_controller.dart';
import 'order_sections.dart';
import 'order_view.dart';

/// Cancelled: the reason as the server gave it, or the price-proposal
/// expiry explained in words; the timeline when the job has a history.
class OrderCancelledView extends StatelessWidget {
  const OrderCancelledView({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctl = context.read<OrderController>();
    final expired = isProposalExpired(job, ctl.now());
    final reason = job.cancellationReason?.trim() ?? '';
    return OrderLayout(
      key: const Key('ord_view_cancelled'),
      children: [
        OrderRefRow(job: job),
        OrderStateHeader(
          icon: expired ? Icons.timer_off_outlined : Icons.close,
          tone: QdTone.danger,
          title:
              expired ? l10n.ordProposalExpiredTitle : l10n.ordCancelledTitle,
          body: expired ? l10n.ordProposalExpiredBody : l10n.ordCancelledBody,
        ),
        if (!expired && reason.isNotEmpty) ...[
          const SizedBox(height: QdSpace.x3),
          Text(
            l10n.ordCancelReason(reason),
            key: const Key('ord_cancel_reason'),
            textAlign: TextAlign.center,
            style: QdText.body.copyWith(color: c.textPrimary),
          ),
        ],
        if (jobHistoryTimeline(context, job,
                key: const Key('ord_timeline'),
                now: ctl.now(),
                ride: orderIsRide(context, job),
                courierName: context.watch<OrderController>().courierName)
            case final timeline?) ...[
          const SizedBox(height: QdSpace.x5),
          timeline,
        ],
        const SizedBox(height: QdSpace.x5),
        OrderRouteCard(job: job, priceMode: OrderPriceMode.plain),
      ],
    );
  }
}

/// Escrow reconciliation: the company checks the trip; nothing for the
/// customer to do. Shows the amount on hold when the job carries it.
class OrderUnderReviewView extends StatelessWidget {
  const OrderUnderReviewView({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final held = job.lockedEscrowAmount;
    return OrderLayout(
      key: const Key('ord_view_under_review'),
      children: [
        OrderRefRow(job: job),
        OrderStateHeader(
          icon: Icons.fact_check_outlined,
          tone: QdTone.warning,
          title: l10n.ordReviewTitle,
          body: l10n.ordReviewBody,
        ),
        const SizedBox(height: QdSpace.x5),
        OrderRouteCard(job: job, priceMode: OrderPriceMode.toPay),
        if (held != null) ...[
          const SizedBox(height: QdSpace.x3),
          QdPriceBreakdown(
            key: const Key('ord_on_hold'),
            lines: [
              QdPriceLine(
                  label: l10n.ordOnHold, value: formatMoney(l10n, held)),
            ],
          ),
        ],
      ],
    );
  }
}

/// A status this client does not know: summary only, no actions.
class OrderUnknownView extends StatelessWidget {
  const OrderUnknownView({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OrderLayout(
      key: const Key('ord_view_unknown'),
      children: [
        OrderRefRow(job: job),
        OrderStateHeader(
          icon: Icons.help_outline,
          title: l10n.ordUnknownTitle,
          body: l10n.ordUnknownBody,
        ),
        const SizedBox(height: QdSpace.x5),
        OrderRouteCard(job: job, priceMode: OrderPriceMode.plain),
      ],
    );
  }
}
