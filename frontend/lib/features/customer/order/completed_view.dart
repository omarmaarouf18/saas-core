import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../ui/qd_ui.dart';
import 'order_controller.dart';
import 'order_sections.dart';
import 'rating_page.dart';

/// completed: what was paid, the route, and a rate button until the
/// customer rated (then a thank-you line), as in the old screen.
class OrderCompletedView extends StatelessWidget {
  const OrderCompletedView({super.key, required this.job});

  final Job job;

  Future<void> _rate(BuildContext context) async {
    final ctl = context.read<OrderController>();
    final l10n = context.l10n;
    final done = await CustomerRatingPage.open(context,
        job: job, courierName: ctl.courierName);
    if (done == true && context.mounted) {
      ctl.markRated();
      showOrderNotice(context, l10n.ordRatedThanks);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctl = context.watch<OrderController>();
    final name = ctl.courierName;
    final ratesCourier = (job.employeeId?.trim() ?? '').isNotEmpty;
    final rateLabel = !ratesCourier
        ? l10n.ordRateCompany
        : name == null
            ? l10n.ordRateCourierNoName
            : l10n.ordRateCourier(name);
    return OrderLayout(
      key: const Key('ord_view_completed'),
      footer: ctl.rated
          ? null
          : QdButton(
              key: const Key('ord_rate'),
              label: rateLabel,
              icon: Icons.star_outline,
              fullWidth: true,
              onPressed: () => _rate(context),
            ),
      children: [
        OrderRefRow(job: job),
        OrderDeliveredHeader(job: job),
        if (ctl.rated) ...[
          const SizedBox(height: QdSpace.x3),
          Row(
            key: const Key('ord_rated'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 18, color: c.success),
              const SizedBox(width: QdSpace.x2),
              Flexible(
                child: Text(l10n.ordRatedThanks,
                    style: QdText.bodyStrong.copyWith(color: c.success)),
              ),
            ],
          ),
        ],
        const SizedBox(height: QdSpace.x5),
        OrderRouteCard(job: job, priceMode: OrderPriceMode.paid),
      ],
    );
  }
}
