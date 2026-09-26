import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/my_account_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/widgets/themed_empty_state.dart';

class MockAuthProviderForMyAccount extends AuthProvider {
  final UserProfile? mockUser;
  final bool shouldFailUpdate;
  final int updateErrorCode;
  bool updateCalled = false;
  Map<String, dynamic>? lastUpdatePayload;

  MockAuthProviderForMyAccount(
    super.apiClient, {
    this.mockUser,
    this.shouldFailUpdate = false,
    this.updateErrorCode = 400,
  });

  bool emailChangeRequested = false;
  bool emailChangeConfirmed = false;
  String? requestedNewEmail;
  String? confirmedOtp;

  @override
  Future<String?> requestEmailChange(String newEmail) async {
    emailChangeRequested = true;
    requestedNewEmail = newEmail;
    if (shouldFailUpdate) {
      throw ApiClientException('Email conflict', statusCode: 409);
    }
    return '123456';
  }

  @override
  Future<bool> confirmEmailChange(String otp) async {
    emailChangeConfirmed = true;
    confirmedOtp = otp;
    if (shouldFailUpdate) {
      throw ApiClientException('Invalid OTP', statusCode: 401);
    }
    return true;
  }

  @override
  UserProfile? get user =>
      mockUser ??
      UserProfile(
        id: 'user-my-account-1',
        email: 'customer@example.com',
        username: 'john_doe',
        phone: '+201012345678',
        frequentAddresses: ['Home: 123 Nile St', 'Work: 456 Main St'],
        role: 'user',
      );

  @override
  String? get token => 'mock-user-token';

  // Audit S4: controllable initial-load failure with a stored provider error,
  // mirroring the real fetchUserProfile contract (stores _error on failure).
  int fetchCalls = 0;
  bool failFetch = false;
  String fetchErrorMessage = 'Profile sync failed';
  String? mockStoredError;

  @override
  String? get error => mockStoredError;

  @override
  Future<void> fetchUserProfile() async {
    fetchCalls++;
    mockStoredError = failFetch ? fetchErrorMessage : null;
  }

  @override
  Future<bool> updateOwnProfile({
    String? username,
    String? phone,
    List<String>? frequentAddresses,
    bool? twoFactorEnabled,
    String? password,
  }) async {
    updateCalled = true;
    lastUpdatePayload = {
      'username': username,
      'phone': phone,
      'frequent_addresses': frequentAddresses,
      if (twoFactorEnabled != null) 'two_factor_enabled': twoFactorEnabled,
      if (password != null) 'password': password,
    };

    if (shouldFailUpdate) {
      if (updateErrorCode == 403) {
        throw ApiClientException(
          "access denied: cannot update another user's profile",
          statusCode: 403,
        );
      }
      throw ApiClientException('Request failed', statusCode: updateErrorCode);
    }
    return true;
  }
}

Widget createMyAccountApp({
  UserProfile? mockUser,
  bool shouldFailUpdate = false,
  int updateErrorCode = 400,
  Widget? homeScreen,
}) {
  final apiClient = ApiClient();
  final mockAuth = MockAuthProviderForMyAccount(
    apiClient,
    mockUser: mockUser,
    shouldFailUpdate: shouldFailUpdate,
    updateErrorCode: updateErrorCode,
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      home: homeScreen ?? const MyAccountScreen(),
    ),
  );
}

void main() {
  testWidgets('Pre-populates form with user profile and keeps email read-only',
      (WidgetTester tester) async {
    await tester.pumpWidget(createMyAccountApp());
    await tester.pumpAndSettle();

    expect(find.text('My Account'), findsOneWidget);
    expect(find.text('customer@example.com'), findsOneWidget);
    expect(find.text('john_doe'), findsOneWidget);
    expect(find.text('+201012345678'), findsAtLeastNWidgets(1));
    expect(find.text('Home: 123 Nile St'), findsOneWidget);
    expect(find.text('Work: 456 Main St'), findsOneWidget);

    // Confirm email field is disabled / non-editable
    final emailField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('my_account_email_field')),
        matching: find.byType(TextField),
      ),
    );
    expect(emailField.enabled, false);
  });

  testWidgets(
      'Navigates to MyAccountScreen from SettingsScreen for customer role',
      (WidgetTester tester) async {
    await tester
        .pumpWidget(createMyAccountApp(homeScreen: const SettingsScreen()));
    await tester.pumpAndSettle();

    final rowFinder = find.byKey(const Key('my_account_setting_row'));
    expect(rowFinder, findsOneWidget);

    await tester.ensureVisible(rowFinder);
    await tester.tap(rowFinder);
    await tester.pumpAndSettle();

    expect(find.byType(MyAccountScreen), findsOneWidget);
    expect(find.text('Account Details'), findsOneWidget);
  });

  testWidgets('Submits profile update successfully and shows SnackBar',
      (WidgetTester tester) async {
    await tester.pumpWidget(createMyAccountApp());
    await tester.pumpAndSettle();

    final usernameField = find.byKey(const Key('my_account_username_field'));
    await tester.enterText(usernameField, 'john_updated');

    final saveButton = find.byKey(const Key('my_account_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Profile updated successfully'), findsOneWidget);
  });

  testWidgets('Rejects adding 11th frequent address with warning message',
      (WidgetTester tester) async {
    final userWith10Addresses = UserProfile(
      id: 'u-10',
      email: 'max@example.com',
      username: 'max_user',
      phone: '+1234567890',
      frequentAddresses: List.generate(10, (i) => 'Address #${i + 1}'),
      role: 'user',
    );

    await tester.pumpWidget(createMyAccountApp(mockUser: userWith10Addresses));
    await tester.pumpAndSettle();

    expect(find.text('Frequent Addresses (10/10)'), findsOneWidget);

    final newAddrField = find.byKey(const Key('my_account_new_address_field'));
    await tester.ensureVisible(newAddrField);
    await tester.enterText(newAddrField, '11th Overflow Address');

    final addButton = find.byKey(const Key('my_account_add_address_button'));
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    // Audit S9: the cap message renders inline at the field — never in the
    // distant top form banner.
    expect(find.byKey(const Key('my_account_error_banner')), findsNothing);
    expect(find.text('Cannot add more than 10 frequent addresses.'),
        findsOneWidget);
  });

  testWidgets('Handles API 403 IDOR error response with error banner',
      (WidgetTester tester) async {
    await tester.pumpWidget(createMyAccountApp(
      shouldFailUpdate: true,
      updateErrorCode: 403,
    ));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const Key('my_account_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my_account_error_banner')), findsOneWidget);
    expect(find.text(ErrorMessages.forbidden), findsOneWidget);
  });

  testWidgets(
      'Opens EmailChangeDialog and validates invalid email address input',
      (WidgetTester tester) async {
    await tester.pumpWidget(createMyAccountApp());
    await tester.pumpAndSettle();

    final changeEmailButton = find.byKey(const Key('change_email_button'));
    expect(changeEmailButton, findsOneWidget);
    await tester.tap(changeEmailButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new_email_input')), findsOneWidget);
    expect(find.byKey(const Key('send_email_code_button')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('new_email_input')), 'invalidemail');
    await tester.tap(find.byKey(const Key('send_email_code_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email address'), findsOneWidget);
  });

  testWidgets(
      'Opens EmailChangeDialog, sends OTP code to valid email, and confirms email change',
      (WidgetTester tester) async {
    await tester.pumpWidget(createMyAccountApp());
    await tester.pumpAndSettle();

    final changeEmailButton = find.byKey(const Key('change_email_button'));
    expect(changeEmailButton, findsOneWidget);
    await tester.tap(changeEmailButton);
    await tester.pumpAndSettle();

    // 1. Enter valid new email and submit request
    await tester.enterText(
        find.byKey(const Key('new_email_input')), 'new_email@example.com');
    await tester.tap(find.byKey(const Key('send_email_code_button')));
    await tester.pumpAndSettle();

    // 2. Verify transition to Step 2 (Confirm OTP)
    expect(find.byKey(const Key('email_change_otp_input')), findsOneWidget);
    expect(
        find.byKey(const Key('confirm_email_change_button')), findsOneWidget);

    // 3. Confirm OTP and submit
    await tester.enterText(
        find.byKey(const Key('email_change_otp_input')), '123456');
    await tester.tap(find.byKey(const Key('confirm_email_change_button')));
    await tester.pumpAndSettle();

    // 4. Verify success toast and dialog closed
    expect(find.text('Email address updated successfully'), findsOneWidget);
    expect(find.byKey(const Key('new_email_input')), findsNothing);
  });

  testWidgets(
      'Audit S4: failed initial load renders its own banner with reload retry',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockAuth = MockAuthProviderForMyAccount(apiClient)..failFetch = true;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: const MaterialApp(home: MyAccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(mockAuth.fetchCalls, greaterThanOrEqualTo(1));
    // Load-failure banner with the stored provider copy ...
    expect(
        find.byKey(const Key('my_account_load_error_banner')), findsOneWidget);
    expect(find.text('Profile sync failed'), findsOneWidget);
    // ... distinct from the submit-scoped banner, which stays absent.
    expect(find.byKey(const Key('my_account_error_banner')), findsNothing);
    // Stale form still renders underneath the warning (editable but warned).
    expect(find.byKey(const Key('my_account_save_button')), findsOneWidget);
  });

  testWidgets('Audit S4: reload retry re-fetches and clears the banner',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockAuth = MockAuthProviderForMyAccount(apiClient)..failFetch = true;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: const MaterialApp(home: MyAccountScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('my_account_load_error_banner')), findsOneWidget);

    // Backend recovers, then the user retries the LOAD (not a submit).
    mockAuth.failFetch = false;
    final retryButton = find.descendant(
      of: find.byKey(const Key('my_account_load_error_banner')),
      matching: find.byType(TextButton),
    );
    expect(retryButton, findsOneWidget);
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(mockAuth.fetchCalls, equals(2));
    expect(find.byKey(const Key('my_account_load_error_banner')), findsNothing);
  });

  testWidgets(
      'Audit S9: empty Add tap yields an inline field hint, not silence',
      (WidgetTester tester) async {
    await tester.pumpWidget(createMyAccountApp());
    await tester.pumpAndSettle();

    final addButton = find.byKey(const Key('my_account_add_address_button'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    // Inline hint at the field ...
    expect(find.text('Type an address first, then tap ADD.'), findsOneWidget);
    // ... no top-banner error, nothing added.
    expect(find.byKey(const Key('my_account_error_banner')), findsNothing);
    expect(find.text('Home: 123 Nile St'), findsOneWidget);
    expect(find.text('Work: 456 Main St'), findsOneWidget);
  });

  testWidgets(
      'Audit S3: zero addresses render an empty state whose action adds typed input',
      (WidgetTester tester) async {
    final emptyUser = UserProfile(
      id: 'u-empty',
      email: 'empty@example.com',
      username: 'empty_user',
      phone: '+1234567890',
      frequentAddresses: const [],
      role: 'user',
    );

    await tester.pumpWidget(createMyAccountApp(mockUser: emptyUser));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('my_account_no_addresses_state')), findsOneWidget);
    expect(find.text('No saved addresses yet.'), findsOneWidget);
    // Bare italic placeholder text is gone.
    expect(find.byType(ThemedEmptyState), findsOneWidget);

    // Action with typed input adds it directly.
    await tester.enterText(
        find.byKey(const Key('my_account_new_address_field')),
        'Home: 123 Nile St');
    final emptyAction = find.descendant(
      of: find.byKey(const Key('my_account_no_addresses_state')),
      matching: find.text('ADD'),
    );
    await tester.ensureVisible(emptyAction);
    await tester.pumpAndSettle();
    await tester.tap(emptyAction);
    await tester.pumpAndSettle();

    expect(find.text('Home: 123 Nile St'), findsOneWidget);
    expect(
        find.byKey(const Key('my_account_no_addresses_state')), findsNothing);
    // Clearing the field after a successful add must not leave a spurious
    // required-field error behind.
    expect(find.text('Type an address first, then tap ADD.'), findsNothing);
  });

  testWidgets('Audit S8: deleting an address offers Undo that restores it',
      (WidgetTester tester) async {
    await tester.pumpWidget(createMyAccountApp());
    await tester.pumpAndSettle();

    expect(find.text('Home: 123 Nile St'), findsOneWidget);
    expect(find.text('Work: 456 Main St'), findsOneWidget);

    final removeBtn = find.byKey(const Key('my_account_remove_address_0'));
    await tester.ensureVisible(removeBtn);
    await tester.pumpAndSettle();
    await tester.tap(removeBtn);
    await tester.pumpAndSettle();
    expect(find.text('Home: 123 Nile St'), findsNothing);
    expect(find.text('Address removed.'), findsOneWidget);
    expect(find.text('UNDO'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();

    // Restored at its original index (ahead of Work).
    expect(find.text('Home: 123 Nile St'), findsOneWidget);
    final homeY = tester.getCenter(find.text('Home: 123 Nile St')).dy;
    final workY = tester.getCenter(find.text('Work: 456 Main St')).dy;
    expect(homeY, lessThan(workY));
  });
}
