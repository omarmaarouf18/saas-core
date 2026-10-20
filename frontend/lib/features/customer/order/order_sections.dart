import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../providers/marketplace_provider.dart';
import '../../../ui/qd_ui.dart';
import '../chat/chat_page.dart';
import '../customer_format.dart';
import 'order_controller.dart';

/// Sections shared by the order detail views (FE-CUST-2). One widget per
/// section, so fields the API does not have yet (ETA, recipient, vehicle,
/// per-status times; JOB-MODEL-V2) slot in without touching the views.

/// Common body of every view: optional fixed [top] (the tracking map),
/// then a pull-to-refresh list with the stale-data banner first, then an
/// optional [footer] with the view's main actions.
class OrderLayout extends StatelessWidget {
  const OrderLayout({
    super.key,
    required this.children,
    this.top,
    this.footer,
    this.onRefresh,
  });

  final List<Widget> children;
  final Widget? top;
  final Widget? footer;

  /// Pull to refresh; defaults to refetching the job.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<OrderController>();
    final list = RefreshIndicator(
      onRefresh: onRefresh ?? ctl.refresh,
      child: ListView(
        key: const Key('ord_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x5),
        children: [
          if (ctl.error != null) ...[
            const OrderStaleBanner(),
            const SizedBox(height: QdSpace.x4),
          ],
          ...children,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (top != null) top!,
        Expanded(child: list),
        if (footer != null) QdFooterBar(child: footer!),
      ],
    );
  }
}

/// A refresh failed: the page still shows the last good data.
class OrderStaleBanner extends StatelessWidget {
  const OrderStaleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ctl = context.read<OrderController>();
    return QdBanner(
      key: const Key('ord_stale_banner'),
      tone: QdBannerTone.danger,
      icon: Icons.error_outline,
      message: l10n.ordRefreshError,
      actionLabel: l10n.retry,
      onAction: ctl.refresh,
    );
  }
}

/// Order reference and status chips ("#QD-A1B2C3D4 · On the way").
class OrderRefRow extends StatelessWidget {
  const OrderRefRow({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            jobRefIsolated(job),
            style: QdText.secondary.copyWith(color: c.textSecondary),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kChipsMaxWidth),
          child: QdJobStatusChips(
            status: job.status,
            cancellationRequestStatus: job.cancellationRequestStatus,
          ),
        ),
      ],
    );
  }
}

/// Big centred state header: an icon disc, a title and an optional body.
class OrderStateHeader extends StatelessWidget {
  const OrderStateHeader({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.tone = QdTone.neutral,
    this.illustration,
  });

  final IconData icon;
  final String title;
  final String? body;
  final QdTone tone;

  /// Replaces the icon disc (the searching rings).
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final (bg, fg) = switch (tone) {
      QdTone.success => (c.successBg, c.success),
      QdTone.warning => (c.warningBg, c.warning),
      QdTone.danger => (c.dangerBg, c.danger),
      QdTone.neutral => (c.fillMuted, c.textPrimary),
    };
    return Padding(
      padding: const EdgeInsets.only(top: QdSpace.x3, bottom: QdSpace.x2),
      child: Column(
        children: [
          illustration ??
              ExcludeSemantics(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, size: 30, color: fg),
                ),
              ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(title,
                textAlign: TextAlign.center,
                style: QdText.sheetTitle.copyWith(color: c.textPrimary)),
          ),
          if (body != null) ...[
            const SizedBox(height: QdSpace.x1),
            Text(body!,
                textAlign: TextAlign.center,
                style: QdText.body.copyWith(color: c.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// How the price row of [OrderRouteCard] reads.
enum OrderPriceMode {
  /// Ended without a trip (cancelled, unknown): just "Price".
  plain,

  /// Before a courier accepted: "Cash · estimated".
  estimate,

  /// Ongoing: "You'll pay cash".
  toPay,

  /// Completed: "Paid cash".
  paid,
}

/// Pickup, drop-off and the price (A-Searching / A-Track details card).
class OrderRouteCard extends StatelessWidget {
  const OrderRouteCard({
    super.key,
    required this.job,
    this.priceMode = OrderPriceMode.estimate,
    this.showPrice = true,
  });

  final Job job;
  final OrderPriceMode priceMode;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return QdCard(
      key: const Key('ord_route'),
      subtle: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QdRouteLines(
            pickup: jobPlaceLabel(l10n, job.location),
            dropoff: jobPlaceLabel(l10n, job.destination),
            pickupCaption: l10n.ordPickupFrom,
            dropoffCaption: l10n.ordDeliverTo,
          ),
          if (showPrice) ...[
            const SizedBox(height: QdSpace.x3),
            Container(height: 1, color: c.border),
            const SizedBox(height: 10),
            OrderPriceRow(job: job, mode: priceMode),
          ],
        ],
      ),
    );
  }
}

/// "<payment> · <price>": agreed price, else the suggested one.
class OrderPriceRow extends StatelessWidget {
  const OrderPriceRow({super.key, required this.job, required this.mode});

  final Job job;
  final OrderPriceMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final price = jobPrice(job);
    final cod = job.paymentMethod.trim().toLowerCase() == 'cod';
    final label = !cod || mode == OrderPriceMode.plain
        ? l10n.custPriceTitle
        : switch (mode) {
            OrderPriceMode.plain => l10n.custPriceTitle,
            OrderPriceMode.estimate => l10n.ordCashEstimate,
            OrderPriceMode.toPay => l10n.ordPayCash,
            OrderPriceMode.paid => l10n.ordPaidCash,
          };
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: QdText.body.copyWith(color: c.textSecondary)),
          ),
          Text(
            price == null ? l10n.ordPriceNotSet : formatMoney(l10n, price),
            key: const Key('ord_price'),
            style: QdText.bodyStrong
                .copyWith(color: c.textPrimary, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The courier (or the one looking at the offer) with the in-app chat,
/// the only courier contact the API offers.
class OrderCourierCard extends StatelessWidget {
  const OrderCourierCard({
    super.key,
    required this.title,
    required this.onChat,
    this.name,
    this.subtitle,
  });

  /// Main line ("<name> is looking at your order").
  final String title;

  /// For the initial; null shows a generic courier icon.
  final String? name;
  final String? subtitle;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return QdCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          if (name != null)
            QdAvatarInitial(name: name!, size: 44)
          else
            const QdIconTile(icon: Icons.person_outline, size: 44),
          const SizedBox(width: QdSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!,
                      style: QdText.caption.copyWith(color: c.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: QdSpace.x2),
          QdIconButton(
            key: const Key('ord_chat'),
            icon: Icons.chat_bubble_outline,
            label: l10n.ordChatCourier,
            round: true,
            onPressed: onChat,
          ),
        ],
      ),
    );
  }
}

/// The company that runs the order, when its service is already loaded
/// (jobs carry only `service_id`; no extra request is made).
String? orderCompanyName(BuildContext context, Job job) {
  final services = context.watch<MarketplaceProvider>().services;
  final name = serviceOfJob(job, services)?.name.trim() ?? '';
  return name.isEmpty ? null : name;
}

/// Shows a short notice, with an optional retry, like the old screens'
/// snack bars.
void showOrderNotice(BuildContext context, String message,
    {VoidCallback? onRetry}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: onRetry == null
          ? null
          : SnackBarAction(label: context.l10n.retry, onPressed: onRetry),
    ));
}

/// Opens the job chat with the courier (the only courier contact).
void openCourierChat(BuildContext context, Job job) {
  final l10n = context.l10n;
  CustomerChatPage.openJob(context,
      jobId: job.id, title: l10n.ordChatCourier, subtitle: jobRefIsolated(job));
}
