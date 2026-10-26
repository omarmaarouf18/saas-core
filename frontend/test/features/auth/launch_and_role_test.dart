import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/launch_splash.dart';
import 'package:frontend/features/auth/unsupported_role_page.dart';
import 'package:frontend/ui/qd_theme_scope.dart';

import 'auth_harness.dart';

void main() {
  testWidgets('launch splash: brand and spinner, light and dark',
      (tester) async {
    usePhone(tester);
    final deps = AuthTestDeps();
    await tester
        .pumpWidget(authApp(deps, const QdThemeScope(child: LaunchSplash())));
    expect(find.byKey(const Key('auth_splash_screen')), findsOneWidget);
    expect(find.text('Quick Delivery'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await deps.theme.setThemeMode(ThemeMode.dark);
    await tester.pump();
    expect(find.byKey(const Key('auth_splash_screen')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a role without screens: message and sign out', (tester) async {
    usePhone(tester);
    final deps = AuthTestDeps();
    await tester.pumpWidget(authApp(deps, const UnsupportedRolePage()));
    await tester.pumpAndSettle();
    expect(find.text("This account can't use the app"), findsOneWidget);
    await tester.tap(find.byKey(const Key('unsupported_role_sign_out')));
    await tester.pumpAndSettle();
    expect(deps.nav.signedOut, 1);
  });
}
