import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../core/enum_labels.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../providers/employee_location_provider.dart';
import '../../ui/qd_ui.dart';
import '../customer/customer_format.dart' show formatWhen;
import 'courier_controller.dart';
import 'courier_format.dart';
import 'courier_rules.dart';
import 'courier_widgets.dart';

/// My jobs (C-History): the availability switch (locked while a job is
/// active, as before), the location permission banner, the verification
/// banner, today's completed count and cash, and the finished jobs.
///
/// Honest numbers: "today" uses the completion time from the server
/// timeline (job model v2); older jobs without one are counted by their
/// creation day and the page says so. Cash is the order price of today's
/// completed cash orders: the amount actually collected is not sent to
/// couriers, and the page says that too.
class CourierJobsPage extends StatelessWidget {
  const CourierJobsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctl = context.watch<CourierController>();
    final finished = finishedJobs(ctl.jobs);
    final stats = todayStats(ctl.jobs, ctl.now());
    final firstLoad = !ctl.loaded && ctl.jobs.isEmpty;

    return Scaffold(
      key: const Key('courier_jobs'),
      backgroundColor: c.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ctl.reload,
          child: ListView(
            key: const Key('courier_jobs_list'),
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, 28, QdSpace.gutter, QdSpace.x4),
            children: [
              CourierHeader(title: l10n.courNavJobs),
              const SizedBox(height: 14),
              const _AvailabilityCard(),
              const _PermissionBanner(),
              const SizedBox(height: QdSpace.x3),
              const CourierKyeBanner(),
              if (ctl.error != null && ctl.jobs.isNotEmpty) ...[
                const SizedBox(height: QdSpace.x3),
                QdBanner(
                  key: const Key('courier_jobs_stale'),
                  tone: QdBannerTone.warning,
                  message: l10n.courLoadError,
                  actionLabel: l10n.retry,
                  onAction: ctl.reload,
                ),
              ],
              const SizedBox(height: QdSpace.x3),
              if (firstLoad)
                const Padding(
                  padding: EdgeInsets.all(QdSpace.x6),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (ctl.error != null && ctl.jobs.isEmpty)
                QdErrorState(
                  key: const Key('courier_jobs_error'),
                  onRetry: ctl.reload,
                  body: l10n.courLoadError,
                )
              else ...[
                _TodayTiles(stats: stats),
                const SizedBox(height: QdSpace.x2),
                Text(
                  stats.estimated
                      ? '${l10n.courTodayCashNote} ${l10n.courTodayByCreation}'
                      : l10n.courTodayCashNote,
                  key: const Key('courier_today_note'),
                  style: QdText.caption.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: QdSpace.x5),
                Text(l10n.courFinishedHeader,
                    style: QdText.bodyStrong.copyWith(color: c.textSecondary)),
                const SizedBox(height: QdSpace.x2),
                if (finished.isEmpty)
                  QdEmptyState(
                    key: const Key('courier_jobs_empty'),
                    icon: Icons.history,
                    title: l10n.courNoFinishedTitle,
                    body: l10n.courNoFinishedBody,
                  )
                else
                  QdListGroup(children: [
                    for (final j in finished)
                      _FinishedRow(
                          key: Key('courier_finished_${j.id}'), job: j),
                  ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Available for tasks" switch; locked while a job is active.
class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctl = context.watch<CourierController>();
    final online = ctl.location.isAvailableOnline;
    final locked = ctl.activeJobLock;
    final body = locked
        ? l10n.courAvailableLocked
        : online
            ? l10n.courAvailableOnBody
            : l10n.courAvailableOffBody;
    return Container(
      key: const Key('courier_availability'),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsetsDirectional.fromSTEB(QdSpace.x4, 6, 6, 6),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(QdRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: online ? c.success : c.decorative,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: QdSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(online ? l10n.courAvailableOn : l10n.courAvailableOff,
                    style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                Text(body,
                    style: QdText.caption.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          Semantics(
            label: l10n.courAvailableOn,
            child: Switch.adaptive(
              key: const Key('courier_availability_switch'),
              value: online,
              activeTrackColor: c.success,
              onChanged: locked ? null : ctl.setOnline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Location permission denied or location turned off: the old banner with
/// the app settings button.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = context.watch<CourierController>().location.status;
    if (status != LocationSharingStatus.permissionDenied &&
        status != LocationSharingStatus.serviceDisabled) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: QdSpace.x3),
      child: QdBanner(
        key: const Key('courier_permission_banner'),
        tone: QdBannerTone.warning,
        icon: Icons.location_off_outlined,
        title: l10n.courPermissionTitle,
        message: l10n.courPermissionBody,
        actionLabel: l10n.courOpenSettings,
        onAction: Geolocator.openAppSettings,
      ),
    );
  }
}

class _TodayTiles extends StatelessWidget {
  const _TodayTiles({required this.stats});

  final CourierDayStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    Widget tile(Key key, String value, String label) => Expanded(
          child: Container(
            key: key,
            padding: const EdgeInsets.all(QdSpace.x3),
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: QdText.sheetTitle.copyWith(color: c.textPrimary)),
                Text(label,
                    style: QdText.caption.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile(const Key('courier_today_count'), '${stats.completed}',
            l10n.courTodayDone),
        const SizedBox(width: QdSpace.x2),
        tile(const Key('courier_today_cash'), formatMoney(l10n, stats.cash),
            l10n.courTodayCash),
      ],
    );
  }
}

class _FinishedRow extends StatelessWidget {
  const _FinishedRow({super.key, required this.job});

  final Job job;

  String _detail(BuildContext context) {
    final l10n = context.l10n;
    final status = job.status.trim().toLowerCase();
    if (status == 'cancelled' || status == 'canceled') {
      final reason = job.cancellationReason?.trim();
      if (reason != null && reason.isNotEmpty) {
        return switch (reason) {
          'price_proposal_expired' => l10n.courPriceExpired,
          'price_disagreement' => l10n.courReasonPriceDisagreement,
          _ => reason,
        };
      }
    }
    return isCod(job)
        ? l10n.courPayCash
        : paymentMethodLabel(l10n, job.paymentMethod);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctl = context.read<CourierController>();
    final when = finishedAt(job) ?? job.updatedAt ?? job.createdAt;
    final place = placeOf(l10n, job.destination ?? job.location).title;
    final status = job.status.trim().toLowerCase();
    // No price on a job that ended without a delivery (C-History).
    final price =
        status == 'cancelled' || status == 'canceled' || status == 'unavailable'
            ? null
            : priceOf(job);
    final sub = [
      if (when != null) formatWhen(context, when, now: ctl.now()),
      _detail(context),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: QdSpace.x4, vertical: QdSpace.x3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.courToPlace(place),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QdText.caption.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: QdSpace.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (price != null)
                Text(formatMoney(l10n, price),
                    style: QdText.bodyStrong.copyWith(
                        color: c.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              QdJobStatusChips(status: job.status),
            ],
          ),
        ],
      ),
    );
  }
}
