import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/payout_request.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/widgets/payout_request_dialog.dart';

class MockAuthProviderForPayout extends AuthProvider {
  MockAuthProviderForPayout(super.apiClient);

  @override
  String? get token => 'mock-owner-token';

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-test-1',
        email: 'owner@example.com',
        username: 'test_owner',
        role: 'owner',
        kycStatus: 'approved',
      );
}

class MockOwnerProviderForPayoutDialog extends OwnerProvider {
  double mockWithdrawable = 500.0;
  bool requestPayoutCalled = false;
  double? lastRequestedAmount;
  String? lastRequestedMethod;
  String? lastRequestedAccountDetails;
  bool shouldThrowOnRequest = false;

  MockOwnerProviderForPayoutDialog(super.apiClient);

  @override
  double get withdrawableBalance => mockWithdrawable;

  @override
  Future<PayoutRequest> requestPayout({
    required double amount,
    required String payoutMethod,
    required String accountDetails,
  }) async {
    if (shouldThrowOnRequest) {
      throw Exception('Payout processing failed on gateway');
    }
    requestPayoutCalled = true;
    lastRequestedAmount = amount;
    lastRequestedMethod = payoutMethod;
    lastRequestedAccountDetails = accountDetails;
    return PayoutRequest(
      id: 'payout-test-1',
      tenantId: 'owner-test-1',
      amount: amount,
      status: 'requested',
      payoutMethod: payoutMethod,
      accountDetails: accountDetails,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> fetchDashboardData(String token) async {}
}

Widget buildTestApp({
  required OwnerProvider ownerProvider,
  required AuthProvider authProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
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
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => PayoutRequestDialog.show(ctx),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('PayoutRequestDialog renders Step 1 form fields initially',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForPayout(apiClient);
    final owner = MockOwnerProviderForPayoutDialog(apiClient);

    await tester
        .pumpWidget(buildTestApp(ownerProvider: owner, authProvider: auth));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Request Payout'), findsOneWidget);
    expect(find.byKey(const Key('payout_amount_field')), findsOneWidget);
    expect(find.byKey(const Key('payout_method_dropdown')), findsOneWidget);
    expect(
        find.byKey(const Key('payout_account_details_field')), findsOneWidget);
    expect(find.byKey(const Key('payout_submit_button')), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('PayoutRequestDialog close button exposes tooltip semantics',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForPayout(apiClient);
    final owner = MockOwnerProviderForPayoutDialog(apiClient);

    await tester
        .pumpWidget(buildTestApp(ownerProvider: owner, authProvider: auth));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    final button = tester.widget<IconButton>(
      find.byKey(const Key('close_payout_dialog')),
    );
    expect(button.tooltip, isNotNull);
    expect(button.tooltip, isNotEmpty);
  });

  testWidgets('PayoutRequestDialog validates empty fields',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForPayout(apiClient);
    final owner = MockOwnerProviderForPayoutDialog(apiClient);

    await tester
        .pumpWidget(buildTestApp(ownerProvider: owner, authProvider: auth));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('payout_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid amount greater than 0.'),
        findsOneWidget);
    expect(find.text('Account details are required.'), findsOneWidget);
  });

  testWidgets('PayoutRequestDialog validates amount exceeding balance',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForPayout(apiClient);
    final owner = MockOwnerProviderForPayoutDialog(apiClient);
    owner.mockWithdrawable = 200.0;

    await tester
        .pumpWidget(buildTestApp(ownerProvider: owner, authProvider: auth));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('payout_amount_field')), '350.00');
    await tester.enterText(
        find.byKey(const Key('payout_account_details_field')), 'EG1234567890');

    await tester.tap(find.byKey(const Key('payout_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Amount exceeds current withdrawable balance.'),
        findsOneWidget);
  });

  testWidgets(
      'PayoutRequestDialog transitions to Step 2 confirmation and back to Step 1',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForPayout(apiClient);
    final owner = MockOwnerProviderForPayoutDialog(apiClient);

    await tester
        .pumpWidget(buildTestApp(ownerProvider: owner, authProvider: auth));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    final amountField = find.descendant(
      of: find.byKey(const Key('payout_amount_field')),
      matching: find.byType(TextField),
    );
    final detailsField = find.descendant(
      of: find.byKey(const Key('payout_account_details_field')),
      matching: find.byType(TextField),
    );

    await tester.enterText(amountField, '150.00');
    await tester.enterText(detailsField, 'IBAN-EG-998877');

    await tester.tap(find.byKey(const Key('payout_submit_button')));
    await tester.pumpAndSettle();

    // Step 2 confirmation
    expect(find.text('Confirm Payout Request'), findsOneWidget);
    expect(find.text('Confirm Payout'), findsOneWidget);
    expect(find.text('Account: IBAN-EG-998877'), findsOneWidget);

    // Tap Back
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Returned to Step 1
    expect(find.text('Request Payout'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('PayoutRequestDialog handles submission and success toast',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForPayout(apiClient);
    final owner = MockOwnerProviderForPayoutDialog(apiClient);

    await tester
        .pumpWidget(buildTestApp(ownerProvider: owner, authProvider: auth));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    final amountField = find.descendant(
      of: find.byKey(const Key('payout_amount_field')),
      matching: find.byType(TextField),
    );
    final detailsField = find.descendant(
      of: find.byKey(const Key('payout_account_details_field')),
      matching: find.byType(TextField),
    );

    await tester.enterText(amountField, '100.00');
    await tester.enterText(detailsField, 'ACC-12345');

    // Continue to step 2
    await tester.tap(find.byKey(const Key('payout_submit_button')));
    await tester.pumpAndSettle();

    // Confirm
    await tester.tap(find.byKey(const Key('payout_confirm_button')));
    await tester.pumpAndSettle();

    expect(owner.requestPayoutCalled, isTrue);
    expect(owner.lastRequestedAmount, 100.0);
    expect(owner.lastRequestedAccountDetails, 'ACC-12345');
    expect(find.byKey(const Key('payout_success_snackbar')), findsOneWidget);
  });

  testWidgets('PayoutRequestDialog displays error banner on failure',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForPayout(apiClient);
    final owner = MockOwnerProviderForPayoutDialog(apiClient);
    owner.shouldThrowOnRequest = true;

    await tester
        .pumpWidget(buildTestApp(ownerProvider: owner, authProvider: auth));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    final amountField = find.descendant(
      of: find.byKey(const Key('payout_amount_field')),
      matching: find.byType(TextField),
    );
    final detailsField = find.descendant(
      of: find.byKey(const Key('payout_account_details_field')),
      matching: find.byType(TextField),
    );

    await tester.enterText(amountField, '50.00');
    await tester.enterText(detailsField, 'ACC-ERROR');

    await tester.tap(find.byKey(const Key('payout_submit_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('payout_confirm_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payout_dialog_error_banner')), findsOneWidget);
  });

  testWidgets(
      'PayoutRequestDialog adapts without overflow on 360dp mobile viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final apiClient = ApiClient();
    final auth = MockAuthProviderForPayout(apiClient);
    final owner = MockOwnerProviderForPayoutDialog(apiClient);

    await tester
        .pumpWidget(buildTestApp(ownerProvider: owner, authProvider: auth));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PayoutRequestDialog), findsOneWidget);
  });
}
