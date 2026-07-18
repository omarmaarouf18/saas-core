import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/main.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/screens/otp_screen.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(apiClient)),
          ChangeNotifierProvider(create: (_) => OwnerProvider(apiClient)),
          ChangeNotifierProvider(
              create: (_) => EmployeeJobsProvider(apiClient)),
        ],
        child: const MyApp(),
      ),
    );

    // Verify that the login screen elements render correctly.
    expect(find.text('Quick Delivery'), findsOneWidget);
    expect(find.text('Log in to manage your services'), findsOneWidget);
  });

  testWidgets('OtpScreen OTP length regression guard',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = AuthProvider(apiClient);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(
          home: OtpScreen(email: 'test@example.com'),
        ),
      ),
    );

    // 1. Assert the TextFormField's maxLength property is exactly 6
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);

    final textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.maxLength, 6);

    // 2. Validate the validator function logic
    final textFormFieldFinder = find.byType(TextFormField);
    expect(textFormFieldFinder, findsOneWidget);

    final textFormField = tester.widget<TextFormField>(textFormFieldFinder);
    final validator = textFormField.validator!;

    // Test a 5-digit string -> error message
    expect(validator('12345'), 'OTP must be exactly 6 digits');

    // Test a 4-digit string -> error message
    expect(validator('1234'), 'OTP must be exactly 6 digits');

    // Test a valid 6-digit string -> null (no error)
    expect(validator('123456'), isNull);
  });
}
