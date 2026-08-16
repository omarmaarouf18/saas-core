import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/widgets/email_change_dialog.dart';
import 'package:frontend/widgets/primary_button.dart';

class MockAuthProviderForDialog extends AuthProvider {
  final bool shouldFailRequest;
  final bool shouldFailConfirm;
  final String? customError;
  bool requestCalled = false;
  bool confirmCalled = false;
  String? lastRequestedEmail;
  String? lastConfirmedOtp;

  MockAuthProviderForDialog(
    super.apiClient, {
    this.shouldFailRequest = false,
    this.shouldFailConfirm = false,
    this.customError,
  });

  @override
  String? get error => customError;

  @override
  UserProfile? get user => UserProfile(
        id: 'user-1',
        email: 'original@example.com',
        username: 'test_user',
        role: 'user',
      );

  @override
  String? get token => 'mock-token';

  @override
  Future<String?> requestEmailChange(String newEmail) async {
    requestCalled = true;
    lastRequestedEmail = newEmail;
    if (shouldFailRequest) {
      throw ApiClientException('Email already in use', statusCode: 409);
    }
    return '654321';
  }

  @override
  Future<bool> confirmEmailChange(String otp) async {
    confirmCalled = true;
    lastConfirmedOtp = otp;
    if (shouldFailConfirm) {
      throw ApiClientException('Invalid OTP code', statusCode: 401);
    }
    return true;
  }
}

Widget createDialogTestApp({
  required AuthProvider authProvider,
}) {
  return MultiProvider(
    providers: [
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
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open_dialog_button'),
              onPressed: () => EmailChangeDialog.show(context),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late ApiClient apiClient;

  setUp(() {
    apiClient = ApiClient();
  });

  testWidgets('EmailChangeDialog renders Step 1 in isolation with close button',
      (WidgetTester tester) async {
    final auth = MockAuthProviderForDialog(apiClient);
    await tester.pumpWidget(createDialogTestApp(authProvider: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_dialog_button')));
    await tester.pumpAndSettle();

    expect(find.byType(EmailChangeDialog), findsOneWidget);
    expect(find.text('Change Email'), findsOneWidget);
    expect(find.byKey(const Key('close_email_change_dialog')), findsOneWidget);
    expect(find.byKey(const Key('new_email_input')), findsOneWidget);
    expect(find.byKey(const Key('send_email_code_button')), findsOneWidget);
    expect(find.byType(PrimaryButton), findsOneWidget);

    // Test close button
    await tester.tap(find.byKey(const Key('close_email_change_dialog')));
    await tester.pumpAndSettle();
    expect(find.byType(EmailChangeDialog), findsNothing);
  });

  testWidgets('EmailChangeDialog validates empty and malformed email inputs',
      (WidgetTester tester) async {
    final auth = MockAuthProviderForDialog(apiClient);
    await tester.pumpWidget(createDialogTestApp(authProvider: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_dialog_button')));
    await tester.pumpAndSettle();

    // 1. Submit empty email
    await tester.tap(find.byKey(const Key('send_email_code_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email address'), findsOneWidget);
    expect(auth.requestCalled, isFalse);

    // 2. Submit invalid format
    await tester.enterText(
        find.byKey(const Key('new_email_input')), 'notanemail');
    await tester.tap(find.byKey(const Key('send_email_code_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email address'), findsOneWidget);
    expect(auth.requestCalled, isFalse);
  });

  testWidgets(
      'EmailChangeDialog handles API error on request code with ThemedErrorBanner',
      (WidgetTester tester) async {
    final auth = MockAuthProviderForDialog(apiClient, shouldFailRequest: true);
    await tester.pumpWidget(createDialogTestApp(authProvider: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_dialog_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('new_email_input')), 'taken@example.com');
    await tester.tap(find.byKey(const Key('send_email_code_button')));
    await tester.pumpAndSettle();

    expect(auth.requestCalled, isTrue);
    expect(find.byKey(const Key('email_change_error_banner')), findsOneWidget);
    expect(find.byKey(const Key('new_email_input')), findsOneWidget);
  });

  testWidgets(
      'EmailChangeDialog transitions to Step 2, auto-populates dev OTP, and confirms email change',
      (WidgetTester tester) async {
    final auth = MockAuthProviderForDialog(apiClient);
    await tester.pumpWidget(createDialogTestApp(authProvider: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_dialog_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('new_email_input')), 'brand_new@example.com');
    await tester.tap(find.byKey(const Key('send_email_code_button')));
    await tester.pumpAndSettle();

    // Verify Step 2 UI
    expect(find.text('Verify New Email'), findsOneWidget);
    expect(find.byKey(const Key('dev_otp_banner')), findsOneWidget);
    expect(find.text('Verification code: 654321'), findsOneWidget);
    expect(find.byKey(const Key('email_change_otp_input')), findsOneWidget);
    expect(
        find.byKey(const Key('confirm_email_change_button')), findsOneWidget);

    // Confirm email change
    await tester.tap(find.byKey(const Key('confirm_email_change_button')));
    await tester.pumpAndSettle();

    expect(auth.confirmCalled, isTrue);
    expect(auth.lastConfirmedOtp, '654321');
    expect(find.text('Email address updated successfully'), findsOneWidget);
    expect(find.byType(EmailChangeDialog), findsNothing);
  });

  testWidgets(
      'EmailChangeDialog handles API error on OTP confirmation with ThemedErrorBanner',
      (WidgetTester tester) async {
    final auth = MockAuthProviderForDialog(apiClient, shouldFailConfirm: true);
    await tester.pumpWidget(createDialogTestApp(authProvider: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_dialog_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('new_email_input')), 'brand_new@example.com');
    await tester.tap(find.byKey(const Key('send_email_code_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_email_change_button')));
    await tester.pumpAndSettle();

    expect(auth.confirmCalled, isTrue);
    expect(find.byKey(const Key('email_change_error_banner')), findsOneWidget);
  });

  testWidgets(
      'EmailChangeDialog renders overflow-free on narrow 360x800 mobile viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final auth = MockAuthProviderForDialog(apiClient);
    await tester.pumpWidget(createDialogTestApp(authProvider: auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_dialog_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(EmailChangeDialog), findsOneWidget);

    // Proceed to Step 2
    await tester.enterText(
        find.byKey(const Key('new_email_input')), 'user@test.com');
    await tester.tap(find.byKey(const Key('send_email_code_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Verify New Email'), findsOneWidget);
  });
}
