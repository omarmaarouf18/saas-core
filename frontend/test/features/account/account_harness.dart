import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_nav.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/ui/qd_ui.dart';
import 'package:provider/provider.dart';

import '../auth/auth_harness.dart';

export '../auth/auth_harness.dart';

class FakeNotificationsStream extends ChangeNotifier
    implements NotificationsProvider {
  int unsubscribes = 0;

  @override
  void unsubscribe() => unsubscribes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records hand-offs to screens outside the account pages.
class RecordingAccountNav extends AccountNav {
  int notifications = 0;
  int support = 0;

  @override
  Future<void> openNotifications(BuildContext context) async => notifications++;

  @override
  Future<void> openSupport(BuildContext context) async => support++;
}

class AccountTestDeps extends AuthTestDeps {
  AccountTestDeps({FakeAuthFlow? auth})
      : super(auth: auth ?? FakeAuthFlow(user: FakeAuthFlow.customer())) {
    extra.add(ChangeNotifierProvider<NotificationsProvider>.value(
        value: notifications));
  }

  final FakeNotificationsStream notifications = FakeNotificationsStream();
  final RecordingAccountNav accountNav = RecordingAccountNav();
}

/// An account page inside the auth test app, under the redesign theme (in
/// the app it sits in the customer shell, which provides it).
Widget accountApp(AccountTestDeps deps, Widget page, {Locale locale = en}) =>
    authApp(
      deps,
      AccountNavScope(nav: deps.accountNav, child: QdThemeScope(child: page)),
      locale: locale,
    );

Future<void> pumpAccount(WidgetTester tester, AccountTestDeps deps, Widget page,
    {Locale locale = en}) async {
  usePhone(tester);
  await tester.pumpWidget(accountApp(deps, page, locale: locale));
  await tester.pumpAndSettle();
}
