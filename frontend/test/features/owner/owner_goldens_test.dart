import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/employee_page.dart';
import 'package:frontend/features/owner/order_detail_page.dart';
import 'package:frontend/features/owner/orders_page.dart';
import 'package:frontend/features/owner/owner_shell.dart';
import 'package:frontend/features/owner/recon_page.dart';
import 'package:frontend/features/owner/team_page.dart';
import 'package:frontend/features/owner/today_page.dart';

import 'owner_harness.dart';

// Golden snapshots of the FE-OWNER-1 owner pages, 360x800, light, AR-RTL
// and EN-LTR (plus the shell and the order detail in dark, EN-LTR), with
// the bundled Plex font. Regenerate with:
//   flutter test --update-goldens test/features/owner/owner_goldens_test.dart

typedef _Setup = void Function(OwnerTestDeps deps, Locale locale);
typedef _Act = Future<void> Function(WidgetTester tester);

List<dynamic> _team(Locale l) => l.languageCode == 'ar'
    ? [
        staff('emp-1', 'كريم', email: 'karim@example.com'),
        staff('emp-2', 'سارة', email: 'sara@example.com'),
        staff('emp-3', 'محمود', active: false, email: 'mahmoud@example.com'),
      ]
    : [
        staff('emp-1', 'Karim'),
        staff('emp-2', 'Sara'),
        staff('emp-3', 'Mahmoud', active: false),
      ];

String _t(Locale l, String en, String ar) => l.languageCode == 'ar' ? ar : en;

void _orderWithRequest(OwnerTestDeps deps, Locale l) {
  deps.owner.nextEmployees = _team(l);
  deps.owner.nextJobs = [
    ownerJob(
      pickupNote: _t(l, 'Beside the kiosk', 'جنب الكشك'),
      dropNote: _t(l, 'Zamalek, 26th of July St', 'الزمالك، شارع 26 يوليو'),
      requestStatus: 'pending',
      requestReason: _t(l, 'My bike broke down', 'الموتوسيكل عطل مني'),
      requestedAt: ownerNow.subtract(const Duration(minutes: 12)),
    ),
  ];
}

void _orderCompletedReview(OwnerTestDeps deps, Locale l) {
  deps.owner.nextEmployees = _team(l);
  deps.owner.nextJobs = [
    ownerJob(
      status: 'completed',
      pickupNote: _t(l, 'Beside the kiosk', 'جنب الكشك'),
      dropNote: _t(l, 'Zamalek, 26th of July St', 'الزمالك، شارع 26 يوليو'),
    ),
  ];
  deps.owner.nextJobJson = {
    'a1b2c3d4e5f6': {
      'actual_cash_amount': 42,
      'distance_review': {'actual_km': 1.2, 'booked_km': 6},
    },
  };
}

void _ordersList(OwnerTestDeps deps, Locale l) {
  deps.owner.nextEmployees = _team(l);
  final drop = _t(l, 'Zamalek, 26th of July St', 'الزمالك، شارع 26 يوليو');
  deps.owner.nextJobs = [
    ownerJob(id: 'b7c1d2e3f4a5', dropNote: drop, requestStatus: 'pending'),
    ownerJob(id: 'c8d2e3f4a5b6', employeeId: 'emp-2', dropNote: drop),
    ownerJob(
        id: 'd9e3f4a5b6c7',
        status: 'awaiting_price_response',
        proposed: 55,
        price: 42),
    ownerJob(
        id: 'e0f4a5b6c7d8',
        status: 'pending_dispatch',
        employeeId: null,
        offeredTo: 'emp-2'),
    ownerJob(
        id: 'f1a5b6c7d8e9',
        status: 'pending',
        employeeId: null,
        dropNote: _t(l, 'Maadi, Road 9', 'المعادي، شارع 9')),
  ];
}

void _recon(OwnerTestDeps deps, Locale l) {
  deps.owner.nextEmployees = _team(l);
  deps.recon.nextQueue = [
    reconJob(
        note: _t(l, 'Tracked 1.2 km of the 6.0 km booked.',
            'اتسجّل 1.2 كم من 6.0 كم في الحجز.')),
  ];
}

void _reconEmpty(OwnerTestDeps deps, Locale l) {}

void _teamData(OwnerTestDeps deps, Locale l) {
  deps.owner.nextEmployees = _team(l);
  deps.owner.nextJobs = [
    ownerJob(id: 'b7c1d2e3f4a5', employeeId: 'emp-1'),
    ownerJob(id: 'c8d2e3f4a5b6', employeeId: 'emp-1', status: 'completed'),
    ownerJob(id: 'd9e3f4a5b6c7', employeeId: 'emp-2', status: 'completed'),
  ];
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void _todayData(OwnerTestDeps deps, Locale l) {
  final today = DateTime(2026, 10, 19, 9);
  deps.owner.nextEmployees = _team(l);
  deps.owner.nextJobs = [
    ownerJob(
      id: 'b7c1d2e3f4a5',
      createdAt: today,
      requestStatus: 'pending',
      requestReason: _t(l, 'Flat tyre', 'الكاوتش نام'),
      requestedAt: ownerNow.subtract(const Duration(minutes: 5)),
    ),
    ownerJob(id: 'c8d2e3f4a5b6', status: 'completed', createdAt: today),
    ownerJob(
        id: 'd9e3f4a5b6c7',
        status: 'completed',
        employeeId: 'emp-2',
        createdAt: today),
    ownerJob(
        id: 'e0f4a5b6c7d8',
        status: 'escrow_reconciliation_required',
        createdAt: today),
  ];
  deps.owner.nextJobJson = {
    'c8d2e3f4a5b6': {'actual_cash_amount': 42},
    'd9e3f4a5b6c7': {'actual_cash_amount': 85},
  };
}

void _todayKybPending(OwnerTestDeps deps, Locale l) {
  _todayData(deps, l);
  deps.auth.user =
      deps.auth.user!.copyWith(kycStatus: 'pending_super_admin_approval');
}

Widget _today() =>
    Scaffold(body: OwnerTodayPage(onShowTeam: () {}, onShowOrders: () {}));

final Map<String, (Widget Function(), _Setup)> _pages = {
  'today': (_today, _todayData),
  'today_kyb_pending': (_today, _todayKybPending),
  'team': (() => const Scaffold(body: OwnerTeamPage()), _teamData),
  'employee': (() => const OwnerEmployeePage(employeeId: 'emp-1'), _teamData),
  'employee_frozen': (
    () => const OwnerEmployeePage(employeeId: 'emp-3'),
    _teamData
  ),
  'recon': (() => const OwnerReconPage(), _recon),
  'recon_empty': (() => const OwnerReconPage(), _reconEmpty),
  'orders': (() => const Scaffold(body: OwnerOrdersPage()), _ordersList),
  'order': (
    () => const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'),
    _orderWithRequest
  ),
  'order_review': (
    () => const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'),
    _orderCompletedReview
  ),
};

final Map<String, (Widget Function(), _Setup, _Act)> _sheets = {
  'cancel_sheet': (
    () => const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'),
    _orderWithRequest,
    (t) => _tap(t, 'own_order_cancel')
  ),
  'respond_sheet': (
    () => const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'),
    _orderWithRequest,
    (t) => _tap(t, 'own_cancel_request_approve')
  ),
  'add_courier': (
    () => const Scaffold(body: OwnerTeamPage()),
    _teamData,
    (t) => _tap(t, 'own_team_add')
  ),
  'freeze_sheet': (
    () => const OwnerEmployeePage(employeeId: 'emp-2'),
    _teamData,
    (t) => _tap(t, 'own_employee_freeze')
  ),
};

void main() {
  setUpAll(loadPlexFont);

  // The shell itself (Today tab + bottom nav); it builds its own controller.
  for (final locale in bothLocales) {
    final dir = locale.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr';
    testWidgets('GOLDEN owner shell $dir', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      _todayData(deps, locale);
      await tester.pumpWidget(ownerApp(deps, OwnerShell(now: () => ownerNow),
          locale: locale, withData: false));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/own_shell_${dir}_360x800.png'),
      );
    });
  }

  // FE-CLEANUP dark review: the shell and the order detail, dark, EN-LTR.
  testWidgets('GOLDEN owner shell dark en_ltr', (tester) async {
    usePhone(tester);
    final deps = OwnerTestDeps();
    _todayData(deps, const Locale('en'));
    await tester.pumpWidget(ownerApp(deps, OwnerShell(now: () => ownerNow),
        withData: false, themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/own_shell_dark_en_ltr_360x800.png'));
  });

  testWidgets('GOLDEN owner order dark en_ltr', (tester) async {
    usePhone(tester);
    final deps = OwnerTestDeps();
    _orderWithRequest(deps, const Locale('en'));
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'),
        themeMode: ThemeMode.dark);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/own_order_dark_en_ltr_360x800.png'));
  });

  _sheets.forEach((name, entry) {
    for (final locale in bothLocales) {
      final dir = locale.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN owner $name $dir', (tester) async {
        usePhone(tester);
        final deps = OwnerTestDeps();
        entry.$2(deps, locale);
        await pumpOwner(tester, deps, entry.$1(), locale: locale);
        await entry.$3(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/own_${name}_${dir}_360x800.png'),
        );
      });
    }
  });

  _pages.forEach((name, entry) {
    for (final locale in bothLocales) {
      final dir = locale.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN owner $name $dir', (tester) async {
        usePhone(tester);
        final deps = OwnerTestDeps();
        entry.$2(deps, locale);
        await pumpOwner(tester, deps, entry.$1(), locale: locale);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/own_${name}_${dir}_360x800.png'),
        );
      });
    }
  });
}
