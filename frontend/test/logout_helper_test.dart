import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/login_page.dart';
import 'package:frontend/utils/logout_helper.dart';

import 'features/auth/auth_harness.dart';

/// HOTFIX-LOGIN: logging out opens the sign-in page for every role and
/// clears the stack.
void main() {
  const signedInKey = Key('signed_in_page');

  testWidgets('opens the sign-in page, stack cleared', (tester) async {
    usePhone(tester);
    final deps = AuthTestDeps(
        auth: FakeAuthFlow(user: FakeAuthFlow.customer(), token: 'jwt'));
    await tester.pumpWidget(authApp(
      deps,
      Builder(
        builder: (context) => Scaffold(
          key: signedInKey,
          body: TextButton(
            onPressed: () => logoutAndClearProviders(context),
            child: const Text('log out'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('log out'));
    await tester.pumpAndSettle();
    expect(deps.auth.calls, contains('logout:'));
    expect(deps.auth.isAuthenticated, isFalse);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byKey(signedInKey), findsNothing);
  });
}
