import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_nav.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/providers/notifications_provider.dart';
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

  int verification = 0;

  @override
  Future<void> openVerification(BuildContext context) async => verification++;
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

/// An account page inside the auth test app (the app theme, as in
/// main.dart).
Widget accountApp(AccountTestDeps deps, Widget page, {Locale locale = en}) =>
    authApp(
      deps,
      AccountNavScope(nav: deps.accountNav, child: page),
      locale: locale,
    );

Future<void> pumpAccount(WidgetTester tester, AccountTestDeps deps, Widget page,
    {Locale locale = en}) async {
  usePhone(tester);
  await tester.pumpWidget(accountApp(deps, page, locale: locale));
  await tester.pumpAndSettle();
}

/// Notifications test data (FE-AUTH-ACCOUNT).
final DateTime now = DateTime(2026, 10, 19, 15, 30);

NotificationModel notif(String id, String type,
        {DateTime? at,
        bool read = false,
        String title = 'Server title',
        String body = 'Server body'}) =>
    NotificationModel(
      id: id,
      type: type,
      tenantId: 't',
      title: title,
      body: body,
      timestamp: at ?? now.subtract(const Duration(minutes: 5)),
      isRead: read,
    );

class FakeFeed extends ChangeNotifier implements NotificationsProvider {
  @override
  List<NotificationModel> notifications = [];

  @override
  bool isConnected = true;

  @override
  bool isLoadingHistory = false;

  @override
  bool isLoadingMore = false;

  @override
  bool hasMore = false;

  @override
  String? error;

  @override
  int get unreadCount => notifications.where((n) => !n.isRead).length;

  final List<String> calls = [];
  List<NotificationModel> nextHistory = [];
  Completer<void>? historyGate;

  @override
  Future<void> fetchHistory({bool refresh = false, int limit = 30}) async {
    calls.add('fetchHistory:$refresh');
    isLoadingHistory = true;
    notifyListeners();
    if (historyGate != null) await historyGate!.future;
    isLoadingHistory = false;
    notifications = List.of(nextHistory);
    notifyListeners();
  }

  @override
  Future<void> loadMore({int limit = 30}) async {
    calls.add('loadMore');
    notifications.add(notif('old', 'job_cancelled',
        at: now.subtract(const Duration(days: 9))));
    hasMore = false;
    notifyListeners();
  }

  @override
  Future<void> markAsRead(String id) async {
    calls.add('markAsRead:$id');
    notifications.firstWhere((n) => n.id == id).isRead = true;
    notifyListeners();
  }

  @override
  Future<void> markAllAsRead() async {
    calls.add('markAllAsRead');
    for (final n in notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  @override
  Future<void> dismiss(String id) async {
    calls.add('dismiss:$id');
    notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  @override
  Future<void> clearAll() async {
    calls.add('clearAll');
    notifications.clear();
    notifyListeners();
  }

  @override
  void initSse(String token) => calls.add('initSse:$token');

  @override
  void unsubscribe() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
