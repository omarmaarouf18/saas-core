import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../ui/qd_ui.dart';
import 'cancel_sheet.dart';
import 'order_controller.dart';
import 'order_sections.dart';
import 'order_view.dart';

/// pending / pending_dispatch (A-Searching): the offer goes to couriers one
/// by one. While a courier is looking at it (`current_offered_employee_id`
/// during dispatch) the customer can already chat with them. The customer
/// may cancel here, as in the old screen.
class OrderSearchingView extends StatelessWidget {
  const OrderSearchingView({super.key, required this.job});

  final Job job;

  Future<void> _cancel(BuildContext context) async {
    final ctl = context.read<OrderController>();
    final l10n = context.l10n;
    // Same notice rule as the old screen: a refund is mentioned only for
    // a non-COD job that was already charged (not while dispatching).
    final refunded = job.paymentMethod.trim().toLowerCase() != 'cod' &&
        job.status.trim().toLowerCase() != 'pending_dispatch';
    final done = await CancelOrderSheet.show(context, onConfirm: ctl.cancel);
    if (done == true && context.mounted) {
      showOrderNotice(
          context, refunded ? l10n.ordCancelDoneRefunded : l10n.ordCancelDone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ctl = context.watch<OrderController>();
    final company = orderCompanyName(context, job);
    final offered =
        job.employeeId == null && OrderController.courierIdOf(job) != null;
    final name = offered ? ctl.courierName : null;
    return OrderLayout(
      key: const Key('ord_view_searching'),
      footer: canCustomerCancel(job)
          ? QdButton.destructive(
              key: const Key('ord_cancel'),
              label: l10n.ordCancelOrder,
              fullWidth: true,
              onPressed: () => _cancel(context),
            )
          : null,
      children: [
        OrderStateHeader(
          icon: Icons.search,
          illustration: const QdRings(),
          title: l10n.ordSearchingTitle,
          body: company == null
              ? l10n.ordSearchingBody
              : l10n.ordSearchingBodyCompany(company),
        ),
        const SizedBox(height: QdSpace.x5),
        if (offered) ...[
          OrderCourierCard(
            key: const Key('ord_offered_courier'),
            name: name,
            title: name == null
                ? l10n.ordOfferedTitleNoName
                : l10n.ordOfferedTitle(name),
            subtitle: l10n.ordOfferedSub,
            onChat: () => openCourierChat(context, job),
          ),
          const SizedBox(height: QdSpace.x5),
        ],
        OrderRouteCard(job: job),
      ],
    );
  }
}

/// unavailable: nobody accepted. "Order again" books the same service,
/// locations, notes and payment method (the old retry), and the page
/// follows the new job.
class OrderUnavailableView extends StatefulWidget {
  const OrderUnavailableView({super.key, required this.job});

  final Job job;

  @override
  State<OrderUnavailableView> createState() => _OrderUnavailableViewState();
}

class _OrderUnavailableViewState extends State<OrderUnavailableView> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    final l10n = context.l10n;
    final ctl = context.read<OrderController>();
    setState(() => _retrying = true);
    try {
      final fresh = await ctl.retryBooking();
      if (!mounted) return;
      if (fresh != null) showOrderNotice(context, l10n.ordRetryBooked);
    } catch (e) {
      if (mounted) showOrderNotice(context, friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OrderLayout(
      key: const Key('ord_view_unavailable'),
      footer: QdButton(
        key: const Key('ord_retry_booking'),
        label: l10n.ordRetryBooking,
        icon: Icons.refresh,
        fullWidth: true,
        loading: _retrying,
        onPressed: _retry,
      ),
      children: [
        OrderRefRow(job: widget.job),
        OrderStateHeader(
          icon: Icons.schedule,
          tone: QdTone.warning,
          title: l10n.ordUnavailableTitle,
          body: l10n.ordUnavailableBody,
        ),
        const SizedBox(height: QdSpace.x5),
        OrderRouteCard(job: widget.job),
      ],
    );
  }
}
