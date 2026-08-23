import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart' show JobLocation;
import 'package:frontend/models/reconciliation_job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/reconciliation_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/chat_screen.dart';
import 'package:frontend/screens/owner_reconciliation_queue_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/widgets/confirm_action_dialog.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';
import 'package:frontend/widgets/themed_error_banner.dart';
import 'package:provider/provider.dart';

/// QA audit A4 regression tests: debounce / double-submit protection.
///
/// Every test asserts on the NETWORK-CALL COUNT (or handler invocation
/// count), never merely that a widget "looks disabled". The critical
/// scenario each screen-level test exercises is the one the 600ms timestamp
/// debounce cannot cover: a second tap AFTER the window has expired while
/// the first network call is still in flight.

// ---------------------------------------------------------------------------
// Shared button unit tests
// ---------------------------------------------------------------------------

class _GatedAsyncHandler {
  int calls = 0;
  final Completer<void> gate = Completer<void>();

  Future<void> handle() async {
    calls++;
    await gate.future;
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('PrimaryButton in-flight double-submit lock', () {
    testWidgets('blocks second tap beyond debounce window while async handler is pending',
        (tester) async {
      final handler = _GatedAsyncHandler();
      DateTime fakeNow = DateTime(2026, 1, 1, 12, 0, 0);

      await tester.pumpWidget(_wrap(PrimaryButton(
        text: 'Pay',
        onPressed: handler.handle,
        nowProvider: () => fakeNow,
      )));

      // First tap starts the async call (held open by the gate).
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(handler.calls, 1);

      // Advance past the 600ms timestamp-debounce window: ONLY the new
      // in-flight lock can block this second tap.
      fakeNow = fakeNow.add(const Duration(milliseconds: 700));
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(handler.calls, 1,
          reason: 'second tap after debounce window expired must be blocked '
              'by the in-flight lock while the first call is pending');

      handler.gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('allows a genuine second invocation after the first completes',
        (tester) async {
      final handler = _GatedAsyncHandler()..gate.complete();
      DateTime fakeNow = DateTime(2026, 1, 1, 12, 0, 0);

      await tester.pumpWidget(_wrap(PrimaryButton(
        text: 'Refresh',
        onPressed: handler.handle,
        nowProvider: () => fakeNow,
      )));

      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(handler.calls, 1);

      fakeNow = fakeNow.add(const Duration(milliseconds: 700));
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(handler.calls, 2,
          reason: 'lock must release once the first call completes');
    });

    testWidgets('timestamp debounce still applies to sync handlers',
        (tester) async {
      int calls = 0;
      DateTime fakeNow = DateTime(2026, 1, 1, 12, 0, 0);

      await tester.pumpWidget(_wrap(PrimaryButton(
        text: 'Sync',
        onPressed: () => calls++,
        nowProvider: () => fakeNow,
      )));

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(calls, 1, reason: 'rapid second tap blocked by existing debounce');
    });
  });

  group('SecondaryButton in-flight double-submit lock', () {
    testWidgets('blocks second tap beyond debounce window while pending',
        (tester) async {
      final handler = _GatedAsyncHandler();
      DateTime fakeNow = DateTime(2026, 1, 1, 12, 0, 0);

      await tester.pumpWidget(_wrap(SecondaryButton(
        text: 'Cancel',
        onPressed: handler.handle,
        nowProvider: () => fakeNow,
      )));

      await tester.tap(find.byType(SecondaryButton));
      await tester.pump();
      expect(handler.calls, 1);

      fakeNow = fakeNow.add(const Duration(milliseconds: 700));
      await tester.tap(find.byType(SecondaryButton));
      await tester.pump();

      expect(handler.calls, 1);

      handler.gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('ThemedErrorBanner retry guard', () {
    testWidgets('double-tap fires retry exactly once', (tester) async {
      int retries = 0;

      await tester.pumpWidget(_wrap(ThemedErrorBanner(
        message: 'Something failed',
        onRetry: () => retries++,
      )));

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1, reason: 'rapid double-tap must not re-fire retry');

      // Past the debounce window a real retry is allowed again — verified
      // with genuine wall-clock time (runAsync escapes fake-async so the
      // banner's real DateTime.now() guard sees an expired window).
      await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 650)));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 2);
    });
  });

  // -------------------------------------------------------------------------
  // Screen-level tests
  // -------------------------------------------------------------------------

  final testJob = ReconciliationJob(
    id: 'job-a4-escrow',
    ownerId: 'owner-1',
    serviceId: 'service-1',
    userId: 'customer-1',
    employeeId: 'employee-1',
    status: 'escrow_reconciliation_required',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'escrow',
    lockedEscrowAmount: 50.0,
    reconciliationNote: 'distance mismatch',
    escrowFailureReason: 'under_distance_mismatch',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  testWidgets(
      '(A4-P1) reconciliation resolve: confirm dialog re-entry cannot fire resolveJob twice',
      (tester) async {
    final gate = Completer<void>();
    int resolveCalls = 0;
    final apiClient = ApiClient();
    final provider = _GatedReconciliationProvider(apiClient, [testJob],
        onResolve: () async {
          resolveCalls++;
          await gate.future;
        });

    await tester.pumpWidget(_buildReconciliationApp(provider));
    await tester.pumpAndSettle();

    // Open confirm dialog for Release to Employee. NOTE: bounded pumps only
    // from here until the gate completes — the in-flight guard flips both
    // action buttons to isLoading spinners behind the modal BY DESIGN, so
    // pumpAndSettle would never settle while the resolution is pending.
    await tester.tap(find.text('Release to Employee'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Cancel'), findsOneWidget,
        reason: 'confirm dialog must be open');
    await tester.tap(find.text('Confirm Release to Employee').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(resolveCalls, 1);

    // Real wall-clock advance past every client-side debounce window while
    // the money-moving POST is STILL pending. This is exactly the window a
    // slow backend leaves open for the "nothing happened, tap again" harm.
    // runAsync escapes fake-async so DateTime.now()-based guards truly age.
    await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 700)));

    // Re-entry attempt: past every debounce window, the money-moving POST
    // still pending. The action buttons must be hard-disabled (isLoading
    // spinner replaces the label, so find.text no longer sees it), and a
    // blind tap on the disabled control must do nothing.
    expect(find.text('Confirm Release to Employee'), findsNothing,
        reason: 'no second confirmation dialog may open while a resolution '
            'is already in flight');

    final releaseBtn =
        tester.widget<PrimaryButton>(find.byType(PrimaryButton).first);
    expect(releaseBtn.isLoading, isTrue,
        reason: 'release button must show in-flight state while resolveJob '
            'is pending');
    expect(releaseBtn.onPressed, isNull,
        reason: 'release button must be hard-disabled while pending');

    await tester.tap(find.byType(PrimaryButton).first, warnIfMissed: false);
    await tester.pump();
    expect(find.byType(ConfirmActionDialog), findsNothing);

    expect(provider.resolveJobCallCount, 1);
    expect(resolveCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(resolveCalls, 1,
        reason: 'exactly-once end state after the gated call settles');
    expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton).first).isLoading,
        isFalse,
        reason: 'in-flight state must clear once the call settles');
  });

  testWidgets('(A4-P2) chat send: double-tap sends message exactly once',
      (tester) async {
    final gate = Completer<void>();
    final sent = <String>[];
    final chatProvider = _GatedChatProvider(ApiClient(),
        onSend: (text) async {
          sent.add(text);
          await gate.future;
        });

    await tester.pumpWidget(_buildChatApp(chatProvider));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello escrow');
    await tester.pump();

    // First send starts (gated mid-flight).
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    // Second tap arrives while the first is still pending. The InkWell has
    // no built-in guard of its own; the handler flag must absorb it.
    await tester.tap(find.byIcon(Icons.send_rounded), warnIfMissed: false);
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(sent, ['hello escrow'],
        reason: 'double-tap on send must deliver exactly one message');
  });

  testWidgets('(A4-P2) settings logout: second tap during logout flow ignored',
      (tester) async {
    final gate = Completer<void>();
    int logoutCalls = 0;
    final authProvider =
        _GatedAuthProvider(ApiClient(), onLogout: () async {
      logoutCalls++;
      await gate.future;
    });

    await tester.pumpWidget(_buildSettingsApp(authProvider));
    await tester.pumpAndSettle();

    final logoutBtn = find.byKey(const Key('settings_logout_button'));
    await tester.ensureVisible(logoutBtn);
    await tester.pumpAndSettle();

    await tester.tap(logoutBtn);
    await tester.pump();
    expect(logoutCalls, 1);

    // Past any 600ms window while logout is still in flight (runAsync lets
    // real wall-clock time pass inside the fake-async test zone).
    await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 700)));
    await tester.tap(find.byKey(const Key('settings_logout_button')),
        warnIfMissed: false);
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(logoutCalls, 1,
        reason: 'logout must fire exactly once even under double-tap');
  });
}

// ---------------------------------------------------------------------------
// Mocks & builders
// ---------------------------------------------------------------------------

class _GatedReconciliationProvider extends ReconciliationProvider {
  _GatedReconciliationProvider(super.apiClient, List<ReconciliationJob> jobs,
      {required this.onResolve}) {
    _testQueue = List.from(jobs);
  }

  final Future<void> Function() onResolve;
  int resolveJobCallCount = 0;
  late final List<ReconciliationJob> _testQueue;

  @override
  List<ReconciliationJob> get queue => List.unmodifiable(_testQueue);

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  void clearError() {}

  @override
  Future<bool> resolveJob({
    required String jobId,
    required String decision,
  }) async {
    resolveJobCallCount++;
    await onResolve();
    return true;
  }
}

Widget _buildReconciliationApp(ReconciliationProvider provider) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<ReconciliationProvider>.value(
      value: provider,
      child: const OwnerReconciliationQueueScreen(),
    ),
  );
}

class _GatedChatProvider extends ChatProvider {
  _GatedChatProvider(super.apiClient, {required this.onSend});

  final Future<void> Function(String text) onSend;

  @override
  Future<void> fetchHistory(String jobId, String token) async {}

  @override
  void connectAndSubscribe(String jobId, String token) {}

  @override
  Future<void> sendMessage(String text) => onSend(text);
}

Widget _buildChatApp(ChatProvider chatProvider) {
  final auth = AuthProvider(ApiClient());
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
      ],
      child: const ChatScreen(jobId: 'job-a4-chat'),
    ),
  );
}

class _GatedAuthProvider extends AuthProvider {
  _GatedAuthProvider(super.apiClient, {required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-a4',
        email: 'a4@test.local',
        username: 'a4tester',
        role: 'owner',
      );

  @override
  String? get token => 'mock-token';

  @override
  Future<void> logout() => onLogout();
}

class _FakeSecureStorage extends FlutterSecureStorage {}

Widget _buildSettingsApp(AuthProvider authProvider) {
  final themeProvider = ThemeProvider(storage: _FakeSecureStorage());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<NotificationsProvider>(
        create: (_) => NotificationsProvider(ApiClient()),
      ),
      ChangeNotifierProvider<ChatProvider>(
        create: (_) => ChatProvider(ApiClient()),
      ),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(),
    ),
  );
}
