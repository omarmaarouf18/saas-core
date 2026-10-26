import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/redesign_update_gate.dart';
import 'package:frontend/features/auth/update_required_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/qd_launch.dart';

import '../../helpers/fake_launcher.dart';

import 'auth_harness.dart';

void main() {
  late List<String> clipboard;

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('server versions and link; the copy button copies the link',
      (tester) async {
    usePhone(tester);
    await tester.pumpWidget(authApp(
        AuthTestDeps(),
        const UpdateRequiredPage(
          currentVersion: '1.0.0',
          minimumVersion: '1.2.0',
          downloadUrl: 'https://example.com/app.apk',
        )));
    await tester.pumpAndSettle();
    expect(find.text('Update the app'), findsOneWidget);
    expect(find.text('Installed version'), findsOneWidget);
    expect(find.text('Oldest version that works'), findsOneWidget);
    expect(find.text('Latest version'), findsNothing); // not sent
    expect(find.text('https://example.com/app.apk'), findsOneWidget);

    await tester.tap(find.byKey(const Key('update_copy')));
    await tester.pump();
    expect(clipboard, ['https://example.com/app.apk']);
    expect(
        find.text(
            'Link copied. Open it in your browser to install the new version.'),
        findsOneWidget);
  });

  testWidgets('download opens the link in another app', (tester) async {
    usePhone(tester);
    final launcher = FakeLauncher(opens: (_) => true);
    await tester.pumpWidget(authApp(
        AuthTestDeps(),
        QdLauncherScope(
          launcher: launcher,
          child: const UpdateRequiredPage(
              downloadUrl: 'https://example.com/app.apk'),
        )));
    await tester.pumpAndSettle();
    expect(find.text('Download the update'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update_download')));
    await tester.pump();
    expect(launcher.tried, [Uri.parse('https://example.com/app.apk')]);
    expect(clipboard, isEmpty);
  });

  testWidgets('download with nothing to open it: the link is copied',
      (tester) async {
    usePhone(tester);
    final launcher = FakeLauncher();
    await tester.pumpWidget(authApp(
        AuthTestDeps(),
        QdLauncherScope(
          launcher: launcher,
          child: const UpdateRequiredPage(),
        )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('update_download')));
    await tester.pump();
    expect(launcher.tried, [Uri.parse(kFallbackDownloadUrl)]);
    expect(clipboard, [kFallbackDownloadUrl]);
    expect(
        find.text(
            'Link copied. Open it in your browser to install the new version.'),
        findsOneWidget);
  });

  testWidgets('no link from the server: the release fallback', (tester) async {
    usePhone(tester);
    await tester
        .pumpWidget(authApp(AuthTestDeps(), const UpdateRequiredPage()));
    await tester.pumpAndSettle();
    expect(find.text(kFallbackDownloadUrl), findsOneWidget);
    expect(find.text('Installed version'), findsNothing);
    await tester.tap(find.byKey(const Key('update_copy')));
    await tester.pump();
    expect(clipboard, [kFallbackDownloadUrl]);
  });

  testWidgets('gate replaces the stack once; back stays on the page',
      (tester) async {
    usePhone(tester);
    final key = GlobalKey<NavigatorState>();
    final gate = RedesignUpdateGate(key);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Text('app'),
    ));
    await gate.handle({
      'current_version': '1.0.0',
      'min_version': '1.3.0',
      'download_url': 'https://example.com/a.apk',
    });
    await tester.pumpAndSettle();
    expect(find.byType(UpdateRequiredPage), findsOneWidget);
    expect(find.text('app'), findsNothing);
    expect(find.text('Oldest version that works'), findsOneWidget);

    await gate.handle({'download_url': 'https://example.com/b.apk'});
    await tester.pumpAndSettle();
    expect(find.byType(UpdateRequiredPage), findsOneWidget);
    expect(find.text('https://example.com/a.apk'), findsOneWidget);

    final popped = await key.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(popped, isTrue); // handled by PopScope, page stays
    expect(find.byType(UpdateRequiredPage), findsOneWidget);
  });
}
