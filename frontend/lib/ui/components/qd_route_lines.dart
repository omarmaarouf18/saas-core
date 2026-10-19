import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../tokens.dart';

/// Pickup (navy ring) and drop-off (gold square, navy border) with their
/// addresses. [compact] is the one-line-each form used inside order cards;
/// the full form adds a caption above each address (offer, booking).
class QdRouteLines extends StatelessWidget {
  const QdRouteLines({
    super.key,
    required this.pickup,
    required this.dropoff,
    this.pickupCaption,
    this.dropoffCaption,
    this.compact = false,
  });

  final String pickup;
  final String dropoff;

  /// Defaults to "Pickup" / "Drop-off" in the full form.
  final String? pickupCaption;
  final String? dropoffCaption;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _line(c, true, pickupCaption ?? l10n.qdPickup, pickup),
        SizedBox(height: compact ? 6 : QdSpace.x3),
        _line(c, false, dropoffCaption ?? l10n.qdDropoff, dropoff),
      ],
    );
  }

  Widget _line(QdColors c, bool isPickup, String caption, String address) {
    final size = compact ? 10.0 : 12.0;
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isPickup ? Colors.transparent : c.gold,
        shape: isPickup ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isPickup ? null : BorderRadius.circular(compact ? 2 : 3),
        border: Border.all(
          color: c.navy,
          width: isPickup ? (compact ? 2 : 3) : 2,
        ),
      ),
    );

    if (compact) {
      return Semantics(
        label: '$caption: $address',
        excludeSemantics: true,
        child: Row(
          children: [
            mark,
            const SizedBox(width: QdSpace.x2),
            Expanded(
              child: Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QdText.secondary.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: '$caption: $address',
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
                Text(address,
                    style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
