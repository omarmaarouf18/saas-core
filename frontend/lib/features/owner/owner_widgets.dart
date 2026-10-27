import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';
import 'owner_rules.dart';

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
  const OwnerInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.trailing,
  });

  final String label;
  final String value;

  /// Second line under the value (recipient / package notes).
  final String? note;

  /// After the value (a call button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final text = MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: QdText.body.copyWith(color: c.textSecondary)),
          const SizedBox(width: QdSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.end,
                  style: QdText.body.copyWith(
                      color: c.textPrimary, fontWeight: FontWeight.w500),
                ),
                if (note != null)
                  Text(note!,
                      textAlign: TextAlign.end,
                      style: QdText.caption.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 14, vertical: QdSpace.x3),
      // The trailing button stays its own semantics node.
      child: trailing == null
          ? text
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: QdSpace.x2),
                trailing!,
              ],
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

/// The courier's ID check (KYE) chip, worded like the verification pages:
/// Verified / Under review / Not accepted / Not uploaded.
QdStatusChip kyeChip(AppLocalizations l10n, KyeState s, {Key? key}) =>
    switch (s) {
      KyeState.approved => QdStatusChip(
          key: key, label: l10n.acctKyeApproved, tone: QdTone.success),
      KyeState.pending => QdStatusChip(
          key: key, label: l10n.acctKyePending, tone: QdTone.warning),
      KyeState.rejected => QdStatusChip(
          key: key, label: l10n.acctKyeRejected, tone: QdTone.danger),
      KyeState.none => QdStatusChip(
          key: key, label: l10n.acctKyeMissing, tone: QdTone.neutral),
    };

String kyeLabel(AppLocalizations l10n, KyeState s) => switch (s) {
      KyeState.approved => l10n.acctKyeApproved,
      KyeState.pending => l10n.acctKyePending,
      KyeState.rejected => l10n.acctKyeRejected,
      KyeState.none => l10n.acctKyeMissing,
    };

/// The member's verification as an owner can see it: the state and what
/// it means. Owners cannot open a courier's documents (only reviewers
/// can, `/auth/kyb-kye/user-documents`); the courier uploads them from
/// their own app.
Future<void> showKyeSheet(BuildContext context, OwnerEmployee e) {
  final l10n = context.l10n;
  final state = kyeStateOf(e.kyeStatus);
  final name = e.displayName;
  final body = switch (state) {
    KyeState.approved => l10n.ownKyeBodyApproved(name),
    KyeState.pending => l10n.ownKyeBodyPending(name),
    KyeState.rejected => l10n.ownKyeBodyRejected(name),
    KyeState.none => l10n.ownKyeBodyMissing(name),
  };
  return QdBottomSheet.show<void>(
    context,
    title: l10n.ownEmpIdCheck,
    child: Builder(builder: (sheet) {
      final c = QdColors.of(sheet);
      return Column(
        key: const Key('own_kye_sheet'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          kyeChip(l10n, state),
          const SizedBox(height: QdSpace.x3),
          Text(body, style: QdText.body.copyWith(color: c.textSecondary)),
        ],
      );
    }),
  );
}
