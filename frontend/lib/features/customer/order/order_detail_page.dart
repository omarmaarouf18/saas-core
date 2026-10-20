import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/marketplace_provider.dart';
import '../../../ui/qd_ui.dart';
import '../customer_theme.dart';
import 'closed_views.dart';
import 'order_controller.dart';
import 'order_deps.dart';
import 'order_sections.dart';
import 'order_view.dart';
import 'searching_views.dart';

/// Order detail (FE-CUST-2): one route for one job id. It polls the job
/// while it is ongoing and renders exactly one state view, chosen by
/// [orderViewFor].
class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.jobId,
    this.initialJob,
    this.now,
    this.pollInterval = const Duration(seconds: 5),
  });

  final String jobId;

  /// Shown at once while the first fetch runs (the caller's copy).
  final Job? initialJob;

  /// Clock (tests).
  final DateTime Function()? now;
  final Duration pollInterval;

  /// Opens [job]. After a booking, [replaceStack] drops the marketplace and
  /// booking pages so "back" returns to the shell.
  static Future<void> open(BuildContext context, Job job,
      {bool replaceStack = false}) {
    final route = customerRoute<void>(
      (_) => OrderDetailPage(jobId: job.id, initialJob: job),
    );
    final nav = Navigator.of(context);
    if (replaceStack) return nav.pushAndRemoveUntil(route, (r) => r.isFirst);
    return nav.push(route);
  }

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late final OrderController _ctl;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final lookup = CourierLookupScope.of(context);
    _ctl = OrderController(
      marketplace: context.read<MarketplaceProvider>(),
      token: () => auth.token,
      courierName: (id) => lookup.nameOf(context, id),
      jobId: widget.jobId,
      initialJob: widget.initialJob,
      now: widget.now,
      pollInterval: widget.pollInterval,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctl.start();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OrderController>.value(
      value: _ctl,
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.ordTitle)),
        body: SafeArea(
          top: false,
          child: Consumer<OrderController>(
            builder: (context, ctl, _) => _body(context, ctl),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, OrderController ctl) {
    final l10n = context.l10n;
    final job = ctl.job;
    if (job == null) {
      if (ctl.error != null && !ctl.refreshing) {
        return Center(
          child: SingleChildScrollView(
            child: QdErrorState(
              key: const Key('ord_load_error'),
              title: l10n.ordLoadError,
              onRetry: ctl.refresh,
            ),
          ),
        );
      }
      return const Center(
        key: Key('ord_loading'),
        child: CircularProgressIndicator(),
      );
    }
    return switch (orderViewFor(job, ctl.now())) {
      OrderViewKind.searching => OrderSearchingView(job: job),
      OrderViewKind.unavailable => OrderUnavailableView(job: job),
      OrderViewKind.cancelled => OrderCancelledView(job: job),
      OrderViewKind.underReview => OrderUnderReviewView(job: job),
      OrderViewKind.unknown => OrderUnknownView(job: job),
      // Replaced by their own views in the following FE-CUST-2 items.
      _ => _InterimView(job: job),
    };
  }
}

class _InterimView extends StatelessWidget {
  const _InterimView({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) => OrderLayout(
        children: [
          OrderRefRow(job: job),
          const SizedBox(height: QdSpace.x4),
          OrderRouteCard(job: job),
        ],
      );
}
