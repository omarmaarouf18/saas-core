import 'package:flutter/material.dart';

import '../tokens.dart';

class QdPriceLine {
  const QdPriceLine({required this.label, required this.value});

  final String label;
  final String value;
}

/// Price summary card (A-Book): label / amount lines, an optional bold total
/// under a divider, and an optional footnote (estimate disclaimer).
class QdPriceBreakdown extends StatelessWidget {
  const QdPriceBreakdown({
    super.key,
    required this.lines,
    this.totalLabel,
    this.totalValue,
    this.note,
  });

  final List<QdPriceLine> lines;
  final String? totalLabel;
  final String? totalValue;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    Widget line(String label, String value, {bool total = false}) {
      final labelStyle = total
          ? QdText.rowTitle.copyWith(color: c.textPrimary)
          : QdText.body.copyWith(color: c.textSecondary);
      final valueStyle = total
          ? QdText.rowTitle
              .copyWith(color: c.textPrimary, fontWeight: FontWeight.w700)
          : QdText.body.copyWith(color: c.textPrimary);
      return MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: labelStyle)),
            const SizedBox(width: QdSpace.x3),
            Text(value, style: valueStyle),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(QdRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: QdSpace.x2),
            line(lines[i].label, lines[i].value),
          ],
          if (totalLabel != null && totalValue != null) ...[
            if (lines.isNotEmpty) ...[
              const SizedBox(height: QdSpace.x2),
              Container(height: 1, color: c.fillMuted),
              const SizedBox(height: QdSpace.x2),
            ],
            line(totalLabel!, totalValue!, total: true),
          ],
          if (note != null) ...[
            const SizedBox(height: QdSpace.x2),
            Text(note!,
                style: QdText.caption
                    .copyWith(color: c.textSecondary, height: 1.6)),
          ],
        ],
      ),
    );
  }
}
