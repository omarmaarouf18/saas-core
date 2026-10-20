import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/employee_screen.dart';
import 'package:frontend/widgets/primary_button.dart';

/// SEC-07b backend contracts:
///  * POST /auth/employee/toggle fails closed with 503
///    (service_unavailable) when session revocation fails — the employee is
///    NOT frozen and the UI must say "temporarily unavailable, try again"
///    without mutating state.
///  * GET /auth/employees returns 500 on a database error (no more empty
///    200 []) — the screen must show the error banner with retry, never the
///    "no employees" empty state.
void main() {
  test('OwnerProvider.toggleEmployee propagates the 503 and records the error',
      () async {
    final api = _FailingToggleApi();
    final provider = OwnerProvider(api);

    await expectLater(
      provider.toggleEmployee(
        employeeEmail: 'courier@company.com',
        ownerEmail: 'owner@example.com',
        ownerPassword: 'owner-pass-9',
        setActive: false,
      ),
      throwsA(isA<ApiClientException>()
          .having((e) => e.statusCode, 'statusCode', 503)),
    );
    expect(provider.error, isNotNull);
  });

  testWidgets('Staff list 500 renders the error banner, not the empty state',
      (tester) async {
    final api = _FailingListApi();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => _StaticOwnerAuth(api),
          ),
          ChangeNotifierProvider<OwnerProvider>(create: (_) {
            final p = OwnerProvider(api);
            p.fetchEmployees('owner-token');
            return p;
          }),
        ],
        child: const MaterialApp(home: EmployeeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('employees_error_banner')), findsOneWidget);
    // The database outage must never read as an empty roster.
    expect(find.textContaining('No Employees Registered'), findsNothing);
    expect(find.textContaining('employees right now'), findsOneWidget);
  });

  testWidgets(
      'Freeze/unfreeze 503 shows the retry-not-changed message, roster intact',
      (tester) async {
    final api = _FailingToggleApi();

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => _StaticOwnerAuth(api),
          ),
          ChangeNotifierProvider<OwnerProvider>(
              create: (_) => OwnerProvider(api)),
        ],
        child: const MaterialApp(home: EmployeeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Open the toggle tile and submit.
    await tester
        .ensureVisible(find.byKey(const Key('freeze_worker_expansion_tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('freeze_worker_expansion_tile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('toggle_employee_email_input')),
        'courier@company.com');
    await tester.enterText(
        find.byKey(const Key('toggle_owner_password_input')), 'owner-pass-9');
    await tester.tap(find.byKey(const Key('employee_toggle_submit_button')));
    await tester.pumpAndSettle();

    // The destructive confirm dialog asks first; confirm the action.
    final dialogConfirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(PrimaryButton),
    );
    expect(dialogConfirm, findsOneWidget);
    await tester.tap(dialogConfirm);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Localized "temporarily unavailable — nothing changed" copy, not the
    // generic 5xx server line.
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(
        find.textContaining('Something went wrong on our end'), findsNothing);
  });
}

class _FailingToggleApi extends ApiClient {
  _FailingToggleApi() : super(baseUrl: 'http://localhost:3002');

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    if (path == '/auth/employee/toggle') {
      // Realistic backend 503 body (handlerutil.SafeError): the message the
      // user sees and the machine code lifted to ApiClientException.
      throw ApiClientException(
        'failed to freeze employee account, please retry',
        statusCode: 503,
        errorCode: 'service_unavailable',
      );
    }
    return {};
  }
}

class _FailingListApi extends ApiClient {
  _FailingListApi() : super(baseUrl: 'http://localhost:3002');

  @override
  Future<dynamic> get(String path,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (path == '/auth/employees') {
      throw ApiClientException('db unavailable', statusCode: 500);
    }
    if (path == '/auth/audit-log') {
      return {'count': 0, 'entries': []};
    }
    return {};
  }
}

class _StaticOwnerAuth extends AuthProvider {
  _StaticOwnerAuth(super.apiClient);

  @override
  String? get token => 'owner-token';

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-1',
        email: 'owner@example.com',
        username: 'OwnerUser',
        role: 'owner',
        kycStatus: 'approved',
      );
}
