import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/login_page.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/utils/logout_helper.dart';

import 'features/auth/auth_harness.dart';

/// HOTFIX-LOGIN: logging out opens the signed-out start screen the
/// QD_REDESIGN_AUTH flag picks, for every role, and clears the stack.
void main() {
  const signedInKey = Key('signed_in_page');

  Future<AuthTestDeps> logOut(WidgetTester tester, {bool? redesign}) async {
    // The redesigned pages are laid out for phones; the old LoginScreen is
    // tested on the default surface like its other tests.
    if (redesign ?? false) usePhone(tester);
    final deps = AuthTestDeps(
        auth: FakeAuthFlow(user: FakeAuthFlow.customer(), token: 'jwt'));
    await tester.pumpWidget(authApp(
      deps,
      Builder(
        builder: (context) => Scaffold(
          key: signedInKey,
          body: TextButton(
            onPressed: () => redesign == null
                ? logoutAndClearProviders(context)
                : logoutAndClearProviders(context, redesign: redesign),
            child: const Text('log out'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('log out'));
    await tester.pumpAndSettle();
    return deps;
  }

  testWidgets('flag off (default build): opens LoginScreen', (tester) async {
    final deps = await logOut(tester);
    expect(deps.auth.calls, contains('logout:'));
    expect(deps.auth.isAuthenticated, isFalse);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byKey(signedInKey), findsNothing);
  });

  testWidgets('flag off explicitly: opens LoginScreen', (tester) async {
    await logOut(tester, redesign: false);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('flag on: opens the redesigned LoginPage, stack cleared',
      (tester) async {
    final deps = await logOut(tester, redesign: true);
    expect(deps.auth.calls, contains('logout:'));
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(signedInKey), findsNothing);
  });
}
