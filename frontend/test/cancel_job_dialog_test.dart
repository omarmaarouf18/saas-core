import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/widgets/cancel_job_dialog.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';
import 'package:frontend/widgets/themed_error_banner.dart';
import 'package:frontend/widgets/themed_text_field.dart';

Widget createCancelJobTestWidget({
  required Future<void> Function(String reason) onConfirm,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => CancelJobDialog.show(
            context,
            jobId: 'job-12345',
            onConfirm: onConfirm,
          ),
          child: const Text('Open Cancel Dialog'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('(a) CancelJobDialog renders ThemedTextField and buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(createCancelJobTestWidget(
      onConfirm: (reason) async {},
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Cancel Dialog'));
    await tester.pumpAndSettle();

    expect(find.textContaining('job-12345'), findsOneWidget);
    expect(find.byType(ThemedTextField), findsOneWidget);
    expect(find.byType(SecondaryButton), findsOneWidget);
    expect(find.byType(PrimaryButton), findsOneWidget);

    // Initial state: reason is empty, PrimaryButton is disabled
    final primaryBtn = tester.widget<PrimaryButton>(
      find.byKey(const Key('confirm_cancel_button')),
    );
    expect(primaryBtn.onPressed, isNull);
  });

  testWidgets('(b) Entering reason enables confirm and calls onConfirm',
      (WidgetTester tester) async {
    String? capturedReason;
    await tester.pumpWidget(createCancelJobTestWidget(
      onConfirm: (reason) async {
        capturedReason = reason;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Cancel Dialog'));
    await tester.pumpAndSettle();

    // Enter a cancellation reason
    await tester.enterText(
      find.byKey(const Key('cancel_reason_input')),
      'Customer requested delay',
    );
    await tester.pumpAndSettle();

    // Confirm button is now enabled
    await tester.tap(find.byKey(const Key('confirm_cancel_button')));
    await tester.pumpAndSettle();

    expect(capturedReason, 'Customer requested delay');
  });

  testWidgets('(c) Failure during confirm displays ThemedErrorBanner',
      (WidgetTester tester) async {
    await tester.pumpWidget(createCancelJobTestWidget(
      onConfirm: (reason) async {
        throw Exception('Network error during cancellation');
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Cancel Dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('cancel_reason_input')),
      'Wrong address',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ThemedErrorBanner), findsOneWidget);
  });
}
