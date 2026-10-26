import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/owner/service_rules.dart';
import 'package:frontend/features/owner/service_setup_page.dart';

import 'owner_harness.dart';

Map<String, dynamic> storedService({
  String? scheduleMode,
  String? open,
  String? close,
  List<Map<String, dynamic>>? perDay,
}) =>
    {
      'id': 'svc-1',
      'tenant_id': 'owner-1',
      'name': 'Nile Express',
      'category': 'shipping',
      'address': '12 Talaat Harb St',
      'coverage_radius_km': 8,
      'tenant_base_price': 20,
      'tenant_price_per_km': 4.5,
      'latitude': 30.0444,
      'longitude': 31.2357,
      'photo_url': '/data/user/0/app/cache/logo.jpg',
      'working_hours': 'Sat-Thu 9-5',
      if (scheduleMode != null) 'schedule_mode': scheduleMode,
      if (open != null) 'open_time': open,
      if (close != null) 'close_time': close,
      if (perDay != null) 'per_day_schedule': perDay,
    };

void main() {
  group('service rules', () {
    test('parseAmount reads Western and Arabic-Indic digits', () {
      expect(parseAmount('12.5'), 12.5);
      expect(parseAmount('١٢٫٥'), 12.5);
      expect(parseAmount(' 7 '), 7);
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
    });

    test('the old screen rules, every problem at once', () {
      final p = validateServiceForm(
        name: ' ',
        hasPlace: false,
        address: 'ab',
        radius: '0',
        baseFee: '-1',
        perKm: 'x',
        hours: ServiceHours(),
      );
      expect([
        p.name,
        p.place,
        p.address,
        p.radius,
        p.baseFee,
        p.perKm
      ], [
        true,
        true,
        true,
        true,
        true,
        true,
      ]);
      final ok = validateServiceForm(
        name: 'Nile',
        hasPlace: true,
        address: '',
        radius: '5',
        baseFee: '0',
        perKm: '0',
        hours: ServiceHours(),
      );
      expect(ok.any, isFalse);
    });

    test('hours: both times needed, not equal; overnight is fine', () {
      final h = ServiceHours()..start();
      expect(hoursProblems(h), isEmpty);
      h.close = h.open;
      expect(hoursProblems(h), {'same': HoursProblem.sameTime});
      h
        ..open = const TimeOfDay(hour: 18, minute: 0)
        ..close = const TimeOfDay(hour: 2, minute: 0);
      expect(hoursProblems(h), isEmpty);

      h.setMode(ScheduleMode.perDay);
      expect(h.days, hasLength(7));
      h.days.first.close = null;
      h.days[1]
        ..open = const TimeOfDay(hour: 9, minute: 0)
        ..close = const TimeOfDay(hour: 9, minute: 0);
      h.days[2]
        ..off = true
        ..close = null;
      expect(hoursProblems(h), {
        'mon': HoursProblem.missingTime,
        'tue': HoursProblem.sameTime,
      });
    });

    test('schedule fields: untouched sends nothing, cleared sends ""', () {
      final loaded = ServiceHours.fromService(storedService(
          scheduleMode: 'same_daily', open: '09:00', close: '23:00'));
      expect(loaded.mode, ScheduleMode.sameDaily);
      expect(scheduleFieldsOf(loaded), isNull);

      loaded.clear();
      expect(scheduleFieldsOf(loaded)!.mode, '');

      final per = ServiceHours()..setMode(ScheduleMode.perDay);
      per.days.last.off = true;
      final f = scheduleFieldsOf(per)!;
      expect(f.mode, 'per_day');
      expect(f.perDay, hasLength(7));
      expect(f.perDay!.last, {
        'day': 'sun',
        'open_time': '09:00',
        'close_time': '17:00',
        'is_off': true,
      });
    });

    test('malformed stored hours load as untouched and empty', () {
      final h = ServiceHours.fromService(
          storedService(scheduleMode: 'per_day', perDay: [
        {'day': 'mon', 'open_time': '09:00', 'close_time': '17:00'}
      ]));
      expect(h.mode, isNull);
      expect(h.touched, isFalse);
    });

    test('example price uses the server formula', () {
      expect(examplePrice('20', '4.5'), 20 + 5 * 4.5);
      expect(examplePrice('20', ''), isNull);
      expect(examplePrice('-1', '3'), isNull);
    });

    test('own service by tenant_id or owner_id', () {
      final list = [
        {'id': 'a', 'tenant_id': 'other'},
        {'id': 'b', 'owner_id': 'owner-1'},
      ];
      expect(ownServiceOf(list, 'owner-1')?['id'], 'b');
      expect(ownServiceOf(list, 'nobody'), isNull);
      expect(ownServiceOf(list, null), isNull);
    });

    test('save failures from the handlers', () {
      expect(
          serviceSaveFailureOf(
              apiErr(403, 'action blocked: owner KYC approval is pending')),
          ServiceSaveFailure.kybNotApproved);
      expect(serviceSaveFailureOf(apiErr(402, 'upgrade_required')),
          ServiceSaveFailure.paidPlanRequired);
      expect(serviceSaveFailureOf(apiErr(503)), ServiceSaveFailure.unavailable);
      expect(serviceSaveFailureOf(apiErr(400)), ServiceSaveFailure.other);
      expect(serviceSaveFailureOf(Exception('x')), ServiceSaveFailure.other);
    });
  });

  group('OwnerServicePage', () {
    final picks = <PickedPlace?>[];
    final times = <TimeOfDay>[];

    Widget page({PickedPlace? place, TimeOfDay? time}) => OwnerServicePage(
          pickPlace: (_, initial) async {
            picks.add(initial);
            return place;
          },
          pickTime: (_, initial) async => time,
        );

    setUp(() {
      picks.clear();
      times.clear();
    });

    Future<void> pumpPage(WidgetTester tester, OwnerTestDeps deps,
        {Widget? home, Locale locale = const Locale('en')}) async {
      await tester.pumpWidget(
          ownerApp(deps, home ?? page(), locale: locale, withData: false));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('own_service_save')));
      await tester.pumpAndSettle();
    }

    testWidgets('loading while the services list is fetched', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.servicesGate = Completer<void>();
      await tester.pumpWidget(ownerApp(deps, page(), withData: false));
      await tester.pump();
      expect(find.byKey(const Key('own_service_loading')), findsOneWidget);
      expect(find.byKey(const Key('own_service_save')), findsNothing);
      deps.owner.servicesGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_service_form')), findsOneWidget);
      expect(deps.auth.profileCalls, 1);
    });

    testWidgets('load error with retry, never an empty form', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextServicesError = 'down';
      await pumpPage(tester, deps);
      expect(find.byKey(const Key('own_service_error')), findsOneWidget);
      expect(find.byKey(const Key('own_service_form')), findsNothing);

      deps.owner.nextServicesError = null;
      deps.owner.nextServices = [storedService()];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(deps.owner.serviceCalls, 2);
      expect(find.text('Nile Express'), findsWidgets);
    });

    testWidgets('prefills the owner\'s service and its hours', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextServices = [
        {'id': 'other', 'tenant_id': 'someone', 'name': 'Not mine'},
        storedService(
            scheduleMode: 'same_daily', open: '09:00', close: '23:00'),
      ];
      await pumpPage(tester, deps);

      expect(find.text('Nile Express'), findsOneWidget);
      expect(find.text('12 Talaat Harb St'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('30.0444, 31.2357'), findsOneWidget);
      expect(find.text('23:00'), findsOneWidget);
      expect(find.text('Example: a 5 km trip shows the customer EGP 42.50.'),
          findsOneWidget);
      // The stored local path is no photo: the letter placeholder.
      expect(
          find.byKey(const Key('service_photo_placeholder')), findsOneWidget);
      expect(find.text('N'), findsOneWidget);
    });

    testWidgets('the example follows the prices as they are typed',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      await pumpPage(tester, deps);
      expect(find.text('Enter both prices to see what a customer pays.'),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('own_service_base_fee')), '15');
      await tester.enterText(find.byKey(const Key('own_service_per_km')), '٣');
      await tester.pump();
      expect(find.text('Example: a 5 km trip shows the customer EGP 30.'),
          findsOneWidget);
    });

    testWidgets('validation: every field shows its problem, nothing is sent',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      await pumpPage(tester, deps);
      await tester.enterText(find.byKey(const Key('own_service_address')), 'a');
      await save(tester);

      expect(find.text('Enter the service name'), findsOneWidget);
      expect(find.text('Write at least 3 letters, or leave it empty'),
          findsOneWidget);
      expect(find.text('Enter a distance above 0'), findsOneWidget);
      expect(find.text('Enter 0 or more'), findsNWidgets(2));
      expect(find.text('Check the fields marked in red'), findsOneWidget);
      expect(deps.owner.createCalls, isEmpty);
      expect(deps.owner.updateCalls, isEmpty);

      // Errors clear as the fields are fixed.
      await tester.enterText(find.byKey(const Key('own_service_name')), 'Nile');
      await tester.pump();
      expect(find.text('Enter the service name'), findsNothing);
    });

    testWidgets('update: one PUT with every field, no photo, no free text',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextServices = [storedService()];
      await pumpPage(tester, deps);
      await tester.tap(find.byKey(const Key('own_service_kind_delivery')));
      await tester.enterText(find.byKey(const Key('own_service_radius')), '12');
      await save(tester);

      expect(deps.owner.createCalls, isEmpty);
      expect(deps.owner.updateCalls, [
        {
          'service_id': 'svc-1',
          'owner_id': 'owner-1',
          'name': 'Nile Express',
          'category': 'delivery',
          'tenant_base_price': 20.0,
          'tenant_price_per_km': 4.5,
          'address': '12 Talaat Harb St',
          'coverage_radius_km': 12.0,
          'latitude': 30.0444,
          'longitude': 31.2357,
        }
      ]);
      expect(find.text('Service saved'), findsOneWidget);
      expect(deps.auth.profileCalls, 2);
    });

    testWidgets('create: POST, then the PUT that sets every field',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      await pumpPage(tester, deps,
          home: page(
              place: const PickedPlace(latitude: 30.1, longitude: 31.3),
              time: const TimeOfDay(hour: 22, minute: 30)));

      await tester.enterText(find.byKey(const Key('own_service_name')), 'Nile');
      await tester.tap(find.byKey(const Key('own_service_place')));
      await tester.pumpAndSettle();
      expect(picks, [null]);
      expect(find.text('30.1000, 31.3000'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('own_service_address')), 'Maadi, road 9');
      await tester.enterText(find.byKey(const Key('own_service_radius')), '6');
      await tester.enterText(
          find.byKey(const Key('own_service_base_fee')), '15');
      await tester.enterText(find.byKey(const Key('own_service_per_km')), '3');
      await tester
          .ensureVisible(find.byKey(const Key('own_service_hours_set')));
      await tester.tap(find.byKey(const Key('own_service_hours_set')));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const Key('own_service_same_close')));
      await tester.tap(find.byKey(const Key('own_service_same_close')));
      await tester.pumpAndSettle();
      await save(tester);

      expect(deps.owner.createCalls, [
        {
          'name': 'Nile',
          'category': 'delivery',
          'tenant_base_price': 15.0,
          'tenant_price_per_km': 3.0,
          'latitude': 30.1,
          'longitude': 31.3,
          'owner_id': 'owner-1',
        }
      ]);
      expect(deps.owner.updateCalls, [
        {
          'service_id': 'svc-new',
          'owner_id': 'owner-1',
          'name': 'Nile',
          'category': 'delivery',
          'tenant_base_price': 15.0,
          'tenant_price_per_km': 3.0,
          'address': 'Maadi, road 9',
          'coverage_radius_km': 6.0,
          'latitude': 30.1,
          'longitude': 31.3,
          'schedule_mode': 'same_daily',
          'open_time': '09:00',
          'close_time': '22:30',
        }
      ]);
      expect(find.text('Service saved'), findsOneWidget);
    });

    testWidgets('create worked, PUT failed: says so, next save is a PUT',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextUpdateError = apiErr(500);
      await pumpPage(tester, deps,
          home:
              page(place: const PickedPlace(latitude: 30.1, longitude: 31.3)));
      await tester.enterText(find.byKey(const Key('own_service_name')), 'Nile');
      await tester.tap(find.byKey(const Key('own_service_place')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('own_service_radius')), '6');
      await tester.enterText(
          find.byKey(const Key('own_service_base_fee')), '15');
      await tester.enterText(find.byKey(const Key('own_service_per_km')), '3');
      await save(tester);

      expect(find.byKey(const Key('own_service_save_error')), findsOneWidget);
      expect(
          find.text(
              'The service was created but some details weren\'t saved. Tap save again.'),
          findsOneWidget);
      expect(find.byKey(const Key('own_service_page')), findsOneWidget);

      deps.owner.nextUpdateError = null;
      await save(tester);
      expect(deps.owner.createCalls, hasLength(1));
      expect(deps.owner.updateCalls, hasLength(2));
      expect(deps.owner.updateCalls.last['service_id'], 'svc-new');
    });

    testWidgets('KYB not approved: banner, and the 403 is explained',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps(
          auth: FakeOwnerAuth(kycStatus: 'pending_super_admin_approval'));
      deps.owner.nextServices = [storedService()];
      deps.owner.nextUpdateError =
          apiErr(403, 'action blocked: owner KYC approval is pending');
      await pumpPage(tester, deps);
      expect(find.byKey(const Key('own_kyb_pending')), findsOneWidget);
      await tester.tap(find.text('View documents'));
      expect(deps.nav.opened, ['kyb']);

      await save(tester);
      expect(
          find.text(
              'Your business papers need to be approved before you can save the service.'),
          findsOneWidget);
    });

    testWidgets('402 and 503 have their own messages', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextServices = [storedService()];
      deps.owner.nextUpdateError = apiErr(402, 'upgrade_required');
      await pumpPage(tester, deps);
      await save(tester);
      expect(find.text('Saving the service needs an active plan.'),
          findsOneWidget);
      deps.owner.nextUpdateError = apiErr(503);
      await save(tester);
      expect(find.text('This is unavailable right now. Try again in a bit.'),
          findsOneWidget);
    });

    testWidgets('double tap while saving sends one request', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextServices = [storedService()];
      deps.owner.updateGate = Completer<void>();
      await pumpPage(tester, deps);
      await tester.tap(find.byKey(const Key('own_service_save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('own_service_save')));
      await tester.pump();
      expect(deps.owner.updateCalls, hasLength(1));
      deps.owner.updateGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('hours: per day with a day off, then removed (explicit clear)',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextServices = [
        storedService(scheduleMode: 'same_daily', open: '09:00', close: '17:00')
      ];
      await pumpPage(tester, deps);
      await tester.ensureVisible(find.text('Each day'));
      await tester.tap(find.text('Each day'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_service_day_mon')), findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const Key('own_service_day_fri_off')));
      await tester.tap(find.byKey(const Key('own_service_day_fri_off')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_service_day_fri_open')), findsNothing);
      await save(tester);
      final perDay =
          deps.owner.updateCalls.single['per_day_schedule'] as List<dynamic>;
      expect(deps.owner.updateCalls.single['schedule_mode'], 'per_day');
      expect(perDay, hasLength(7));
      expect((perDay[4] as Map)['is_off'], isTrue);
    });

    testWidgets('removing the hours sends schedule_mode ""', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextServices = [
        storedService(scheduleMode: 'same_daily', open: '09:00', close: '17:00')
      ];
      await pumpPage(tester, deps);
      await tester
          .ensureVisible(find.byKey(const Key('own_service_hours_remove')));
      await tester.tap(find.byKey(const Key('own_service_hours_remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_service_hours_none')), findsOneWidget);
      await save(tester);
      expect(deps.owner.updateCalls.single['schedule_mode'], '');
    });

    testWidgets('a missing location blocks the save', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      await pumpPage(tester, deps);
      await tester.enterText(find.byKey(const Key('own_service_name')), 'Nile');
      await tester.enterText(find.byKey(const Key('own_service_radius')), '6');
      await tester.enterText(
          find.byKey(const Key('own_service_base_fee')), '15');
      await tester.enterText(find.byKey(const Key('own_service_per_km')), '3');
      await save(tester);
      expect(deps.owner.createCalls, isEmpty);
      expect(find.text('Required'), findsOneWidget);
    });
  });
}
