import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/chat/chat_page.dart';
import 'package:frontend/features/customer/order/rating_page.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/models/job.dart';

import '../customer_harness.dart';
import 'order_fixtures.dart';
import 'order_harness.dart';

// Golden snapshots of each order detail view at 360x800, light, AR-RTL and
// EN-LTR, with the bundled Plex font (like customer_goldens_test.dart).
// Icons render as test-font boxes; map tiles are blank.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/customer/order/order_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

Job _job(Locale l, String status,
        {String? employeeId,
        String? offered,
        double? proposed,
        String? proposedBy,
        DateTime? expires,
        String? reason,
        double? agreed,
        double? escrow}) =>
    orderJob(
      status: status,
      employeeId: employeeId,
      offeredEmployeeId: offered,
      pickupNote: _t(l, 'Beside the kiosk', 'جنب الكشك'),
      dropNote: _t(l, 'Zamalek, 26th of July St', 'الزمالك، شارع 26 يوليو'),
      suggested: 42,
      proposed: proposed,
      proposedBy: proposedBy,
      proposalExpiresAt: expires,
      cancellationReason: reason,
      agreed: agreed,
      lockedEscrow: escrow,
    );

final Map<String, Job Function(Locale)> _views = {
  'searching': (l) => _job(l, 'pending_dispatch', offered: 'emp-1'),
  'unavailable': (l) => _job(l, 'unavailable'),
  'proposal': (l) => _job(l, 'awaiting_price_response',
      employeeId: 'emp-1',
      proposed: 50,
      proposedBy: 'employee',
      expires: fixedNow.add(const Duration(minutes: 2, seconds: 41))),
  'proposal_counter': (l) => _job(l, 'awaiting_price_response',
      expires: fixedNow.add(const Duration(minutes: 4))),
  'active': (l) => _job(l, 'active', employeeId: 'emp-1', agreed: 45),
  'completed': (l) => _job(l, 'completed', employeeId: 'emp-1', agreed: 45),
  'cancelled': (l) =>
      _job(l, 'cancelled', reason: _t(l, 'Changed my mind', 'غيرت رأيي')),
  'cancelled_expired': (l) =>
      _job(l, 'cancelled', reason: 'price_proposal_expired'),
  'unknown': (l) => _job(l, 'picked_up', employeeId: 'emp-1'),
  'under_review': (l) => _job(l, 'escrow_reconciliation_required',
      employeeId: 'emp-1', escrow: 42),
};

void main() {
  setUpAll(loadPlexFont);

  for (final locale in bothLocales) {
    final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
    testWidgets('GOLDEN order rating $dir', (tester) async {
      usePhone(tester);
      final deps = CustomerTestDeps();
      await tester.pumpWidget(customerApp(
        deps,
        CustomerRatingPage(
          job: _job(locale, 'completed', employeeId: 'emp-1', agreed: 45),
          courierName: _t(locale, 'Karim', 'كريم'),
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ord_rating_${dir}_360x800.png'),
      );
    });
  }

  for (final locale in bothLocales) {
    final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
    testWidgets('GOLDEN order chat $dir', (tester) async {
      usePhone(tester);
      final deps = CustomerTestDeps();
      ChatMessage msg(String id, String sender, String text) => ChatMessage(
            id: id,
            channel: 'job:a1b2c3d4e5f6',
            senderId: sender,
            senderUsername:
                sender == 'user-1' ? 'Mona' : _t(locale, 'Karim', 'كريم'),
            content: text,
            type: 'message',
            createdAt: fixedNow,
          );
      deps.chat.nextHistory = [
        msg('1', 'emp-1', _t(locale, "I'm at the gate.", 'أنا عند البوابة.')),
        msg('2', 'user-1',
            _t(locale, 'Coming down in two minutes.', 'نازل كمان دقيقتين.')),
      ];
      await tester.pumpWidget(customerApp(
        deps,
        CustomerChatPage(
          channel: 'job:a1b2c3d4e5f6',
          title: _t(locale, 'Chat with the courier', 'محادثة المندوب'),
          subtitle: '\u2066#QD-A1B2C3D4\u2069',
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ord_chat_${dir}_360x800.png'),
      );
    });
  }

  _views.forEach((name, build) {
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN order $name $dir', (tester) async {
        final deps = CustomerTestDeps();
        deps.marketplace.services = [
          service(name: _t(locale, 'Nile Express', 'شحن النيل')),
        ];
        deps.map.setCourier(30.055, 31.232);
        await pumpOrder(tester, deps, build(locale),
            locale: locale,
            lookup: FakeCourierLookup({'emp-1': _t(locale, 'Karim', 'كريم')}));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/ord_${name}_${dir}_360x800.png'),
        );
        await unmountOrder(tester, deps);
      });
    }
  });
}
