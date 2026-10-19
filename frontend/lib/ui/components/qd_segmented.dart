import 'package:flutter/material.dart';

import '../tokens.dart';

class QdSegment<T> {
  const QdSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// Two or three equal tabs on a muted track (orders: current / past; team:
/// all / active / frozen). Labels never wrap: a label too long for its
/// third of the width scales down instead of breaking mid-word.
class QdSegmented<T> extends StatelessWidget {
  const QdSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  }) : assert(segments.length >= 2 && segments.length <= 3,
            'QdSegmented takes 2 or 3 options');

  final List<QdSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Container(
      padding: const EdgeInsets.all(QdSpace.x1),
      decoration: BoxDecoration(
        color: c.fillMuted,
        borderRadius: BorderRadius.circular(QdRadius.sm),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: QdSpace.x1),
            Expanded(child: _segment(c, segments[i])),
          ],
        ],
      ),
    );
  }

  Widget _segment(QdColors c, QdSegment<T> s) {
    final isSelected = s.value == selected;
    return Semantics(
      selected: isSelected,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: s.label,
      excludeSemantics: true,
      onTap: isSelected ? null : () => onChanged(s.value),
      child: Material(
        color: isSelected ? c.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: isSelected ? null : () => onChanged(s.value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.border),
                  )
                : null,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: QdSpace.x2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                s.label,
                maxLines: 1,
                softWrap: false,
                style: QdText.body.copyWith(
                  color: isSelected ? c.textPrimary : c.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
