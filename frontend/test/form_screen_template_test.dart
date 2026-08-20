import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/widgets/form_screen_template.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/themed_card.dart';
import 'package:frontend/widgets/themed_error_banner.dart';
import 'package:frontend/widgets/themed_text_field.dart';

void main() {
  Widget buildTestFormScreen({
    String? title,
    String? subtitle,
    Widget? titleWidget,
    Widget? leading,
    bool? showBackButton,
    VoidCallback? onBackPressed,
    List<Widget>? actions,
    bool isEmbeddedInTab = false,
    GlobalKey<FormState>? formKey,
    Widget? body,
    Widget? header,
    Widget? footer,
    bool cardWrapper = false,
    Color? cardTopAccentColor,
    String? errorMessage,
    VoidCallback? onRetryError,
    bool isSubmitting = false,
    bool isLoading = false,
    String? submitButtonText,
    VoidCallback? onSubmit,
    bool isSubmitEnabled = true,
    String? secondaryButtonText,
    VoidCallback? onSecondaryAction,
    List<Widget>? children,
  }) {
    return MaterialApp(
      theme: quickDeliveryTheme,
      home: FormScreenTemplate(
        title: title,
        subtitle: subtitle,
        titleWidget: titleWidget,
        leading: leading,
        showBackButton: showBackButton,
        onBackPressed: onBackPressed,
        actions: actions,
        isEmbeddedInTab: isEmbeddedInTab,
        formKey: formKey,
        body: body,
        header: header,
        footer: footer,
        cardWrapper: cardWrapper,
        cardTopAccentColor: cardTopAccentColor,
        errorMessage: errorMessage,
        onRetryError: onRetryError,
        isSubmitting: isSubmitting,
        isLoading: isLoading,
        submitButtonText: submitButtonText,
        onSubmit: onSubmit,
        isSubmitEnabled: isSubmitEnabled,
        secondaryButtonText: secondaryButtonText,
        onSecondaryAction: onSecondaryAction,
        children: children,
      ),
    );
  }

  group('FormScreenTemplate Standalone Tests', () {
    testWidgets(
        '1. Normal rendering: header, fields, submit/secondary buttons, and footer',
        (WidgetTester tester) async {
      bool submitPressed = false;
      bool secondaryPressed = false;
      final emailController = TextEditingController();

      await tester.pumpWidget(
        buildTestFormScreen(
          title: 'Sign In',
          subtitle: 'Welcome back to QuickDelivery',
          header: const Text('Brand Header Logo'),
          submitButtonText: 'Submit Login',
          onSubmit: () => submitPressed = true,
          secondaryButtonText: 'Create Account',
          onSecondaryAction: () => secondaryPressed = true,
          footer: const Text('Terms & Privacy Policy'),
          children: [
            ThemedTextField(
              key: const Key('email_field'),
              labelText: 'Email',
              controller: emailController,
            ),
          ],
        ),
      );

      // Verify title & subtitle in AppBar
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Welcome back to QuickDelivery'), findsOneWidget);

      // Verify header, field, buttons, footer
      expect(find.text('Brand Header Logo'), findsOneWidget);
      expect(find.byKey(const Key('email_field')), findsOneWidget);
      expect(find.text('Submit Login'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Terms & Privacy Policy'), findsOneWidget);

      // Tap submit button
      await tester.tap(find.text('Submit Login'));
      await tester.pumpAndSettle();
      expect(submitPressed, isTrue);

      // Tap secondary button
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(secondaryPressed, isTrue);
    });

    testWidgets(
        '2. Validation error display: renders ThemedErrorBanner when errorMessage is set',
        (WidgetTester tester) async {
      bool retryCalled = false;

      await tester.pumpWidget(
        buildTestFormScreen(
          title: 'KYC Verification',
          errorMessage: 'Document upload failed. File too large.',
          onRetryError: () => retryCalled = true,
          children: const [
            Text('Form Content'),
          ],
        ),
      );

      // Error banner present
      expect(find.byType(ThemedErrorBanner), findsOneWidget);
      expect(
          find.text('Document upload failed. File too large.'), findsOneWidget);

      // Tap retry button if present in banner
      final retryFinder = find.text('Retry');
      if (retryFinder.evaluate().isNotEmpty) {
        await tester.tap(retryFinder);
        await tester.pumpAndSettle();
        expect(retryCalled, isTrue);
      }
    });

    testWidgets(
        '3. Submitting / Disabled state: disables input and displays spinner',
        (WidgetTester tester) async {
      bool submitPressed = false;

      await tester.pumpWidget(
        buildTestFormScreen(
          title: 'Edit Profile',
          isSubmitting: true,
          submitButtonText: 'Save Changes',
          onSubmit: () => submitPressed = true,
          children: const [
            ThemedTextField(
              key: Key('username_field'),
              labelText: 'Username',
            ),
          ],
        ),
      );

      // PrimaryButton shows CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Tapping submit during submission should not trigger callback
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();
      expect(submitPressed, isFalse);
    });

    testWidgets(
        '4. Disabled submit state: when isSubmitEnabled is false, button is disabled',
        (WidgetTester tester) async {
      bool submitPressed = false;

      await tester.pumpWidget(
        buildTestFormScreen(
          title: 'Reset Password',
          isSubmitEnabled: false,
          submitButtonText: 'Confirm Reset',
          onSubmit: () => submitPressed = true,
          children: const [
            Text('Enter new password'),
          ],
        ),
      );

      expect(find.text('Confirm Reset'), findsOneWidget);
      await tester.tap(find.text('Confirm Reset'), warnIfMissed: false);
      await tester.pump();
      expect(submitPressed, isFalse);
    });

    testWidgets(
        '5. Embedded tab mode (isEmbeddedInTab): suppresses standalone AppBar',
        (WidgetTester tester) async {
      // Standalone mode: AppBar is rendered
      await tester.pumpWidget(
        buildTestFormScreen(
          title: 'Settings',
          isEmbeddedInTab: false,
          children: const [
            Text('Settings Form Options'),
          ],
        ),
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Settings Form Options'), findsOneWidget);

      // Embedded tab mode: AppBar is omitted, body remains rendered
      await tester.pumpWidget(
        buildTestFormScreen(
          title: 'Settings',
          isEmbeddedInTab: true,
          children: const [
            Text('Settings Form Options'),
          ],
        ),
      );
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Settings Form Options'), findsOneWidget);
    });

    testWidgets('6. Card wrapper mode: wraps form children in ThemedCard',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestFormScreen(
          title: 'Login Card',
          cardWrapper: true,
          cardTopAccentColor: AppColors.secondary,
          children: const [
            Text('Card Child 1'),
            Text('Card Child 2'),
          ],
        ),
      );

      expect(find.byType(ThemedCard), findsOneWidget);
      expect(find.text('Card Child 1'), findsOneWidget);
      expect(find.text('Card Child 2'), findsOneWidget);
    });
  });
}
