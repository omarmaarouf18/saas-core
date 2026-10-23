import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/qd_launch.dart';

import '../helpers/fake_launcher.dart';

// FE-V2-CONSUME item 1: links and the open-or-copy fallback.
void main() {
  test('phoneCallUri keeps digits and a leading plus', () {
    expect(phoneCallUri('+20 101-234 5678').toString(), 'tel:+201012345678');
    expect(phoneCallUri('(010) 1234 5678').toString(), 'tel:01012345678');
  });

  test('coordsText has 6 decimals', () {
    expect(coordsText(30.0444, 31.2357), '30.044400,31.235700');
  });

  test('mapsUris per platform', () {
    final android =
        mapsUris(30.0444, 31.2357, platform: TargetPlatform.android);
    expect(android.first.toString(),
        'geo:30.044400,31.235700?q=30.044400,31.235700');
    expect(android.last.host, 'www.google.com');
    expect(android.last.queryParameters['query'], '30.044400,31.235700');

    final ios = mapsUris(30.0444, 31.2357, platform: TargetPlatform.iOS);
    expect(ios.first.host, 'maps.apple.com');
    expect(ios.first.queryParameters['q'], '30.044400,31.235700');
    expect(ios.last.host, 'www.google.com');

    final linux = mapsUris(30.0444, 31.2357, platform: TargetPlatform.linux);
    expect(linux, hasLength(1));
    expect(linux.single.host, 'www.google.com');
  });

  group('openOrCopy', () {
    late List<String> copied;

    setUp(() {
      copied = [];
      TestWidgetsFlutterBinding.ensureInitialized()
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });

    tearDown(() => TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    Future<BuildContext> pump(WidgetTester tester, FakeLauncher l) async {
      late BuildContext ctx;
      await tester.pumpWidget(QdLauncherScope(
        launcher: l,
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      return ctx;
    }

    final a = Uri.parse('geo:1,2'), b = Uri.parse('https://example.com/');

    testWidgets('first link that opens wins, nothing copied', (tester) async {
      final l = FakeLauncher(opens: (u) => u == b);
      final ctx = await pump(tester, l);
      var notices = 0;
      final ok = await openOrCopy(ctx, [a, b],
          copyText: '1,2', onCopied: () => notices++);
      expect(ok, isTrue);
      expect(l.tried, [a, b]);
      expect(copied, isEmpty);
      expect(notices, 0);
    });

    testWidgets('nothing opens: copies and notifies', (tester) async {
      final l = FakeLauncher();
      final ctx = await pump(tester, l);
      var notices = 0;
      final ok = await openOrCopy(ctx, [a, b],
          copyText: '1,2', onCopied: () => notices++);
      expect(ok, isFalse);
      expect(copied, ['1,2']);
      expect(notices, 1);
    });

    testWidgets('no scope: the real url_launcher launcher', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      expect(QdLauncherScope.of(ctx), isA<UrlQdLauncher>());
    });
  });
}
