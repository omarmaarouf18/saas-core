import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/owner_provider.dart';

import 'owner_payout_test.dart'
    show FakeApiClientForPayout, createWalletTestWidget;

/// PAY-COD-ONLY: the wallet top-up and payout entry points open their
/// dialogs only when `GET /users/platform/config` reports
/// `digital_payments_enabled: true`; otherwise they show "coming soon".
class _ConfigApi extends FakeApiClientForPayout {
  final Object? config; // a Map, or an Exception to throw
  _ConfigApi(this.config);

  @override
  Future<dynamic> get(String path,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (path == '/users/platform/config') {
      if (config is Exception) throw config as Exception;
      return config;
    }
    return super.get(path,
        queryParams: queryParams, headers: headers, isRetry: isRetry);
  }
}

Future<void> _pumpWallet(WidgetTester tester, ApiClient api,
    {Locale locale = const Locale('en')}) async {
  final owner = OwnerProvider(api);
  await owner.fetchDashboardData('mock-owner-token');
  await tester.pumpWidget(createWalletTestWidget(
      apiClient: api, ownerProvider: owner, locale: locale));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

const _comingSoonEn =
    'Coming soon: wallet top-up and payouts are not available yet. Bookings are paid cash on delivery.';

void main() {
  for (final entry in <String, Object?>{
    'flag false': {'digital_payments_enabled': false},
    'flag absent': {'platform_fee_percentage': 0},
    'config fetch fails':
        ApiClientException('Service unavailable', statusCode: 503),
  }.entries) {
    testWidgets('${entry.key}: payout and top-up show coming soon, no dialog',
        (tester) async {
      await _pumpWallet(tester, _ConfigApi(entry.value));

      await _tap(tester, find.byKey(const Key('request_payout_button')));
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const Key('digital_payments_coming_soon')),
          findsOneWidget);
      expect(find.text(_comingSoonEn), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await _tap(tester, find.text('Deposit Funds'));
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const Key('digital_payments_coming_soon')),
          findsOneWidget);
    });
  }

  testWidgets('flag false: coming soon is localized in Arabic', (tester) async {
    await _pumpWallet(tester, _ConfigApi({'digital_payments_enabled': false}),
        locale: const Locale('ar'));
    await _tap(tester, find.byKey(const Key('request_payout_button')));
    expect(
        find.text(
            'قريب: شحن المحفظة وسحب الأرباح مش متاحين لسه. الحجوزات بتتدفع كاش عند الاستلام.'),
        findsOneWidget);
  });

  testWidgets('flag true: payout and top-up open their dialogs as before',
      (tester) async {
    await _pumpWallet(tester, _ConfigApi({'digital_payments_enabled': true}));

    await _tap(tester, find.byKey(const Key('request_payout_button')));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byKey(const Key('digital_payments_coming_soon')), findsNothing);
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pumpAndSettle();

    await _tap(tester, find.text('Deposit Funds'));
    expect(find.byType(Dialog), findsOneWidget);
  });
}
