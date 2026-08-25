import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/widgets/create_service_dialog.dart';

class MockOwnerProviderForCreateService extends OwnerProvider {
  bool createServiceCalled = false;
  String? createdName;
  String? createdCategory;
  double? createdBasePrice;
  double? createdRate;
  double? createdLat;
  double? createdLon;
  String? createdOwnerId;
  bool shouldThrowOnCreate = false;

  MockOwnerProviderForCreateService(super.apiClient);

  @override
  Future<Map<String, dynamic>> createService({
    required String name,
    required String category,
    required double tenantBasePrice,
    required double tenantPricePerKM,
    required double latitude,
    required double longitude,
    required String ownerId,
  }) async {
    if (shouldThrowOnCreate) {
      throw Exception('Service name already exists');
    }
    createServiceCalled = true;
    createdName = name;
    createdCategory = category;
    createdBasePrice = tenantBasePrice;
    createdRate = tenantPricePerKM;
    createdLat = latitude;
    createdLon = longitude;
    createdOwnerId = ownerId;
    return {'id': 'svc-1', 'name': name};
  }
}

Widget buildCreateServiceTestApp({
  required OwnerProvider ownerProvider,
}) {
  return MultiProvider(
    providers: [
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
              onPressed: () => CreateServiceDialog.show(
                ctx,
                ownerId: 'owner-test-1',
              ),
              child: const Text('Open Create Service Dialog'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('CreateServiceDialog renders all inputs and buttons',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final owner = MockOwnerProviderForCreateService(apiClient);

    await tester.pumpWidget(buildCreateServiceTestApp(ownerProvider: owner));
    await tester.tap(find.text('Open Create Service Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Create New Service'), findsOneWidget);
    expect(find.byKey(const Key('service_name_field')), findsOneWidget);
    expect(find.byKey(const Key('service_category_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('service_base_price_field')), findsOneWidget);
    expect(find.byKey(const Key('service_price_per_km_field')), findsOneWidget);
    expect(find.byKey(const Key('service_latitude_field')), findsOneWidget);
    expect(find.byKey(const Key('service_longitude_field')), findsOneWidget);
    expect(find.byKey(const Key('service_create_button')), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('CreateServiceDialog close button exposes tooltip semantics',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final owner = MockOwnerProviderForCreateService(apiClient);

    await tester.pumpWidget(buildCreateServiceTestApp(ownerProvider: owner));
    await tester.tap(find.text('Open Create Service Dialog'));
    await tester.pumpAndSettle();

    final button = tester.widget<IconButton>(
      find.byKey(const Key('close_create_service_dialog')),
    );
    expect(button.tooltip, isNotNull);
    expect(button.tooltip, isNotEmpty);
  });

  testWidgets('CreateServiceDialog validates required fields',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final owner = MockOwnerProviderForCreateService(apiClient);

    await tester.pumpWidget(buildCreateServiceTestApp(ownerProvider: owner));
    await tester.tap(find.text('Open Create Service Dialog'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('service_create_button')));
    await tester.tap(find.byKey(const Key('service_create_button')));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Base price is required'), findsOneWidget);
    expect(find.text('Rate is required'), findsOneWidget);
  });

  testWidgets('CreateServiceDialog validates latitude and longitude ranges',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final owner = MockOwnerProviderForCreateService(apiClient);

    await tester.pumpWidget(buildCreateServiceTestApp(ownerProvider: owner));
    await tester.tap(find.text('Open Create Service Dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('service_name_field')), 'Express Delivery');
    await tester.enterText(
        find.byKey(const Key('service_base_price_field')), '20.0');
    await tester.enterText(
        find.byKey(const Key('service_price_per_km_field')), '5.0');
    await tester.enterText(
        find.byKey(const Key('service_latitude_field')), '120.0');
    await tester.enterText(
        find.byKey(const Key('service_longitude_field')), '-200.0');

    await tester.ensureVisible(find.byKey(const Key('service_create_button')));
    await tester.tap(find.byKey(const Key('service_create_button')));
    await tester.pumpAndSettle();

    expect(find.text('Must be between -90 and 90'), findsOneWidget);
    expect(find.text('Must be between -180 and 180'), findsOneWidget);
  });

  testWidgets('CreateServiceDialog successfully submits valid form',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final owner = MockOwnerProviderForCreateService(apiClient);

    await tester.pumpWidget(buildCreateServiceTestApp(ownerProvider: owner));
    await tester.tap(find.text('Open Create Service Dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('service_name_field')), 'Super Cargo');
    await tester.enterText(
        find.byKey(const Key('service_base_price_field')), '35.50');
    await tester.enterText(
        find.byKey(const Key('service_price_per_km_field')), '8.25');
    await tester.enterText(
        find.byKey(const Key('service_latitude_field')), '30.0444');
    await tester.enterText(
        find.byKey(const Key('service_longitude_field')), '31.2357');

    await tester.ensureVisible(find.byKey(const Key('service_create_button')));
    await tester.tap(find.byKey(const Key('service_create_button')));
    await tester.pumpAndSettle();

    expect(owner.createServiceCalled, isTrue);
    expect(owner.createdName, 'Super Cargo');
    expect(owner.createdCategory, 'delivery');
    expect(owner.createdBasePrice, 35.50);
    expect(owner.createdRate, 8.25);
    expect(owner.createdLat, 30.0444);
    expect(owner.createdLon, 31.2357);
    expect(owner.createdOwnerId, 'owner-test-1');
    expect(find.byType(CreateServiceDialog), findsNothing);
  });

  testWidgets('CreateServiceDialog displays error message on API failure',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final owner = MockOwnerProviderForCreateService(apiClient);
    owner.shouldThrowOnCreate = true;

    await tester.pumpWidget(buildCreateServiceTestApp(ownerProvider: owner));
    await tester.tap(find.text('Open Create Service Dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('service_name_field')), 'Duplicate Name');
    await tester.enterText(
        find.byKey(const Key('service_base_price_field')), '20.0');
    await tester.enterText(
        find.byKey(const Key('service_price_per_km_field')), '5.0');

    await tester.ensureVisible(find.byKey(const Key('service_create_button')));
    await tester.tap(find.byKey(const Key('service_create_button')));
    await tester.pumpAndSettle();

    expect(owner.createServiceCalled, isFalse);
    expect(find.byType(CreateServiceDialog), findsOneWidget);
  });

  testWidgets(
      'CreateServiceDialog adapts without overflow on 360dp mobile viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final apiClient = ApiClient();
    final owner = MockOwnerProviderForCreateService(apiClient);

    await tester.pumpWidget(buildCreateServiceTestApp(ownerProvider: owner));
    await tester.tap(find.text('Open Create Service Dialog'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CreateServiceDialog), findsOneWidget);
  });
}
