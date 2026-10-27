import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../providers/employee_location_provider.dart';
import '../../ui/qd_ui.dart';
import 'courier_controller.dart';
import 'courier_format.dart';
import 'courier_map.dart';
import 'courier_nav.dart';
import 'courier_route.dart';
import 'courier_rules.dart';
import 'courier_sheets.dart';
import 'courier_widgets.dart';
import 'negotiation_panel.dart';

/// The current job (A-Courier): the map with the courier's own position,
/// whether the customer can see it and "open in maps"; then the job's
/// phase, the route with address text, package details, the recipient
/// (name, notes, phone while the job is active) with chat, and ONE primary
/// action by phase: heading to pickup -> "I picked up the order"
/// (`POST /users/jobs/pickup`); picked up, or an older job without a phase
/// -> "Delivered" with the cash confirmation. A job waiting for a price
/// shows the negotiation panel instead. Cancellation can be requested,
/// with pending / rejected banners. Location sharing itself is the
/// controller's (same rule as before).
class CourierActiveJobPage extends StatefulWidget {
  const CourierActiveJobPage({super.key, required this.job});

  final Job job;

  @override
  State<CourierActiveJobPage> createState() => _CourierActiveJobPageState();
}

class _CourierActiveJobPageState extends State<CourierActiveJobPage> {
  bool _busy = false;

  Job get job => widget.job;

  Future<void> _pickup() async {
    if (_busy) return;
    final l10n = context.l10n;
    final ctl = context.read<CourierController>();
    setState(() => _busy = true);
    try {
      await ctl.pickup(job);
      if (mounted) showCourierNotice(context, l10n.courPickedUpDone);
    } catch (e) {
      if (!mounted) return;
      final status = e is ApiClientException ? e.statusCode : null;
      showCourierNotice(context, pickupErrorText(l10n, e),
          key: const Key('courier_pickup_error'),
          actionLabel: status == null || status >= 500 ? l10n.retry : null,
          onAction: _pickup);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver() async {
    final l10n = context.l10n;
    final ctl = context.read<CourierController>();
    final cod = isCod(job);
    final done = await CourierCompleteSheet.show(
      context,
      job: job,
      onConfirm: (actual) =>
          ctl.complete(job, cashCollected: cod, actualAmount: actual),
    );
    if (done == true && mounted) {
      showCourierNotice(context, l10n.courDelivered);
    }
  }

  Future<void> _requestCancel() async {
    final l10n = context.l10n;
    final ctl = context.read<CourierController>();
    final sent = await CourierCancelRequestSheet.show(context,
        onConfirm: (reason) => ctl.requestCancellation(job, reason));
    if (sent == true && mounted) {
      showCourierNotice(context, l10n.courCancelSent);
    }
  }

  /// Opens the next stop in a maps app; copies its coordinates when none
  /// opens.
  Future<void> _openInMaps() async {
    final l10n = context.l10n;
    final t = navigationTarget(job);
    final coords = coordsText(t.latitude, t.longitude);
    await openOrCopy(
      context,
      mapsUris(t.latitude, t.longitude),
      copyText: coords,
      onCopied: () {
        if (mounted) {
          showCourierNotice(context, l10n.lnchMapsCopied(coords),
              key: const Key('courier_coords_copied'));
        }
      },
    );
  }

  Future<void> _pickRunning(List<Job> running) async {
    final l10n = context.l10n;
    final ctl = context.read<CourierController>();
    await QdBottomSheet.show<void>(
      context,
      title: l10n.courOtherJobsTitle,
      child: Builder(
        builder: (sheet) => QdListGroup(children: [
          for (final j in running)
            QdListTile(
              key: Key('courier_running_${j.id}'),
              title: placeOf(l10n, j.destination ?? j.location).title,
              subtitle: jobRef(j),
              badge: _PhaseChip(job: j),
              onTap: () {
                ctl.select(j.id);
                Navigator.of(sheet).pop();
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctl = context.watch<CourierController>();
    final loc = ctl.location;
    final pos = loc.lastKnownPosition;
    final action = primaryActionFor(job);
    final cod = isCod(job);
    final price = priceOf(job);
    final others = ctl.running.where((j) => j.id != job.id).toList();
    final request = job.cancellationRequestStatus?.trim().toLowerCase();

    final String? primaryLabel = switch (action) {
      CourierAction.pickup => l10n.courPickedUp,
      CourierAction.deliver when cod && price != null =>
        l10n.courDeliveredCollected(formatMoney(l10n, price)),
      CourierAction.deliver when cod => l10n.courDeliveredCash,
      CourierAction.deliver => l10n.courDeliveredPlain,
      CourierAction.none => null,
    };

    return Scaffold(
      key: const Key('courier_active'),
      backgroundColor: c.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 250,
              child: CourierMap(
                key: const Key('courier_active_map'),
                job: job,
                height: 250,
                interactive: true,
                self: pos == null ? null : LatLng(pos.latitude, pos.longitude),
                overlays: [
                  PositionedDirectional(
                    top: QdSpace.x4,
                    start: QdSpace.x4,
                    child: _SharingChip(job: job, location: loc),
                  ),
                  PositionedDirectional(
                    bottom: 30,
                    end: QdSpace.x4,
                    child: _MapPill(
                      key: const Key('courier_open_maps'),
                      icon: Icons.near_me_outlined,
                      label: l10n.courOpenInMaps,
                      onTap: _openInMaps,
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              top: 230,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(QdRadius.sheet)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: ctl.reload,
                        child: ListView(
                          key: const Key('courier_active_list'),
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              QdSpace.gutter,
                              QdSpace.x5,
                              QdSpace.gutter,
                              QdSpace.x3),
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(l10n.courCurrentTitle,
                                      style: QdText.sheetTitle
                                          .copyWith(color: c.textPrimary)),
                                ),
                                const SizedBox(width: QdSpace.x2),
                                _PhaseChip(job: job),
                              ],
                            ),
                            if (_etaText(l10n) case final eta?) ...[
                              const SizedBox(height: QdSpace.x1),
                              Text(eta,
                                  key: const Key('courier_eta'),
                                  style: QdText.secondary
                                      .copyWith(color: c.textSecondary)),
                            ],
                            if (others.isNotEmpty) ...[
                              const SizedBox(height: QdSpace.x3),
                              QdBanner(
                                key: const Key('courier_other_jobs'),
                                tone: QdBannerTone.info,
                                icon: Icons.layers_outlined,
                                message: l10n.courOtherJobs(others.length),
                                actionLabel: l10n.courOtherJobsShow,
                                onAction: () => _pickRunning(ctl.running),
                              ),
                            ],
                            if (request == 'pending') ...[
                              const SizedBox(height: QdSpace.x3),
                              QdBanner(
                                key: const Key('courier_cancel_pending'),
                                tone: QdBannerTone.warning,
                                icon: Icons.hourglass_top,
                                message: l10n.courCancelPending,
                              ),
                            ] else if (request == 'rejected') ...[
                              const SizedBox(height: QdSpace.x3),
                              QdBanner(
                                key: const Key('courier_cancel_rejected'),
                                tone: QdBannerTone.danger,
                                icon: Icons.block,
                                message: l10n.courCancelRejected,
                              ),
                            ],
                            if (isActive(job)) _LocationProblem(location: loc),
                            if (isAwaitingPrice(job)) ...[
                              const SizedBox(height: QdSpace.x4),
                              CourierNegotiationPanel(
                                  key: ValueKey('negotiation_${job.id}'),
                                  job: job),
                            ],
                            const SizedBox(height: QdSpace.x4),
                            CourierStops(job: job),
                            if (job.packageDetails != null) ...[
                              const SizedBox(height: QdSpace.x4),
                              CourierPackageLine(job: job),
                            ],
                            const SizedBox(height: QdSpace.x4),
                            _RecipientCard(job: job),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          QdSpace.gutter,
                          QdSpace.x2,
                          QdSpace.gutter,
                          QdSpace.x2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (primaryLabel != null)
                            QdButton(
                              key: Key('courier_action_${action.name}'),
                              label: primaryLabel,
                              fullWidth: true,
                              loading: _busy,
                              onPressed: action == CourierAction.pickup
                                  ? _pickup
                                  : _deliver,
                            ),
                          if (canRequestCancellation(job))
                            QdButton.destructive(
                              key: const Key('courier_request_cancel'),
                              label: l10n.courRequestCancel,
                              fullWidth: true,
                              small: true,
                              onPressed: _busy ? null : _requestCancel,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _etaText(AppLocalizations l10n) {
    final minutes = job.estimatedDurationMinutes;
    if (minutes == null || !isActive(job)) return null;
    return primaryActionFor(job) == CourierAction.pickup
        ? l10n.courEtaPickup(minutes)
        : l10n.courEtaDropoff(minutes);
  }
}

/// Phase of a running job.
class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (isAwaitingPrice(job)) {
      return QdStatusChip(label: l10n.courPhasePrice, tone: QdTone.neutral);
    }
    if (!isActive(job)) {
      return QdJobStatusChips(
          status: job.status,
          cancellationRequestStatus: job.cancellationRequestStatus);
    }
    final sub = job.subStatus?.trim().toLowerCase();
    final label = switch (sub) {
      'heading_to_pickup' => l10n.courPhaseToPickup,
      'picked_up' => l10n.courPhasePickedUp,
      _ => l10n.courPhaseActive,
    };
    return QdStatusChip(
        key: const Key('courier_phase'), label: label, tone: QdTone.warning);
  }
}

/// "Customer sees your location" over the map, or why not.
class _SharingChip extends StatelessWidget {
  const _SharingChip({required this.job, required this.location});

  final Job job;
  final EmployeeLocationProvider location;

  @override
  Widget build(BuildContext context) {
    if (!isActive(job)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final status = location.status;
    final (String label, Color dot, String key) = switch (status) {
      LocationSharingStatus.tracking when location.activeJobId == job.id => (
          l10n.courSharingLive,
          c.success,
          'live'
        ),
      LocationSharingStatus.permissionDenied ||
      LocationSharingStatus.serviceDisabled =>
        (l10n.courSharingOff, c.danger, 'off'),
      LocationSharingStatus.error => (
          l10n.courSharingFailing,
          c.danger,
          'error'
        ),
      _ => (l10n.courSharingStarting, c.warning, 'starting'),
    };
    return _MapPill(
      key: Key('courier_sharing_$key'),
      dot: dot,
      label: label,
    );
  }
}

/// White pill over the map: a status dot or an icon, a label, optional tap.
class _MapPill extends StatelessWidget {
  const _MapPill(
      {super.key, required this.label, this.icon, this.dot, this.onTap});

  final String label;
  final IconData? icon;
  final Color? dot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final pill = Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(QdRadius.pill),
        boxShadow: const [
          BoxShadow(
              color: Color(0x260D1321), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          if (icon != null) Icon(icon, size: 18, color: c.textPrimary),
          const SizedBox(width: QdSpace.x2),
          Text(label, style: QdText.chip.copyWith(color: c.textPrimary)),
        ],
      ),
    );
    if (onTap == null) return Semantics(container: true, child: pill);
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(QdRadius.pill),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: QdSize.minTouch),
            child: Center(widthFactor: 1, child: pill),
          ),
        ),
      ),
    );
  }
}

/// Location off or failing while the job is active: the customer cannot
/// see the courier (the old card showed the same error; the permission
/// banner had the settings button).
class _LocationProblem extends StatelessWidget {
  const _LocationProblem({required this.location});

  final EmployeeLocationProvider location;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = location.status;
    if (status == LocationSharingStatus.permissionDenied ||
        status == LocationSharingStatus.serviceDisabled) {
      return Padding(
        padding: const EdgeInsets.only(top: QdSpace.x3),
        child: QdBanner(
          key: const Key('courier_active_permission'),
          tone: QdBannerTone.warning,
          icon: Icons.location_off_outlined,
          title: l10n.courPermissionTitle,
          message: l10n.courPermissionBody,
          actionLabel: l10n.courOpenSettings,
          onAction: Geolocator.openAppSettings,
        ),
      );
    }
    if (status == LocationSharingStatus.error && location.error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: QdSpace.x3),
        child: QdBanner(
          key: const Key('courier_active_location_error'),
          tone: QdBannerTone.danger,
          icon: Icons.location_disabled_outlined,
          message: location.error!,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Who receives the order: the recipient's name and notes (job model v2),
/// else "Customer"; the cash to collect; the phone while the job is active
/// (the server sends it only then), and chat with the customer.
class _RecipientCard extends StatelessWidget {
  const _RecipientCard({required this.job});

  final Job job;

  /// Dials the recipient; copies the number when the phone app does not
  /// open.
  Future<void> _call(BuildContext context, String phone) async {
    final l10n = context.l10n;
    await openOrCopy(
      context,
      [phoneCallUri(phone)],
      copyText: phone,
      onCopied: () {
        if (context.mounted) {
          showCourierNotice(context, l10n.lnchPhoneCopied(phone),
              key: const Key('courier_phone_copied'));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final r = job.recipient;
    final name = r?.name ?? l10n.courChatTitle;
    final price = priceOf(job);
    final phone = r?.phone;
    final pays = price == null
        ? null
        : isCod(job)
            ? l10n.courWillPayCash(formatMoney(l10n, price))
            : l10n.courOrderPriceValue(formatMoney(l10n, price));

    return Container(
      key: const Key('courier_recipient'),
      padding: const EdgeInsets.all(QdSpace.x3),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(QdRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              QdAvatarInitial(name: name, size: 40),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                    if (pays != null)
                      Text(pays,
                          style:
                              QdText.caption.copyWith(color: c.textSecondary)),
                    if (phone != null)
                      Text(phone,
                          key: const Key('courier_recipient_phone'),
                          textDirection: TextDirection.ltr,
                          style:
                              QdText.caption.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
              if (phone != null)
                QdIconButton(
                  key: const Key('courier_recipient_call'),
                  icon: Icons.phone_outlined,
                  label: l10n.courCallRecipient,
                  round: true,
                  onPressed: () => _call(context, phone),
                ),
              const SizedBox(width: QdSpace.x1),
              QdIconButton(
                key: const Key('courier_recipient_chat'),
                icon: Icons.chat_bubble_outline,
                label: l10n.courChatWithCustomer,
                round: true,
                onPressed: () =>
                    CourierNavScope.of(context).openChat(context, job),
              ),
            ],
          ),
          if (r?.notes case final notes?) ...[
            const SizedBox(height: QdSpace.x2),
            Text(l10n.courRecipientNotes(notes),
                key: const Key('courier_recipient_notes'),
                style: QdText.secondary.copyWith(color: c.textPrimary)),
          ],
        ],
      ),
    );
  }
}
