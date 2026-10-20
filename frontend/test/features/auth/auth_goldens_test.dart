import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/login_page.dart';
import 'package:frontend/features/auth/otp_page.dart';
import 'package:frontend/features/auth/reset_password_page.dart';
import 'package:frontend/features/auth/signup_page.dart';
import 'package:frontend/features/auth/update_required_page.dart';

import '../customer/customer_harness.dart' show loadPlexFont;
import 'auth_harness.dart';

// Golden snapshots of the FE-AUTH-ACCOUNT signed-out screens at 360x800,
// light, AR-RTL and EN-LTR, with the bundled Plex font. Icons render as
// test-font boxes.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/auth/auth_goldens_test.dart

typedef _Setup = Future<void> Function(WidgetTester tester);

Future<void> _noSetup(WidgetTester tester) async {}

Future<void> _toCode(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reset_send_code')));
  await tester.pump();
  await _clearNotices(tester);
}

/// Notices are not part of the screens' pictures.
Future<void> _clearNotices(WidgetTester tester) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
      .clearSnackBars();
  await tester.pumpAndSettle();
}

Future<void> _toPassword(WidgetTester tester) async {
  await _toCode(tester);
  await tester.tap(find.byKey(const Key('otp_confirm')));
  await tester.pumpAndSettle();
  await _clearNotices(tester);
}

Future<void> _signupError(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('signup_submit')));
  await tester.pump();
}

final Map<String, (Widget, _Setup)> _screens = {
  'login': (const LoginPage(), _noSetup),
  'signup': (const SignupPage(), _signupError),
  'otp': (const OtpPage(email: 'mona@example.com', devOtp: '482913'), _noSetup),
  'reset_email': (
    const ResetPasswordPage(initialEmail: 'mona@example.com'),
    _noSetup
  ),
  'reset_code': (
    const ResetPasswordPage(initialEmail: 'mona@example.com'),
    _toCode
  ),
  'reset_password': (
    const ResetPasswordPage(initialEmail: 'mona@example.com'),
    _toPassword
  ),
  'update': (
    const UpdateRequiredPage(
      currentVersion: '1.0.0',
      minimumVersion: '1.2.0',
      latestVersion: '1.3.1',
      downloadUrl: 'https://example.com/quick-delivery.apk',
    ),
    _noSetup
  ),
};

void main() {
  setUpAll(loadPlexFont);

  _screens.forEach((name, entry) {
    final (page, setup) = entry;
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN auth $name $dir', (tester) async {
        usePhone(tester);
        final deps = AuthTestDeps()..auth.devOtp = '482913';
        await tester.pumpWidget(authApp(deps, page, locale: locale));
        await tester.pumpAndSettle();
        await setup(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/auth_${name}_${dir}_360x800.png'),
        );
        // Stop the resend countdown before the test ends.
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
