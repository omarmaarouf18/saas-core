import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/booking_page.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/market_page.dart';

import '../../helpers/fake_service_photos.dart';
import 'customer_harness.dart';

const _pickup = PickedPlace(latitude: 30.07, longitude: 31.28);

void main() {
  testWidgets('market card: the photo when stored, the initial otherwise',
      (tester) async {
    usePhone(tester);
    final photos = FakeServicePhotoStore(photos: {
      'with': solidPng(8, 40, 90, 160),
      'broken': Uint8List(0),
    });
    final deps = CustomerTestDeps(photos: photos);
    deps.marketplace.nextServices = [
      service(id: 'with', name: 'Nile', photoUrl: 'services/with/photo.png'),
      service(id: 'none', name: 'Delta', distanceKm: 3),
      service(
          id: 'local',
          name: 'Old',
          distanceKm: 4,
          photoUrl: '/data/user/0/app/cache/x.jpg'),
    ];
    await tester.pumpWidget(customerApp(
        deps, const CustomerMarketPage(category: 'delivery', pickup: _pickup)));
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('cust_market_service_with'));
    expect(
        find.descendant(
            of: card, matching: find.byKey(const Key('service_photo_image'))),
        findsOneWidget);
    for (final id in ['none', 'local']) {
      final c = find.byKey(Key('cust_market_service_$id'));
      expect(
          find.descendant(
              of: c,
              matching: find.byKey(const Key('service_photo_placeholder'))),
          findsOneWidget,
          reason: id);
    }
    // Only the stored key is loaded; a device path never is.
    expect(photos.loads, ['with']);
  });

  testWidgets('booking page (service detail) shows the company photo',
      (tester) async {
    usePhone(tester);
    final photos =
        FakeServicePhotoStore(photos: {'svc-1': solidPng(8, 40, 90, 160)});
    await tester.pumpWidget(customerApp(
      CustomerTestDeps(photos: photos),
      CustomerBookingPage(
          service: service(photoUrl: 'services/svc-1/photo.png'),
          pickup: _pickup),
    ));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('cust_book_service_photo')),
            matching: find.byKey(const Key('service_photo_image'))),
        findsOneWidget);
  });

  testWidgets('failed load: placeholder', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(customerApp(
      CustomerTestDeps(photos: FakeServicePhotoStore()),
      CustomerBookingPage(
          service: service(photoUrl: 'services/svc-1/photo.png'),
          pickup: _pickup),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('service_photo_placeholder')), findsOneWidget);
  });
}
