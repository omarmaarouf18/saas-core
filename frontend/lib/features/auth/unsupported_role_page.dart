import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';
import '../account/account_nav.dart';
import 'widgets/auth_scaffold.dart';

/// Shown when a signed-in role has no screens in the app (staff roles such
/// as admin or reviewer, which use the web console): what happened and a
/// sign-out button. Replaces the old generic dashboard these roles got.
class UnsupportedRolePage extends StatelessWidget {
  const UnsupportedRolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthScaffold(
      key: const Key('unsupported_role_page'),
      footer: QdButton.secondary(
        key: const Key('unsupported_role_sign_out'),
        label: l10n.acctLogout,
        icon: Icons.logout,
        fullWidth: true,
        onPressed: () => AccountNavScope.of(context).signOut(context),
      ),
      children: [
        const SizedBox(height: 48),
        AuthHeading(
          title: l10n.roleUnsupportedTitle,
          subtitle: l10n.roleUnsupportedBody,
        ),
      ],
    );
  }
}
