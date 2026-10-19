import 'package:flutter/material.dart';

import '../tokens.dart';

class QdChoice<T> {
  const QdChoice({required this.value, required this.label});

  final T value;
  final String label;
}

/// Single-choice pill row (sort order, distance): the selected pill is navy
/// with surface-colored text, the others outlined. Scrolls sideways when the
/// pills do not fit. Announced as a group of mutually exclusive buttons.
class QdChoiceChips<T> extends StatelessWidget {
  const QdChoiceChips({
    super.key,
    required this.choices,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<QdChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      explicitChildNodes: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(width: QdSpace.x2),
              _chip(c, choices[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(QdColors c, QdChoice<T> choice) {
    final isSelected = choice.value == selected;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(QdRadius.pill),
      side: BorderSide(color: isSelected ? c.navy : c.borderInput),
    );
    return Semantics(
      button: true,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      label: choice.label,
      excludeSemantics: true,
      onTap: isSelected ? null : () => onChanged(choice.value),
      child: SizedBox(
        height: QdSize.minTouch,
        child: Center(
          child: Material(
            color: isSelected ? c.navy : c.surface,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isSelected ? null : () => onChanged(choice.value),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      choice.label,
                      maxLines: 1,
                      softWrap: false,
                      style: QdText.secondary.copyWith(
                        color: isSelected ? c.surface : c.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
