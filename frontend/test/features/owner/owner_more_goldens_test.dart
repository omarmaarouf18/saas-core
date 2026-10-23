import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/activity_log_page.dart';
import 'package:frontend/features/owner/fleet_map_page.dart';
import 'package:frontend/features/owner/owner_shell.dart';
import 'package:frontend/features/owner/service_setup_page.dart';
import 'package:frontend/features/owner/plan_page.dart';
import 'package:frontend/features/owner/wallet_page.dart';
import 'package:frontend/models/payout_request.dart';

import 'owner_harness.dart';

// Golden snapshots of the FE-OWNER-2 / FE-OWNER-2b owner pages at 360x800,
// light, AR-RTL and EN-LTR, Plex font: account tab, wallet, plan, service
// setup, team map and activity log.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/owner/owner_more_goldens_test.dart

typedef _Setup = void Function(OwnerTestDeps deps, Locale l);
typedef _Act = Future<void> Function(WidgetTester tester);

Future<void> _tapAccount(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byKey(const Key('owner_shell_nav')),
      matching: find.byIcon(Icons.person_outline)));
  await tester.pumpAndSettle();
}

void _owner(OwnerTestDeps deps, Locale l) {
  deps.auth.user = deps.auth.user!.copyWith(
      kycStatus: 'pending_super_admin_approval',
      username: l.languageCode == 'ar' ? 'نايل إكسبريس' : 'Nile Express');
}

/// Pages that open inside the shell (it builds its own controller).
final Map<String, (_Setup, _Act)> _shellPages = {
  'account': (_owner, _tapAccount),
};

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

void _money(OwnerTestDeps deps, Locale l, {String tier = 'paid'}) {
  deps.owner.nextWallet =
      (total: 1250, escrow: 150, withdrawable: 1100, tier: tier);
  deps.owner.nextExpiresAt = DateTime(2026, 11, 30);
  final at = ownerNow.subtract(const Duration(hours: 3)).toUtc();
  deps.owner.nextLedger = [
    {
      'id': 'l1',
      'type': 'escrow_release',
      'amount': 120,
      'balance_before': 980,
      'balance_after': 1100,
      'job_id': 'a1b2c3d4e5f6',
      'timestamp': at.toIso8601String(),
    },
    {
      'id': 'l2',
      'type': 'escrow_lock',
      'amount': 85,
      'balance_before': 1065,
      'balance_after': 980,
      'job_id': 'b2c3d4e5f6a1',
      'timestamp': at.subtract(const Duration(hours: 5)).toIso8601String(),
    },
  ];
  PayoutRequest p(String id, String status, double amount,
          {String? reason, int days = 2}) =>
      PayoutRequest(
        id: id,
        tenantId: 'owner-1',
        amount: amount,
        status: status,
        payoutMethod: 'instapay',
        rejectionReason: reason,
        createdAt: ownerNow.subtract(Duration(days: days)),
        updatedAt: ownerNow.subtract(Duration(days: days)),
      );
  deps.owner.nextPayouts = [
    p('p1', 'paid', 500),
    p('p2', 'rejected', 90,
        days: 9, reason: _t(l, 'Account name mismatch', 'اسم الحساب مش مطابق')),
  ];
}

void _service(OwnerTestDeps deps, Locale l) {
  deps.owner.nextServices = [
    {
      'id': 'svc-1',
      'tenant_id': 'owner-1',
      'name': _t(l, 'Nile Express', 'نايل إكسبريس'),
      'category': 'delivery',
      'address':
          _t(l, '12 Talaat Harb St, Downtown', '12 شارع طلعت حرب، وسط البلد'),
      'coverage_radius_km': 8,
      'tenant_base_price': 20,
      'tenant_price_per_km': 4.5,
      'latitude': 30.0444,
      'longitude': 31.2357,
      'schedule_mode': 'same_daily',
      'open_time': '09:00',
      'close_time': '23:00',
    }
  ];
}

void _fleet(OwnerTestDeps deps, Locale l) {
  deps.owner.nextEmployees = [
    staff('emp-1', _t(l, 'Karim', 'كريم')),
    staff('emp-2', _t(l, 'Sara', 'سارة')),
  ];
  deps.owner.nextJobs = [ownerJob(id: 'b7c1d2e3f4a5', employeeId: 'emp-1')];
  deps.map.nextMarkers = [
    courierAt('emp-1', jobId: 'b7c1d2e3f4a5'),
    courierAt('emp-2', lat: 30.06, lon: 31.25),
  ];
  // The live socket is down: the reconnect banner shows.
  deps.map.isConnected = false;
}

void _log(OwnerTestDeps deps, Locale l) {
  deps.owner.nextEmployees = [staff('emp-1', _t(l, 'Karim', 'كريم'))];
  String ago(Duration d) => ownerNow.subtract(d).toUtc().toIso8601String();
  deps.owner.nextAudit = [
    {
      'id': 'a1',
      'action': 'Arrived at Pickup',
      'employee_id': 'emp-1',
      'timestamp': ago(const Duration(minutes: 10)),
    },
    {
      'id': 'a2',
      'action': 'KYC_REVIEWED',
      'employee_id': 'owner-1',
      'timestamp': ago(const Duration(days: 3)),
    },
  ];
  deps.owner.nextLedger = [
    {
      'id': 'l1',
      'type': 'escrow_lock',
      'amount': 120,
      'balance_before': 500,
      'balance_after': 380,
      'job_id': 'b7c1d2e3f4a5',
      'timestamp': ago(const Duration(hours: 2)),
    },
    {
      'id': 'l2',
      'type': 'payout',
      'amount': 120,
      'job_id': 'b7c1d2e3f4a5',
      'timestamp': ago(const Duration(days: 2)),
    },
  ];
}

/// Pushed pages, pumped with the deps' controller.
final Map<String, (Widget Function(), _Setup)> _pages = {
  'service': (() => const OwnerServicePage(), _service),
  'fleet_reconnecting': (() => const OwnerFleetMapPage(), _fleet),
  'activity': (() => const OwnerActivityPage(), _log),
  'money': (() => const OwnerActivityPage(initialTab: ActivityTab.money), _log),
  'wallet': (() => const OwnerWalletPage(), _money),
  'plan_paid': (() => const OwnerPlanPage(), _money),
  'plan_free': (
    () => const OwnerPlanPage(),
    (d, l) => _money(d, l, tier: 'free')
  ),
  'plan_review': (
    () => const OwnerPlanPage(),
    (d, l) => _money(d, l, tier: 'pending_payment')
  ),
};

void main() {
  setUpAll(loadPlexFont);

  for (final locale in bothLocales) {
    final dir = locale.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr';
    testWidgets('GOLDEN owner service_errors $dir', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      await pumpOwner(tester, deps, const OwnerServicePage(),
          locale: locale, refresh: false);
      await tester.enterText(find.byKey(const Key('own_service_address')), 'a');
      await tester.tap(find.byKey(const Key('own_service_save')));
      await tester.pumpAndSettle();
      // Back to the top: the first fields with their errors.
      await tester.drag(
          find.byKey(const Key('own_service_form')), const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/own_service_errors_${dir}_360x800.png'),
      );
    });
  }

  _pages.forEach((name, entry) {
    for (final locale in bothLocales) {
      final dir = locale.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN owner $name $dir', (tester) async {
        usePhone(tester);
        final deps = OwnerTestDeps();
        entry.$2(deps, locale);
        await pumpOwner(tester, deps, entry.$1(),
            locale: locale, refresh: false);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/own_${name}_${dir}_360x800.png'),
        );
      });
    }
  });

  _shellPages.forEach((name, entry) {
    for (final locale in bothLocales) {
      final dir = locale.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN owner $name $dir', (tester) async {
        usePhone(tester);
        final deps = OwnerTestDeps();
        entry.$1(deps, locale);
        await tester.pumpWidget(ownerApp(deps, OwnerShell(now: () => ownerNow),
            locale: locale, withData: false));
        await tester.pumpAndSettle();
        await entry.$2(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/own_${name}_${dir}_360x800.png'),
        );
      });
    }
  });
}
