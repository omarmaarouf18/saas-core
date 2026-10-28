import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/services/local_notifications.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

class _RecordingNotifier implements LocalNotifier {
  final channels = <(String, String)>[];

  @override
  Future<bool> ensureChannel(
      {required String name, required String description}) async {
    channels.add((name, description));
    return true;
  }

  @override
  Future<bool> openAppSettings() async => false;
}

Widget _app(Locale locale, LocalNotifier notifier) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          PushChannelSync(notifier: notifier, child: child!),
      home: const SizedBox(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginLocalNotifier.ensureChannel', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return call.method == 'initialize' ? true : null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('creates qd_default with high importance on Android', () async {
      final n = PluginLocalNotifier(android: true);
      final ok = await n.ensureChannel(name: 'Order updates', description: 'd');
      expect(ok, isTrue);
      final create =
          calls.singleWhere((c) => c.method == 'createNotificationChannel');
      final args = (create.arguments as Map).cast<String, Object?>();
      expect(args['id'], 'qd_default');
      expect(args['name'], 'Order updates');
      expect(args['description'], 'd');
      expect(args['importance'], Importance.high.value);
      // A second call (language change) renames it; the plugin is
      // initialized once.
      await n.ensureChannel(name: 'تحديثات الطلبات', description: 'd');
      expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
      expect(calls.where((c) => c.method == 'createNotificationChannel'),
          hasLength(2));
    });

    test('guarded: not Android → no plugin call, false', () async {
      final n = PluginLocalNotifier(android: false);
      expect(await n.ensureChannel(name: 'x', description: 'y'), isFalse);
      expect(calls, isEmpty);
    });

    test('guarded: plugin missing → false, no throw', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      final n = PluginLocalNotifier(android: true);
      expect(await n.ensureChannel(name: 'x', description: 'y'), isFalse);
    });
  });

  group('PushChannelSync', () {
    testWidgets('creates the channel in the app language, renames on change',
        (tester) async {
      final n = _RecordingNotifier();
      await tester.pumpWidget(_app(const Locale('en'), n));
      await tester.pumpAndSettle();
      expect(n.channels, [
        ('Order updates',
            'Bookings, pickups, deliveries and cancellations of your orders.')
      ]);
      // Rebuilding in the same language does not re-create it.
      await tester.pumpWidget(_app(const Locale('en'), n));
      await tester.pumpAndSettle();
      expect(n.channels, hasLength(1));

      await tester.pumpWidget(_app(const Locale('ar'), n));
      await tester.pumpAndSettle();
      expect(n.channels, hasLength(2));
      expect(n.channels.last.$1, 'تحديثات الطلبات');
    });
  });
}
