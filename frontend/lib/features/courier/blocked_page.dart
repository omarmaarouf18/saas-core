import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import 'courier_nav.dart';

/// Shown instead of the courier tabs while the account is suspended by a
/// reviewer or paused (frozen) by the company: both come back from the
/// auth service as `account_status: suspended`, a reviewer suspension with
/// its reason. The courier cannot take orders, so there are no job tabs;
/// they can check again, contact support or sign out. (The old courier app
/// ignored the account state.)
class CourierBlockedPage extends StatefulWidget {
  const CourierBlockedPage({super.key});

  @override
  State<CourierBlockedPage> createState() => _CourierBlockedPageState();
}

class _CourierBlockedPageState extends State<CourierBlockedPage> {
  bool _checking = false;
  bool _signingOut = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    await context.read<AuthProvider>().fetchUserProfile();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await CourierNavScope.of(context).signOut(context);
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final user = context.watch<AuthProvider>().user;
    final reason = user?.suspensionReason?.trim();
    final hasReason = reason != null && reason.isNotEmpty;
    final nav = CourierNavScope.of(context);

    return Scaffold(
      key: const Key('courier_blocked'),
      backgroundColor: c.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, 48, QdSpace.gutter, QdSpace.x6),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                width: QdSize.iconTileLg,
                height: QdSize.iconTileLg,
                decoration: BoxDecoration(
                  color: c.dangerBg,
                  borderRadius: BorderRadius.circular(QdRadius.sm),
                ),
                child: Icon(Icons.block, color: c.danger, size: QdSize.iconLg),
              ),
            ),
            const SizedBox(height: QdSpace.x5),
            Text(l10n.courBlockedTitle,
                style: QdText.sheetTitle.copyWith(color: c.textPrimary)),
            const SizedBox(height: QdSpace.x2),
            Text(
              hasReason ? l10n.courBlockedSuspended : l10n.courBlockedPaused,
              key: const Key('courier_blocked_body'),
              style: QdText.body.copyWith(color: c.textSecondary),
            ),
            if (hasReason) ...[
              const SizedBox(height: QdSpace.x4),
              QdBanner(
                key: const Key('courier_blocked_reason'),
                tone: QdBannerTone.danger,
                title: l10n.courBlockedReason,
                message: reason,
              ),
            ],
            const SizedBox(height: QdSpace.x4),
            Text(l10n.courBlockedWhat,
                style: QdText.secondary.copyWith(color: c.textSecondary)),
            const SizedBox(height: QdSpace.x6),
            QdButton(
              key: const Key('courier_blocked_check'),
              label: l10n.courBlockedCheck,
              fullWidth: true,
              loading: _checking,
              onPressed: _check,
            ),
            const SizedBox(height: QdSpace.x3),
            QdButton.secondary(
              key: const Key('courier_blocked_support'),
              label: l10n.acctSupport,
              fullWidth: true,
              onPressed: () => nav.openSupport(context),
            ),
            const SizedBox(height: QdSpace.x2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: QdButton.destructive(
                key: const Key('courier_blocked_sign_out'),
                label: l10n.acctLogout,
                loading: _signingOut,
                onPressed: _signOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
