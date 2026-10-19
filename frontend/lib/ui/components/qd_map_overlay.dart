import 'package:flutter/material.dart';

import '../tokens.dart';

/// Centre pin of a "move the map under the pin" picker (A-Picker): gold
/// square with a navy border on a navy stem, and a soft ground shadow.
/// Its bottom tip is the picked point: place it with
/// `Alignment.center` + a bottom offset of half its [height].
class QdMapPin extends StatelessWidget {
  const QdMapPin({super.key});

  static const double height = 36 + 18 + 4;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.gold,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.navy, width: 3),
            ),
          ),
          Container(width: 3, height: 18, color: c.navy),
          Container(
            width: 10,
            height: 4,
            decoration: BoxDecoration(
              color: c.scrim,
              borderRadius: BorderRadius.circular(QdRadius.pill),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating title pill over a map ("Drop-off place").
class QdMapLabel extends StatelessWidget {
  const QdMapLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Semantics(
      header: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(QdRadius.pill),
          border: Border.all(color: c.border),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
      ),
    );
  }
}

/// Surface panel with 24 dp top corners docked under a map or at the bottom
/// of a screen (picker controls).
class QdDockedPanel extends StatelessWidget {
  const QdDockedPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: QdSpace.x5),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, QdSpace.x4, QdSpace.gutter, 0),
          child: child,
        ),
      ),
    );
  }
}

/// Bottom action bar with a top border (A-Book footer): holds the screen's
/// one primary button and an optional caption under it.
class QdFooterBar extends StatelessWidget {
  const QdFooterBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: QdSpace.x5),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, 14, QdSpace.gutter, 0),
          // Sized by its content even as a Scaffold.bottomNavigationBar,
          // whose loose constraints would let a centred button grow.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child],
          ),
        ),
      ),
    );
  }
}
