import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
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

/// Bordered group of arbitrary rows with 1 dp dividers (per-day hours,
/// activity lists). The border is drawn over the rows so row fills never
/// cover it.
class OwnerBorderedColumn extends StatelessWidget {
  const OwnerBorderedColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final radius = BorderRadius.circular(QdRadius.card);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: radius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Container(height: 1, color: c.fillMuted),
              children[i],
            ],
          ],
        ),
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

/// KYB status banner (A-Owner): not uploaded, under review, or rejected
/// with the reviewer's reason; the action opens the verification page.
class OwnerKybBanner extends StatelessWidget {
  const OwnerKybBanner(
      {super.key,
      required this.status,
      required this.reason,
      required this.onOpen});

  final String status;
  final String? reason;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pending = status == 'pending_super_admin_approval';
    final rejected = status == 'rejected';
    final why = reason?.trim() ?? '';
    return QdBanner(
      key: Key(
          'own_kyb_${rejected ? 'rejected' : pending ? 'pending' : 'missing'}'),
      tone: rejected
          ? QdBannerTone.danger
          : pending
              ? QdBannerTone.warning
              : QdBannerTone.info,
      icon: rejected
          ? Icons.error_outline
          : pending
              ? Icons.hourglass_top
              : Icons.verified_user_outlined,
      title: rejected
          ? l10n.ownKybRejectedTitle
          : pending
              ? l10n.ownKybPendingTitle
              : l10n.ownKybMissingTitle,
      message: rejected
          ? (why.isEmpty ? l10n.ownKybRejectedBody : why)
          : pending
              ? l10n.ownKybPendingBody
              : l10n.ownKybMissingBody,
      actionLabel: rejected
          ? l10n.ownKybUploadAgain
          : pending
              ? l10n.ownKybView
              : l10n.ownKybUpload,
      onAction: onOpen,
    );
  }
}
