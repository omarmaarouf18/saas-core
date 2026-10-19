import 'package:flutter/material.dart';

import '../tokens.dart';

/// Bordered 16-radius container. Never a shadow. [subtle] uses the
/// `#F9FAFB` fill of the highlighted cards (current order, price summary).
class QdCard extends StatelessWidget {
  const QdCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(QdSpace.x4),
    this.subtle = false,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool subtle;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(QdRadius.card),
      side: BorderSide(color: c.border),
    );
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(onTap: onTap, child: body);
    }
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: Material(
        color: subtle ? c.fillSubtle : c.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
  }
}
