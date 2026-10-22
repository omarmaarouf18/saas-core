import 'package:flutter/material.dart';

import '../../ui/qd_ui.dart';

/// Small layout pieces shared by the redesigned owner pages (FE-OWNER-1).

/// Bordered group of label / value rows (O-Order details, O-Recon
/// amounts). The value takes the rest of the row and wraps, unlike
/// [QdListTile.value].
class OwnerInfoGroup extends StatelessWidget {
  const OwnerInfoGroup({super.key, required this.rows});

  final List<OwnerInfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(QdRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: c.fillMuted),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class OwnerInfoRow extends StatelessWidget {
  const OwnerInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14, vertical: QdSpace.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: QdText.body.copyWith(color: c.textSecondary)),
            const SizedBox(width: QdSpace.x3),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: QdText.body.copyWith(
                    color: c.textPrimary, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-height scrollable box with [child] centred, so empty / error /
/// loading states still allow pull to refresh.
class OwnerScrollableCenter extends StatelessWidget {
  const OwnerScrollableCenter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: QdSpace.gutter),
                child: child,
              ),
            ),
          ),
        ),
      );
}

/// Pushed-page app bar: back button, title, optional trailing widget.
PreferredSizeWidget ownerAppBar(BuildContext context,
    {required String title, Widget? trailing}) {
  final c = QdColors.of(context);
  return AppBar(
    backgroundColor: c.surface,
    surfaceTintColor: c.surface,
    elevation: 0,
    scrolledUnderElevation: 0,
    // Next to the back button; a root page (no back) gets the gutter.
    titleSpacing: ModalRoute.of(context)?.canPop == true ? 0 : QdSpace.gutter,
    title: Text(title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: QdText.header.copyWith(color: c.textPrimary)),
    actions: [
      if (trailing != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: QdSpace.x4),
          child: Center(child: trailing),
        ),
    ],
  );
}
