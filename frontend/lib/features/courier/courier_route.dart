import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../ui/qd_ui.dart';
import 'courier_format.dart';

/// Pickup (navy ring) and drop-off (gold square) with a caption, the
/// address (or note, or "Pinned location") and the landmark note under it
/// when the address is the title (C-Offer, A-Courier). Same marks as
/// [QdRouteLines], plus the note line.
class CourierStops extends StatelessWidget {
  const CourierStops({
    super.key,
    required this.job,
    this.pickupCaption,
    this.dropoffCaption,
  });

  final Job job;

  /// Default "Pickup" / "Drop-off".
  final String? pickupCaption;
  final String? dropoffCaption;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pickup = placeOf(l10n, job.location);
    final drop = job.destination == null
        ? (title: l10n.courNoDestination, note: null)
        : placeOf(l10n, job.destination);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Stop(
          key: const Key('courier_stop_pickup'),
          isPickup: true,
          caption: pickupCaption ?? l10n.qdPickup,
          title: pickup.title,
          note: pickup.note,
        ),
        const SizedBox(height: QdSpace.x3),
        _Stop(
          key: const Key('courier_stop_dropoff'),
          isPickup: false,
          caption: dropoffCaption ?? l10n.qdDropoff,
          title: drop.title,
          note: drop.note,
        ),
      ],
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    super.key,
    required this.isPickup,
    required this.caption,
    required this.title,
    this.note,
  });

  final bool isPickup;
  final String caption;
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final mark = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isPickup ? Colors.transparent : c.gold,
        shape: isPickup ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isPickup ? null : BorderRadius.circular(3),
        border: Border.all(color: c.navy, width: isPickup ? 3 : 2),
      ),
    );
    return Semantics(
      label: [caption, title, if (note != null) note].join(': '),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 6), child: mark),
          const SizedBox(width: QdSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(caption,
                    style: QdText.caption.copyWith(color: c.textSecondary)),
                const SizedBox(height: 1),
                Text(title,
                    style: QdText.rowTitle.copyWith(color: c.textPrimary)),
                if (note != null)
                  Text(note!,
                      style: QdText.secondary.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Package: Small · Documents" when the booking gave a size or notes.
class CourierPackageLine extends StatelessWidget {
  const CourierPackageLine({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final p = job.packageDetails;
    if (p == null) return const SizedBox.shrink();
    final parts = [
      if (packageSizeLabel(l10n, p.size) case final size?) size,
      if (p.notes case final notes?) notes,
    ];
    return Row(
      key: const Key('courier_package'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.inventory_2_outlined,
            size: QdSize.icon, color: c.textSecondary),
        const SizedBox(width: QdSpace.x2),
        Expanded(
          child: Text(l10n.courPackage(parts.join(' · ')),
              style: QdText.body.copyWith(color: c.textPrimary)),
        ),
      ],
    );
  }
}
