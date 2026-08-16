import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/notifications_screen.dart';
import 'package:frontend/widgets/confirm_action_dialog.dart';
import 'package:frontend/widgets/primary_button.dart';

class MockNotificationsProvider extends NotificationsProvider {
  final List<NotificationModel> _mockList;
  bool clearAllCalled = false;
  String? lastMarkedReadId;
  String? lastDismissedId;

  MockNotificationsProvider(super.apiClient, this._mockList);

  @override
  List<NotificationModel> get notifications => _mockList;

  @override
  bool get isConnected => true;

  @override
  void markAsRead(String id) {
    lastMarkedReadId = id;
    final idx = _mockList.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final old = _mockList[idx];
      _mockList[idx] = NotificationModel(
        id: old.id,
        tenantId: old.tenantId,
        title: old.title,
        body: old.body,
        type: old.type,
        isRead: true,
        timestamp: old.timestamp,
      );
      notifyListeners();
    }
  }

  @override
  void dismiss(String id) {
    lastDismissedId = id;
    _mockList.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  @override
  void clearAll() {
    clearAllCalled = true;
    _mockList.clear();
    notifyListeners();
  }
}

class MockAuthProviderForNotifs extends AuthProvider {
  MockAuthProviderForNotifs(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'user-1',
        email: 'user@example.com',
        username: 'test_user',
        role: 'user',
      );

  @override
  String? get token => 'mock-token';
}

Widget createNotificationsTestApp({
  required NotificationsProvider notificationsProvider,
  required AuthProvider authProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationsProvider>.value(
          value: notificationsProvider),
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: quickDeliveryTheme,
      home: const NotificationsScreen(),
    ),
  );
}

void main() {
  late ApiClient apiClient;

  setUp(() {
    apiClient = ApiClient();
  });

  testWidgets('NotificationsScreen shows empty state when list is empty',
      (WidgetTester tester) async {
    final notifsProvider = MockNotificationsProvider(apiClient, []);
    final authProvider = MockAuthProviderForNotifs(apiClient);

    await tester.pumpWidget(createNotificationsTestApp(
      notificationsProvider: notifsProvider,
      authProvider: authProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsWidgets);
    expect(find.text('Back to Home'), findsOneWidget);
  });

  testWidgets('NotificationsScreen renders items and filters by category',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final items = [
      NotificationModel(
        id: 'job-1',
        tenantId: 'tenant-1',
        title: 'New Job Available',
        body: 'A new delivery job is ready',
        type: 'job_alert',
        isRead: false,
        timestamp: now,
      ),
      NotificationModel(
        id: 'sys-1',
        tenantId: 'tenant-1',
        title: 'System Maintenance',
        body: 'Scheduled tonight',
        type: 'system',
        isRead: true,
        timestamp: now.subtract(const Duration(days: 1)),
      ),
    ];

    final notifsProvider = MockNotificationsProvider(apiClient, items);
    final authProvider = MockAuthProviderForNotifs(apiClient);

    await tester.pumpWidget(createNotificationsTestApp(
      notificationsProvider: notifsProvider,
      authProvider: authProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.text('New Job Available'), findsOneWidget);
    expect(find.text('System Maintenance'), findsOneWidget);

    // Filter to Jobs
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();

    expect(find.text('New Job Available'), findsOneWidget);
    expect(find.text('System Maintenance'), findsNothing);

    // Filter to System
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();

    expect(find.text('New Job Available'), findsNothing);
    expect(find.text('System Maintenance'), findsOneWidget);
  });

  testWidgets(
      'NotificationsScreen clear all dialog triggers ConfirmActionDialog',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final items = [
      NotificationModel(
        id: 'job-1',
        tenantId: 'tenant-1',
        title: 'New Job Available',
        body: 'A new delivery job is ready',
        type: 'job_alert',
        isRead: false,
        timestamp: now,
      ),
    ];

    final notifsProvider = MockNotificationsProvider(apiClient, items);
    final authProvider = MockAuthProviderForNotifs(apiClient);

    await tester.pumpWidget(createNotificationsTestApp(
      notificationsProvider: notifsProvider,
      authProvider: authProvider,
    ));
    await tester.pumpAndSettle();

    // Tap delete sweep icon
    final clearBtn = find.byIcon(Icons.delete_sweep);
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    // Confirm dialog is shown
    expect(find.byType(ConfirmActionDialog), findsOneWidget);

    // Cancel first
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(notifsProvider.clearAllCalled, isFalse);
    expect(find.text('New Job Available'), findsOneWidget);

    // Tap delete sweep again and confirm
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    // In ConfirmActionDialog, confirm button is a PrimaryButton
    final dialogConfirmBtn = find.descendant(
      of: find.byType(PrimaryButton),
      matching: find.text('Clear All'),
    );
    await tester.tap(dialogConfirmBtn);
    await tester.pumpAndSettle();

    expect(notifsProvider.clearAllCalled, isTrue);
    expect(find.text('Back to Home'), findsOneWidget);
  });

  testWidgets(
      'NotificationsScreen handles card tap to mark as read and dismiss action',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final items = [
      NotificationModel(
        id: 'job-1',
        tenantId: 'tenant-1',
        title: 'New Job Available',
        body: 'A new delivery job is ready',
        type: 'job_alert',
        isRead: false,
        timestamp: now,
      ),
    ];

    final notifsProvider = MockNotificationsProvider(apiClient, items);
    final authProvider = MockAuthProviderForNotifs(apiClient);

    await tester.pumpWidget(createNotificationsTestApp(
      notificationsProvider: notifsProvider,
      authProvider: authProvider,
    ));
    await tester.pumpAndSettle();

    // Tap card
    await tester.tap(find.text('New Job Available'));
    await tester.pumpAndSettle();
    expect(notifsProvider.lastMarkedReadId, 'job-1');

    // Tap dismiss icon
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(notifsProvider.lastDismissedId, 'job-1');
  });

  testWidgets(
      'NotificationsScreen renders without overflow on 360x800 mobile viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime.now();
    final items = [
      NotificationModel(
        id: 'job-1',
        tenantId: 'tenant-1',
        title: 'New Job Available with a long description title for testing',
        body:
            'A new delivery job is ready and waiting for dispatch immediately.',
        type: 'job_alert',
        isRead: false,
        timestamp: now,
      ),
    ];

    final notifsProvider = MockNotificationsProvider(apiClient, items);
    final authProvider = MockAuthProviderForNotifs(apiClient);

    await tester.pumpWidget(createNotificationsTestApp(
      notificationsProvider: notifsProvider,
      authProvider: authProvider,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Jobs'), findsOneWidget);
  });
}
