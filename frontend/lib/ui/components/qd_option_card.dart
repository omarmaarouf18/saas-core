import 'package:flutter/material.dart';

import '../tokens.dart';

/// One choice of a small set shown as cards (A-Signup "who are you?"):
/// title with a radio mark, a one-line hint below. Selected: 2 dp navy
/// border on the gold tint; otherwise a 1 dp input border on white.
class QdOptionCard extends StatelessWidget {
  const QdOptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final radius = BorderRadius.circular(QdRadius.button);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.goldTint : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? c.navy : c.borderInput,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: QdSize.minTouch),
            child: Padding(
              padding: const EdgeInsets.all(QdSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: selected ? c.navy : c.textSecondary,
                      ),
                      const SizedBox(width: QdSpace.x2),
                      Expanded(
                        child: Text(
                          title,
                          style:
                              QdText.rowTitleSm.copyWith(color: c.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: QdSpace.x1),
                    Text(
                      subtitle!,
                      style: QdText.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
