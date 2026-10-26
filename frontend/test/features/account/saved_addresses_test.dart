import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/saved_address_rules.dart';
import 'package:frontend/features/account/saved_addresses_page.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:frontend/models/saved_address.dart';
import 'package:frontend/models/user_profile.dart';

import 'account_harness.dart';

const home = SavedAddress(
  id: 'addr-home',
  label: 'Home',
  address: '10 Tahrir Square, Cairo',
  addressNote: 'Floor 3, Apt 12',
  latitude: 30.0444,
  longitude: 31.2357,
);
const work = SavedAddress(
  id: 'addr-work',
  label: 'Work',
  address: 'Building B2, Smart Village',
  latitude: 30.075,
  longitude: 31.02,
);

/// Picks [place] for every pin request and records the initial pins.
class FakePin {
  FakePin(this.place);

  PickedPlace? place;
  final List<PickedPlace?> initials = [];

  Future<PickedPlace?> call(BuildContext _, PickedPlace? initial) async {
    initials.add(initial);
    return place;
  }
}

Future<void> _open(WidgetTester tester, AccountTestDeps deps,
    {FakePin? pin}) async {
  usePhone(tester);
  final page = SavedAddressesPage(pickPin: pin?.call);
  await tester.pumpWidget(accountApp(
      deps,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('host'),
          ),
        ),
      )));
  await tester.tap(find.text('host'));
  await tester.pumpAndSettle();
}

AccountTestDeps _deps(
        {List<SavedAddress> saved = const [home, work],
        List<String>? addresses,
        String? accountStatus}) =>
    AccountTestDeps(
        auth: FakeAuthFlow(
            user: FakeAuthFlow.customer(
                saved: saved,
                addresses: addresses,
                accountStatus: accountStatus)));

List<dynamic>? _sent(AccountTestDeps deps) =>
    deps.auth.lastProfileUpdate?['saved_addresses'] as List<dynamic>?;

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('address_save')));
  await tester.pumpAndSettle();
}

void main() {
  group('rules', () {
    test('labels: Home / Work in the app language, Arabic words count', () {
      final en = AppLocalizationsEn();
      final ar = AppLocalizationsAr();
      expect(savedLabelKindOf('home'), SavedLabelKind.home);
      expect(savedLabelKindOf('البيت'), SavedLabelKind.home);
      expect(savedLabelKindOf(' Work '), SavedLabelKind.work);
      expect(savedLabelKindOf('الشغل'), SavedLabelKind.work);
      expect(savedLabelKindOf('Gym'), SavedLabelKind.other);
      expect(savedLabelText(ar, 'Home'), 'البيت');
      expect(savedLabelText(en, 'الشغل'), 'Work');
      expect(savedLabelText(en, 'Gym'), 'Gym');
      expect(savedLabelValue(SavedLabelKind.home, 'x'), 'Home');
      expect(savedLabelValue(SavedLabelKind.other, ' Gym '), 'Gym');
    });

    test('validation counts characters, needs a pin in range', () {
      SavedAddressProblems v(
              {String label = 'Home',
              String address = 'x',
              String note = '',
              double? lat = 30,
              double? lng = 31}) =>
          validateSavedAddress(
              label: label,
              address: address,
              note: note,
              latitude: lat,
              longitude: lng);
      expect(v().any, isFalse);
      expect(v(label: ' ').labelMissing, isTrue);
      expect(v(address: '  ').addressMissing, isTrue);
      expect(v(lat: null).pinMissing, isTrue);
      expect(v(lat: 91).pinMissing, isTrue);
      expect(v(lng: -181).pinMissing, isTrue);
      // 250 Arabic letters are 500 bytes but 250 characters: allowed.
      expect(v(address: 'ب' * 250).addressTooLong, isFalse);
      expect(v(address: 'ب' * 251).addressTooLong, isTrue);
      expect(v(note: 'ن' * 500).noteTooLong, isFalse);
      expect(v(note: 'ن' * 501).noteTooLong, isTrue);
      expect(v(label: 'ل' * 100).labelTooLong, isFalse);
      expect(v(label: 'ل' * 101).labelTooLong, isTrue);
    });

    test('legacy: frequent strings no saved address covers', () {
      final user = UserProfile(
        id: 'u',
        email: '',
        username: '',
        role: 'user',
        frequentAddresses: [home.address, ' Gym ', '', 'Gym'],
        savedAddresses: const [home],
      );
      expect(legacyAddressesOf(user), ['Gym']);
      expect(legacyAddressesOf(null), isEmpty);
    });

    test('model: lat/lng aliases in, latitude/longitude out', () {
      final a = SavedAddress.fromJson({
        'id': 'a1',
        'label': 'Home',
        'address': 'x',
        'address_note': 'n',
        'lat': 30.5,
        'lng': 31.5,
      });
      expect((a.latitude, a.longitude), (30.5, 31.5));
      expect(a.toJson(), {
        'id': 'a1',
        'label': 'Home',
        'address': 'x',
        'address_note': 'n',
        'latitude': 30.5,
        'longitude': 31.5,
      });
      final p = UserProfile.fromJson({
        'id': 'u',
        'role': 'user',
        'saved_addresses': [
          {
            'id': 'b',
            'label': 'Work',
            'address': 'y',
            'latitude': 1,
            'longitude': 2
          }
        ],
      });
      expect(p.savedAddresses.single.longitude, 2);
      expect(UserProfile.fromJson({'id': 'u'}).savedAddresses, isEmpty);
    });
  });

  group('Saved addresses page', () {
    testWidgets('lists label, address and note', (tester) async {
      final deps = _deps();
      await _open(tester, deps);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('10 Tahrir Square, Cairo'), findsOneWidget);
      expect(find.text('Floor 3, Apt 12'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.textContaining('2 of 10'), findsOneWidget);
      expect(find.text('Not on the map yet'), findsNothing);
    });

    testWidgets('add: needs the address and the pin, then saves the list',
        (tester) async {
      final deps = _deps();
      final pin = FakePin(const PickedPlace(latitude: 30.06, longitude: 31.33));
      await _open(tester, deps, pin: pin);
      await tester.tap(find.byKey(const Key('addresses_add')));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(find.text('Write the address'), findsOneWidget);
      expect(find.text('Pin the place on the map'), findsOneWidget);
      expect(_sent(deps), isNull);

      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await typeInto(tester, 'address_input', ' Gym, Nasr City ');
      await typeInto(tester, 'address_note_input', 'Next to the mall');
      await _save(tester);
      expect(find.text('Choose or write a name'), findsOneWidget);
      await typeInto(tester, 'address_label_custom', 'Gym');
      await tester.tap(find.byKey(const Key('address_pin')));
      await tester.pumpAndSettle();
      expect(pin.initials, [null]);
      expect(find.text('30.0600, 31.3300'), findsOneWidget);
      await _save(tester);

      expect(_sent(deps), [
        home.toJson(),
        work.toJson(),
        {
          'label': 'Gym',
          'address': 'Gym, Nasr City',
          'address_note': 'Next to the mall',
          'latitude': 30.06,
          'longitude': 31.33,
        },
      ]);
      expect(deps.auth.lastProfileUpdate!.containsKey('frequent_addresses'),
          isFalse);
      expect(find.text('Gym'), findsOneWidget);
      expect(find.textContaining('3 of 10'), findsOneWidget);
    });

    testWidgets('edit keeps the id and starts the pin where it was',
        (tester) async {
      final deps = _deps();
      final pin = FakePin(null);
      await _open(tester, deps, pin: pin);
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('address_editor')), findsOneWidget);
      await tester.tap(find.byKey(const Key('address_pin')));
      await tester.pumpAndSettle();
      expect(pin.initials.single!.latitude, work.latitude);
      await typeInto(tester, 'address_input', 'B7, Smart Village');
      await _save(tester);
      final sent = _sent(deps)!;
      expect(sent[1]['id'], 'addr-work');
      expect(sent[1]['address'], 'B7, Smart Village');
      expect(sent[1]['latitude'], work.latitude);
    });

    testWidgets('delete saves right away; undo restores', (tester) async {
      final deps = _deps();
      await _open(tester, deps);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('address_0')),
          matching: find.byKey(const Key('address_delete'))));
      await tester.pumpAndSettle();
      expect(_sent(deps), [work.toJson()]);
      expect(find.text('Address deleted.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(_sent(deps), [home.toJson(), work.toJson()]);
      expect(find.text('10 Tahrir Square, Cairo'), findsOneWidget);
    });

    testWidgets('a failed save restores the list; retry saves it',
        (tester) async {
      final deps = _deps();
      deps.auth.failNext['updateOwnProfile'] =
          const AuthFailure('Something went wrong. Please try again.');
      await _open(tester, deps);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('address_1')),
          matching: find.byKey(const Key('address_delete'))));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
      expect(find.byKey(const Key('addresses_error')), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsNothing);
      expect(find.byKey(const Key('addresses_error')), findsNothing);
    });

    testWidgets('old string addresses: listed apart, pinning one keeps it',
        (tester) async {
      final deps =
          _deps(saved: const [], addresses: ['Gym, Nasr City', 'Club']);
      final pin = FakePin(const PickedPlace(latitude: 30.1, longitude: 31.4));
      await _open(tester, deps, pin: pin);
      expect(find.text('Not on the map yet'), findsOneWidget);
      expect(find.byKey(const Key('addresses_empty')), findsNothing);

      await tester.tap(find.descendant(
          of: find.byKey(const Key('address_legacy_0')),
          matching: find.byKey(const Key('address_legacy_pin'))));
      await tester.pumpAndSettle();
      // The editor starts with the old text; the pin is still needed.
      expect(find.text('Gym, Nasr City'), findsOneWidget);
      await tester.tap(find.byKey(const Key('address_pin')));
      await tester.pumpAndSettle();
      await _save(tester);

      // Saving rebuilds frequent_addresses server-side: "Club" would go.
      expect(find.byKey(const Key('addresses_drop_dialog')), findsOneWidget);
      expect(
          find.text('1 older address without a map pin will be removed when '
              'you save. Pin it first to keep it.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('addresses_drop_cancel')));
      await tester.pumpAndSettle();
      expect(_sent(deps), isNull);

      await tester.tap(find.descendant(
          of: find.byKey(const Key('address_legacy_0')),
          matching: find.byKey(const Key('address_legacy_pin'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('address_pin')));
      await tester.pumpAndSettle();
      await _save(tester);
      await tester.tap(find.byKey(const Key('addresses_drop_confirm')));
      await tester.pumpAndSettle();
      expect(_sent(deps), [
        {
          'label': 'Home',
          'address': 'Gym, Nasr City',
          'latitude': 30.1,
          'longitude': 31.4,
        }
      ]);
      expect(find.text('Not on the map yet'), findsNothing);
    });

    testWidgets('the last old address is pinned without a question',
        (tester) async {
      final deps = _deps(saved: const [], addresses: ['Club']);
      await _open(tester, deps,
          pin: FakePin(const PickedPlace(latitude: 30, longitude: 31)));
      await tester.tap(find.byKey(const Key('address_legacy_pin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('address_pin')));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(find.byKey(const Key('addresses_drop_dialog')), findsNothing);
      expect(_sent(deps), hasLength(1));
    });

    testWidgets('ten addresses: add is off', (tester) async {
      final deps = _deps(saved: [
        for (var i = 0; i < 10; i++)
          SavedAddress(
              id: 'a$i',
              label: 'Place $i',
              address: 'Street $i',
              latitude: 30,
              longitude: 31),
      ]);
      await _open(tester, deps);
      await tester.scrollUntilVisible(
          find.byKey(const Key('addresses_add')), 200);
      expect(find.text('You can save up to 10 addresses'), findsOneWidget);
      await tester.tap(find.byKey(const Key('addresses_add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('address_editor')), findsNothing);
    });

    testWidgets('empty state; suspended is read-only', (tester) async {
      final deps =
          _deps(saved: const [], addresses: [], accountStatus: 'suspended');
      await _open(tester, deps);
      expect(find.text('No saved addresses yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('addresses_add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('address_editor')), findsNothing);
    });
  });
}
