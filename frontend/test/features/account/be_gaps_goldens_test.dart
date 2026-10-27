import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/saved_addresses_page.dart';
import 'package:frontend/models/saved_address.dart';

import '../customer/customer_harness.dart' as cust;
import 'account_harness.dart';

// FE-BE-GAPS goldens at 360x800 with the Plex font: light AR-RTL and
// EN-LTR, plus one dark EN-LTR per new screen.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/account/be_gaps_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

List<SavedAddress> _saved(Locale l) => [
      SavedAddress(
        id: 'addr-home',
        label: 'Home',
        address: _t(l, '12 Tahrir St, Dokki', '12 شارع التحرير، الدقي'),
        addressNote:
            _t(l, 'Floor 3, the blue door', 'الدور التالت، الباب الأزرق'),
        latitude: 30.0444,
        longitude: 31.2357,
      ),
      SavedAddress(
        id: 'addr-work',
        label: 'Work',
        address: _t(l, 'Smart Village B7', 'القرية الذكية B7'),
        latitude: 30.075,
        longitude: 31.02,
      ),
      SavedAddress(
        id: 'addr-gym',
        label: _t(l, 'Gym', 'الجيم'),
        address:
            _t(l, '5 Abbas El Akkad, Nasr City', '5 عباس العقاد، مدينة نصر'),
        latitude: 30.06,
        longitude: 31.33,
      ),
    ];

FakeAuthFlow _auth(Locale l) => FakeAuthFlow(
      token: 'jwt',
      user: FakeAuthFlow.customer(
        saved: _saved(l),
        addresses: [
          for (final a in _saved(l)) a.address,
          _t(l, 'Club, Heliopolis', 'النادي، مصر الجديدة'),
        ],
      ),
    );

typedef _Case = Future<void> Function(WidgetTester tester);

Future<void> _none(WidgetTester tester) async {}

final Map<String, _Case> _cases = {
  'addresses_pinned': _none,
  'address_editor': (tester) async {
    await tester.tap(find.text(_isAr(tester) ? 'الجيم' : 'Gym'));
    await tester.pumpAndSettle();
  },
  'address_editor_errors': (tester) async {
    await tester.tap(find.byKey(const Key('addresses_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('address_save')));
    await tester.pumpAndSettle();
  },
};

bool _isAr(WidgetTester tester) =>
    Localizations.localeOf(tester.element(find.byType(Scaffold).first))
        .languageCode ==
    'ar';

const Set<String> _dark = {'addresses_pinned', 'address_editor'};

void main() {
  setUpAll(cust.loadPlexFont);

  _cases.forEach((name, setup) {
    final variants = [
      for (final l in bothLocales)
        (l, ThemeMode.light, l == ar ? 'ar_rtl' : 'en_ltr'),
      if (_dark.contains(name)) (en, ThemeMode.dark, 'dark_en_ltr'),
    ];
    for (final (locale, mode, dir) in variants) {
      testWidgets('GOLDEN account $name $dir', (tester) async {
        final deps = AccountTestDeps(auth: _auth(locale));
        await deps.theme.setThemeMode(mode);
        await pumpAccount(tester, deps, const SavedAddressesPage(),
            locale: locale);
        await setup(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/acct_${name}_${dir}_360x800.png'),
        );
      });
    }
  });
}
