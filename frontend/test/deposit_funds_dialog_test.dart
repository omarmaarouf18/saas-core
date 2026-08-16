import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/widgets/deposit_funds_dialog.dart';

class MockAuthProviderForDeposit extends AuthProvider {
  MockAuthProviderForDeposit(super.apiClient);

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

class MockOwnerProviderForDepositDialog extends OwnerProvider {
  bool depositCalled = false;
  double? lastDepositedAmount;
  bool shouldThrowOnDeposit = false;

  MockOwnerProviderForDepositDialog(super.apiClient);

  @override
  Future<void> deposit(String token, double amount) async {
    if (shouldThrowOnDeposit) {
      throw Exception('Deposit transaction declined');
    }
    depositCalled = true;
    lastDepositedAmount = amount;
  }
}

Widget buildDepositTestApp({
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
              onPressed: () => DepositFundsDialog.show(ctx),
              child: const Text('Open Deposit Dialog'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('DepositFundsDialog renders fields and buttons',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForDeposit(apiClient);
    final owner = MockOwnerProviderForDepositDialog(apiClient);

    await tester.pumpWidget(buildDepositTestApp(
      ownerProvider: owner,
      authProvider: auth,
    ));
    await tester.tap(find.text('Open Deposit Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Deposit Funds'), findsOneWidget);
    expect(find.byKey(const Key('deposit_amount_field')), findsOneWidget);
    expect(find.byKey(const Key('deposit_confirm_button')), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('DepositFundsDialog validates empty amount',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForDeposit(apiClient);
    final owner = MockOwnerProviderForDepositDialog(apiClient);

    await tester.pumpWidget(buildDepositTestApp(
      ownerProvider: owner,
      authProvider: auth,
    ));
    await tester.tap(find.text('Open Deposit Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deposit_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.text('Amount is required'), findsOneWidget);
  });

  testWidgets('DepositFundsDialog validates zero or negative amount',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForDeposit(apiClient);
    final owner = MockOwnerProviderForDepositDialog(apiClient);

    await tester.pumpWidget(buildDepositTestApp(
      ownerProvider: owner,
      authProvider: auth,
    ));
    await tester.tap(find.text('Open Deposit Dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('deposit_amount_field')), '0');
    await tester.tap(find.byKey(const Key('deposit_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid positive number'), findsOneWidget);
  });

  testWidgets('DepositFundsDialog validates excessive amount (> 1M)',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForDeposit(apiClient);
    final owner = MockOwnerProviderForDepositDialog(apiClient);

    await tester.pumpWidget(buildDepositTestApp(
      ownerProvider: owner,
      authProvider: auth,
    ));
    await tester.tap(find.text('Open Deposit Dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('deposit_amount_field')), '1000001');
    await tester.tap(find.byKey(const Key('deposit_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.text('Maximum single deposit is 1,000,000 credits'),
        findsOneWidget);
  });

  testWidgets('DepositFundsDialog successfully submits deposit and pops dialog',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForDeposit(apiClient);
    final owner = MockOwnerProviderForDepositDialog(apiClient);

    await tester.pumpWidget(buildDepositTestApp(
      ownerProvider: owner,
      authProvider: auth,
    ));
    await tester.tap(find.text('Open Deposit Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deposit_amount_field')));
    await tester.enterText(
        find.byKey(const Key('deposit_amount_field')), '250.00');
    await tester.tap(find.byKey(const Key('deposit_confirm_button')));
    await tester.pumpAndSettle();

    expect(owner.depositCalled, isTrue);
    expect(owner.lastDepositedAmount, 250.00);
    expect(find.text('Successfully deposited 250.00 credits.'), findsOneWidget);
    expect(find.byType(DepositFundsDialog), findsNothing);
  });

  testWidgets('DepositFundsDialog renders error banner on failure',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForDeposit(apiClient);
    final owner = MockOwnerProviderForDepositDialog(apiClient);
    owner.shouldThrowOnDeposit = true;

    await tester.pumpWidget(buildDepositTestApp(
      ownerProvider: owner,
      authProvider: auth,
    ));
    await tester.tap(find.text('Open Deposit Dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deposit_amount_field')));
    await tester.enterText(
        find.byKey(const Key('deposit_amount_field')), '100.00');
    await tester.tap(find.byKey(const Key('deposit_confirm_button')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('deposit_dialog_error_banner')), findsOneWidget);
    expect(find.byType(DepositFundsDialog), findsOneWidget);
  });

  testWidgets(
      'DepositFundsDialog renders without overflow on 360dp mobile viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final apiClient = ApiClient();
    final auth = MockAuthProviderForDeposit(apiClient);
    final owner = MockOwnerProviderForDepositDialog(apiClient);

    await tester.pumpWidget(buildDepositTestApp(
      ownerProvider: owner,
      authProvider: auth,
    ));
    await tester.tap(find.text('Open Deposit Dialog'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DepositFundsDialog), findsOneWidget);
  });
}
