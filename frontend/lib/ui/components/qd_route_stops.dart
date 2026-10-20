import 'package:flutter/material.dart';

import '../tokens.dart';

/// One stop of a [QdRouteStops] group.
class QdRouteStop {
  const QdRouteStop({
    required this.caption,
    this.value,
    this.note,
    required this.placeholder,
    this.onTap,
  });

  /// "Pickup" / "Drop-off".
  final String caption;

  /// The chosen place; null shows [placeholder] in the warning color.
  final String? value;

  /// Secondary line under the value (landmark note).
  final String? note;
  final String placeholder;
  final VoidCallback? onTap;
}

/// Editable route (A-Book "From where to where?"): a bordered group with a
/// pickup row (navy ring) and a drop-off row (gold square), each opening a
/// picker. An unset stop shows its placeholder in the warning color.
class QdRouteStops extends StatelessWidget {
  const QdRouteStops({super.key, required this.pickup, required this.dropoff});

  final QdRouteStop pickup;
  final QdRouteStop dropoff;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QdRadius.card),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(c, pickup, isPickup: true),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14 + 12 + 12),
            child: Container(height: 1, color: c.border),
          ),
          _row(c, dropoff, isPickup: false),
        ],
      ),
    );
  }

  Widget _row(QdColors c, QdRouteStop stop, {required bool isPickup}) {
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
    final isSet = stop.value != null;
    final shown = stop.value ?? stop.placeholder;
    return Semantics(
      button: stop.onTap != null,
      label:
          [stop.caption, shown, if (stop.note != null) stop.note!].join(', '),
      excludeSemantics: true,
      onTap: stop.onTap,
      child: InkWell(
        onTap: stop.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 14, vertical: QdSpace.x2),
            child: Row(
              children: [
                mark,
                const SizedBox(width: QdSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(stop.caption,
                          style:
                              QdText.caption.copyWith(color: c.textSecondary)),
                      const SizedBox(height: 1),
                      Text(
                        shown,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: QdText.rowTitleSm.copyWith(
                          color: isSet ? c.textPrimary : c.warning,
                          fontWeight: isSet ? FontWeight.w500 : FontWeight.w600,
                        ),
                      ),
                      if (stop.note != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          stop.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              QdText.caption.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (stop.onTap != null) ...[
                  const SizedBox(width: QdSpace.x2),
                  Icon(Icons.chevron_right,
                      size: QdSize.icon, color: c.textSecondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
