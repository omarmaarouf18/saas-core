import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/employee_screen.dart';
import 'package:frontend/widgets/status_badge.dart';

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

  @override
  Future<void> fetchAuditLog({
    required String tenantId,
    required String requesterToken,
  }) async {}
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
}
