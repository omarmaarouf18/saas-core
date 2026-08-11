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

  @override
  Future<void> fetchUserProfile() async {}

  @override
  Future<bool> updateOwnProfile({
    String? username,
    String? phone,
    List<String>? frequentAddresses,
  }) async {
    updateCalled = true;
    lastUpdatePayload = {
      'username': username,
      'phone': phone,
      'frequent_addresses': frequentAddresses,
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

    expect(find.byKey(const Key('my_account_error_banner')), findsOneWidget);
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
}
