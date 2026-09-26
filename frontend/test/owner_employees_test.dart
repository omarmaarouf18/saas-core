import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/employee_screen.dart';
import 'package:frontend/widgets/status_badge.dart';
import 'package:frontend/widgets/confirm_action_dialog.dart';
import 'package:frontend/widgets/primary_button.dart';

class MockApiClientForEmployeesTest extends ApiClient {
  bool shouldFail = false;
  List<dynamic> mockEmployeesResponse = [
    {
      'id': 'emp-101',
      'username': 'driver_john',
      'email': 'john@company.com',
      'is_active': true,
      'created_at': '2026-01-01T10:00:00Z',
    },
    {
      'id': 'emp-102',
      'username': 'courier_sarah',
      'email': 'sarah@company.com',
      'is_active': false,
      'created_at': '2026-01-02T12:00:00Z',
    },
  ];

  @override
  Future<dynamic> get(String endpoint,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (endpoint == '/auth/employees') {
      if (shouldFail) {
        throw ApiClientException('Failed to fetch employees list',
            statusCode: 500);
      }
      return mockEmployeesResponse;
    }
    if (endpoint == '/auth/audit-log') {
      return {'count': 0, 'entries': []};
    }
    return {};
  }
}

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;

  MockAuthProviderForTest(super.apiClient,
      {this.mockUser, this.mockToken = 'test-owner-token'});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;

  @override
  Future<void> fetchUserProfile() async {}
}

class MockOwnerProviderForEmployeesTest extends OwnerProvider {
  List<dynamic> mockEmployees = [];
  bool mockIsLoading = false;
  String? mockError;
  bool fetchEmployeesCalled = false;
  String? lastTokenPassed;

  MockOwnerProviderForEmployeesTest(super.apiClient);

  @override
  List<dynamic> get employees => mockEmployees;

  @override
  bool get isLoading => mockIsLoading;

  @override
  String? get error => mockError;

  @override
  Future<List<dynamic>> fetchEmployees([String? ownerToken]) async {
    fetchEmployeesCalled = true;
    lastTokenPassed = ownerToken;
    return mockEmployees;
  }

  List<Map<String, dynamic>> mockAuditLogEntries = [];
  bool fetchAuditLogCalled = false;

  @override
  List<Map<String, dynamic>> get auditLogEntries => mockAuditLogEntries;

  @override
  Future<void> fetchAuditLog({
    String? tenantId,
    String? requesterToken,
    String? userId,
    String? userToken,
  }) async {
    fetchAuditLogCalled = true;
  }

  bool toggleEmployeeCalled = false;
  String? lastToggledEmail;
  bool? lastSetActive;

  @override
  Future<Map<String, dynamic>> toggleEmployee({
    required String employeeEmail,
    required String ownerEmail,
    required String ownerPassword,
    required bool setActive,
  }) async {
    toggleEmployeeCalled = true;
    lastToggledEmail = employeeEmail;
    lastSetActive = setActive;
    return {'message': 'Worker status successfully updated'};
  }
}

void main() {
  test(
      'OwnerProvider.fetchEmployees calls GET /auth/employees and parses array',
      () async {
    final apiClient = MockApiClientForEmployeesTest();
    final ownerProvider = OwnerProvider(apiClient);

    expect(ownerProvider.employees, isEmpty);

    final res = await ownerProvider.fetchEmployees('test-owner-token');

    expect(res.length, equals(2));
    expect(ownerProvider.employees.length, equals(2));
    expect(ownerProvider.employees[0]['username'], equals('driver_john'));
    expect(ownerProvider.employees[1]['username'], equals('courier_sarah'));
    expect(ownerProvider.employees[1]['is_active'], isFalse);
  });

  test(
      'OwnerProvider.fetchEmployees sets error message and clears employees on failure',
      () async {
    final apiClient = MockApiClientForEmployeesTest();
    apiClient.shouldFail = true;
    final ownerProvider = OwnerProvider(apiClient);

    final res = await ownerProvider.fetchEmployees('test-owner-token');

    expect(res, isEmpty);
    expect(ownerProvider.employees, isEmpty);
    expect(ownerProvider.error, isNotNull);
  });

  Widget createEmployeeScreenWidget({
    required MockOwnerProviderForEmployeesTest ownerProvider,
    MockAuthProviderForTest? authProvider,
  }) {
    final apiClient = ApiClient();
    final auth = authProvider ??
        MockAuthProviderForTest(
          apiClient,
          mockUser: UserProfile(
            id: 'owner-1',
            email: 'owner@example.com',
            username: 'OwnerUser',
            role: 'owner',
          ),
        );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
      ],
      child: const MaterialApp(
        home: EmployeeScreen(),
      ),
    );
  }

  testWidgets(
      'EmployeeScreen renders loading state while employees are being fetched',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockIsLoading = true;
    mockOwner.mockEmployees = [];

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));

    expect(find.byKey(const Key('employees_loading')), findsOneWidget);
    expect(find.text("Loading employee list..."), findsOneWidget);
  });

  testWidgets('EmployeeScreen renders empty state when zero employees exist',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockIsLoading = false;
    mockOwner.mockEmployees = [];

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('employees_empty_state')), findsOneWidget);
    expect(find.text("No Employees Registered"), findsOneWidget);
  });

  testWidgets(
      'EmployeeScreen renders registered employee cards with active and frozen badges',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockIsLoading = false;
    mockOwner.mockEmployees = [
      {
        'id': 'emp-101',
        'username': 'driver_john',
        'email': 'john@company.com',
        'is_active': true,
      },
      {
        'id': 'emp-102',
        'username': 'courier_sarah',
        'email': 'sarah@company.com',
        'is_active': false,
      },
    ];

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('employees_list_view')), findsOneWidget);
    expect(find.byKey(const Key('employee_item_emp-101')), findsOneWidget);
    expect(find.byKey(const Key('employee_item_emp-102')), findsOneWidget);

    expect(find.text('driver_john'), findsOneWidget);
    expect(find.text('john@company.com'), findsOneWidget);
    expect(find.text('courier_sarah'), findsOneWidget);
    expect(find.text('sarah@company.com'), findsOneWidget);

    expect(find.byType(StatusBadge), findsNWidgets(2));
  });

  testWidgets(
      'EmployeeScreen renders error banner when fetchEmployees returns error',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockIsLoading = false;
    mockOwner.mockEmployees = [];
    mockOwner.mockError = 'Failed to fetch employee roster';

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('employees_error_banner')), findsOneWidget);
    expect(find.text('Failed to fetch employee roster'), findsOneWidget);
  });

  testWidgets(
      'Audit trail tab renders error banner with retry on fetch failure, suppressing empty state (audit E8)',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockIsLoading = false;
    mockOwner.mockEmployees = [];
    mockOwner.mockError = 'Audit log fetch failed';

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    // Switch to Audit Trail tab
    await tester.tap(find.text('Audit Trail'));
    await tester.pumpAndSettle();

    // Error banner renders with retry, and empty state is NOT shown
    expect(find.byKey(const Key('audit_log_error_banner')), findsOneWidget);
    expect(find.text('Audit log fetch failed'), findsOneWidget);
    expect(find.text('No audit events recorded'), findsNothing);

    // Tap retry
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(mockOwner.fetchAuditLogCalled, isTrue);
  });

  testWidgets(
      'Audit trail tab renders empty state when zero events and no error',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockIsLoading = false;
    mockOwner.mockEmployees = [];
    mockOwner.mockError = null;
    mockOwner.mockAuditLogEntries = [];

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    // Switch to Audit Trail tab
    await tester.tap(find.text('Audit Trail'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('audit_log_error_banner')), findsNothing);
    expect(find.text('No audit events recorded'), findsOneWidget);
  });

  testWidgets(
      'EmployeeScreen renders actionable empty state when filters match zero workers (audit E4)',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockIsLoading = false;
    mockOwner.mockEmployees = [
      {
        'id': 'emp-101',
        'username': 'driver_john',
        'email': 'john@company.com',
        'is_active': true,
      },
    ];

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    expect(find.text('driver_john'), findsOneWidget);

    // Enter search term that matches nothing
    await tester.enterText(find.byType(TextField).first, 'nonexistent');
    await tester.pumpAndSettle();

    // Verify filtered empty state renders with clear filters action
    expect(find.byKey(const Key('filtered_empty_employees_state')),
        findsOneWidget);
    expect(find.text('No workers found matching your filter.'), findsOneWidget);
    expect(find.text('Clear Filters'), findsOneWidget);
    expect(find.text('driver_john'), findsNothing);

    // Tap Clear Filters
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();

    // Verify filter is cleared and worker card returns
    expect(
        find.byKey(const Key('filtered_empty_employees_state')), findsNothing);
    expect(find.text('driver_john'), findsOneWidget);
  });

  testWidgets(
      'Freezing worker shows ConfirmActionDialog with consequence explanation; cancel does not call toggleEmployee (audit E14)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockEmployees = [
      {
        'id': 'emp-101',
        'username': 'driver_john',
        'email': 'john@company.com',
        'is_active': true,
      },
    ];

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    // Expand the freeze worker disclosure (audit E23)
    final expansionFinder =
        find.byKey(const Key('freeze_worker_expansion_tile'));
    await tester.ensureVisible(expansionFinder);
    await tester.tap(expansionFinder);
    await tester.pumpAndSettle();

    // Scroll to freeze form submit button
    final submitFinder = find.byKey(const Key('employee_toggle_submit_button'));
    await tester.ensureVisible(submitFinder);

    // Fill in email and owner password
    final emailField = find.descendant(
      of: find.byKey(const Key('toggle_employee_email_input')),
      matching: find.byType(TextField),
    );
    final passwordField = find.descendant(
      of: find.byKey(const Key('toggle_owner_password_input')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(emailField);
    await tester.enterText(emailField, 'john@company.com');
    await tester.enterText(passwordField, 'secret123');
    await tester.pumpAndSettle();

    // Toggle switch to Freeze Worker mode (setActive = false)
    final switchFinder = find.byType(Switch);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Tap Freeze Worker submit button
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    // ConfirmActionDialog is displayed with consequence explanation
    expect(find.byType(ConfirmActionDialog), findsOneWidget);
    expect(find.text('Freeze Worker Account?'), findsOneWidget);
    expect(
      find.textContaining(
          'immediately block their login and hide them from active dispatch'),
      findsOneWidget,
    );

    // Cancel the dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // toggleEmployee should NOT have been called
    expect(find.byType(ConfirmActionDialog), findsNothing);
    expect(mockOwner.toggleEmployeeCalled, isFalse);
  });

  testWidgets(
      'Freezing worker confirms dialog and calls toggleEmployee with setActive: false (audit E14)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockEmployees = [
      {
        'id': 'emp-101',
        'username': 'driver_john',
        'email': 'john@company.com',
        'is_active': true,
      },
    ];

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    // Expand the freeze worker disclosure (audit E23)
    final expansionFinder =
        find.byKey(const Key('freeze_worker_expansion_tile'));
    await tester.ensureVisible(expansionFinder);
    await tester.tap(expansionFinder);
    await tester.pumpAndSettle();

    final submitFinder = find.byKey(const Key('employee_toggle_submit_button'));
    await tester.ensureVisible(submitFinder);

    final emailField = find.descendant(
      of: find.byKey(const Key('toggle_employee_email_input')),
      matching: find.byType(TextField),
    );
    final passwordField = find.descendant(
      of: find.byKey(const Key('toggle_owner_password_input')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(emailField);
    await tester.enterText(emailField, 'john@company.com');
    await tester.enterText(passwordField, 'secret123');
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmActionDialog), findsOneWidget);
    final confirmBtn = find.descendant(
      of: find.byType(ConfirmActionDialog),
      matching: find.byType(PrimaryButton),
    );
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    // toggleEmployee called with setActive = false
    expect(mockOwner.toggleEmployeeCalled, isTrue);
    expect(mockOwner.lastToggledEmail, 'john@company.com');
    expect(mockOwner.lastSetActive, isFalse);
  });

  testWidgets(
      'Roster is focal with badge icon and freeze form is collapsed by default (audit E23)',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = MockOwnerProviderForEmployeesTest(apiClient);
    mockOwner.mockEmployees = [
      {
        'id': 'emp-101',
        'username': 'driver_john',
        'email': 'john@company.com',
        'is_active': true,
      },
    ];

    await tester
        .pumpWidget(createEmployeeScreenWidget(ownerProvider: mockOwner));
    await tester.pumpAndSettle();

    // Roster focal element has badge icon
    expect(find.byIcon(Icons.badge_outlined), findsOneWidget);

    // Freeze form is collapsed behind expansion tile by default
    final expansionFinder =
        find.byKey(const Key('freeze_worker_expansion_tile'));
    expect(expansionFinder, findsOneWidget);

    // Form submit button is not visible while collapsed
    expect(
        find.byKey(const Key('employee_toggle_submit_button')), findsNothing);

    // Tapping expands the form
    await tester.ensureVisible(expansionFinder);
    await tester.tap(expansionFinder);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('employee_toggle_submit_button')),
        findsOneWidget);
  });
}
