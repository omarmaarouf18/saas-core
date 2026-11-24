import 'package:flutter/material.dart';

import '../../core/app_client.dart';
import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';
import '../account/account_nav.dart';
import 'widgets/auth_scaffold.dart';

/// Shown when the signed-in role has no screens in this app, with a
/// sign-out button.
///
/// - [rightApp] set (SPLIT-APPS, ADR-0030): the role belongs to another
///   Waddify app (a customer in Waddify Console, say); the page names that
///   app. The user is never routed into another role's shell.
/// - [rightApp] null: a staff role (admin, reviewer) with no app at all;
///   they use the web console.
class UnsupportedRolePage extends StatelessWidget {
  const UnsupportedRolePage({super.key, this.rightApp});

  final AppClient? rightApp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final app = rightApp;
    return AuthScaffold(
      key: Key(app == null ? 'unsupported_role_page' : 'wrong_app_page'),
      footer: QdButton.secondary(
        key: const Key('unsupported_role_sign_out'),
        label: l10n.acctLogout,
        icon: Icons.logout,
        fullWidth: true,
        onPressed: () => AccountNavScope.of(context).signOut(context),
      ),
      children: [
        const SizedBox(height: 48),
        if (app == null)
          AuthHeading(
            title: l10n.roleUnsupportedTitle,
            subtitle: l10n.roleUnsupportedBody,
          )
        else
          AuthHeading(
            title: l10n.wrongAppTitle,
            subtitle: l10n.wrongAppBody(app.displayName),
          ),
      ],
    );
  }
}
