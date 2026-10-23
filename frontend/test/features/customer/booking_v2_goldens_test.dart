import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/booking_page.dart';
import 'package:frontend/features/customer/customer_location.dart';

import 'customer_harness.dart';

// FE-V2-CONSUME goldens: A-Book with the recipient and package filled in,
// scrolled to those sections, 360x800, light, AR-RTL and EN-LTR, Plex font.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/customer/booking_v2_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

Future<void> _type(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.scrollUntilVisible(f, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.enterText(
      find.descendant(of: f, matching: find.byType(TextField)), text);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPlexFont);

  for (final locale in bothLocales) {
    final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
    testWidgets('GOLDEN booking v2 recipient package $dir', (tester) async {
      usePhone(tester);
      final deps = CustomerTestDeps();
      await tester.pumpWidget(customerApp(
        deps,
        CustomerBookingPage(
          service: service(name: _t(locale, 'Nile Express', 'شحن النيل')),
          pickup: PickedPlace(
              latitude: 30.05,
              longitude: 31.24,
              address: _t(locale, '15 Kasr El Nil St', '15 شارع قصر النيل'),
              note: _t(locale, 'Floor 3', 'الدور التالت')),
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find
          .text(_t(locale, 'Choose the drop-off place', 'اختار مكان التسليم')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(FlutterMap), const Offset(-150, 120));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cust_picker_address')),
          _t(locale, '4 Tahrir St, Dokki', '4 شارع التحرير، الدقي'));
      await tester.tap(find.byKey(const Key('cust_picker_confirm')));
      await tester.pumpAndSettle();

      final other = find.text(_t(locale, 'Someone else', 'حد تاني'));
      await tester.scrollUntilVisible(other, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(other);
      await tester.pumpAndSettle();
      await _type(tester, 'cust_book_recipient_name',
          _t(locale, 'Mahmoud Ibrahim', 'محمود إبراهيم'));
      await _type(tester, 'cust_book_recipient_phone', '0123');
      await _type(tester, 'cust_book_recipient_notes',
          _t(locale, 'Call before you arrive', 'كلّمه قبل ما توصل'));
      final small = find.text(_t(locale, 'Small', 'صغيرة'));
      await tester.scrollUntilVisible(small, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(small);
      await tester.pumpAndSettle();
      await _type(tester, 'cust_book_package_notes',
          _t(locale, 'Documents', 'أوراق ومستندات'));
      // Submit once: the invalid phone shows its field error and banner.
      await tester.tap(find.byKey(const Key('cust_book_submit')));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const Key('cust_book_recipient_phone')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(deps.marketplace.bookCalls, isEmpty);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/cust_book_v2_${dir}_360x800.png'),
      );
    });
  }
}
