import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/features/account/notifications/push_permission_prompt.dart';
import 'package:frontend/services/push_notification_service.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_push.dart';
import '../customer/customer_harness.dart' as cust;
import 'account_harness.dart';

// PUSH-FCM item 3: the once-per-install permission prompt in the shells
// and the phone notifications row / "off" hint on the account page.
//
// Regenerate the goldens after an intentional change, with the CI Flutter
// version:
//   flutter test --update-goldens test/features/account/push_permission_test.dart

class _Push {
  _Push({
    PushPermission status = PushPermission.notDetermined,
    PushPermission answer = PushPermission.granted,
    bool available = true,
  }) : adapter = FakePushAdapter(
            status: status, answer: answer, available: available) {
    service = PushNotificationService(
      apiClient: ApiClient(baseUrl: 'https://ci.local/api/v1'),
      adapter: adapter,
      promptMemory: memory,
      openSettings: () async {
        settingsOpened++;
        return true;
      },
    );
  }

  final FakePushAdapter adapter;
  final MemoryPromptMemory memory = MemoryPromptMemory();
  late final PushNotificationService service;
  int settingsOpened = 0;

  /// The permission read sign-in does (token registration fails quietly:
  /// no server in tests).
  Future<void> signIn(WidgetTester tester) async {
    await service.refreshPermission();
  }
}

AccountTestDeps _deps(_Push push, {String role = 'user'}) {
  final deps = AccountTestDeps(
      auth: FakeAuthFlow(
          token: 'jwt', user: FakeAuthFlow.customer(role: role)));
  deps.extra.add(
      ChangeNotifierProvider<PushNotificationService>.value(value: push.service));
  return deps;
}

const _shell = PushPermissionPrompt(
  child: Scaffold(body: Center(child: Text('shell'))),
);

Future<void> _pumpShell(WidgetTester tester, AccountTestDeps deps,
    {Locale locale = en}) async {
  await pumpAccount(tester, deps, _shell, locale: locale);
  // The prompt waits a moment after the shell shows.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

Future<void> _scrollToAppSection(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const Key('account_theme')), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
  await tester.pumpAndSettle();
}

void main() {
  group('PushPermissionPrompt', () {
    testWidgets('offered once after a delay; Turn on asks the phone',
        (tester) async {
      final push = _Push();
      await push.signIn(tester);
      final deps = _deps(push);
      await pumpAccount(tester, deps, _shell);
      expect(find.byKey(const Key('push_prompt_turn_on')), findsNothing,
          reason: 'not on the first frame');

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Turn on notifications?'), findsOneWidget);
      expect(
          find.textContaining('your order is accepted, picked up, delivered'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('push_prompt_turn_on')));
      await tester.pumpAndSettle();
      expect(push.adapter.requestCalls, 1);
      expect(push.service.permission, PushPermission.granted);
      expect(push.memory.isAnswered, isTrue);
      expect(find.text('Turn on notifications?'), findsNothing);
    });

    testWidgets('Not now: the phone is not asked, the prompt never returns',
        (tester) async {
      final push = _Push();
      await push.signIn(tester);
      await _pumpShell(tester, _deps(push));
      await tester.tap(find.byKey(const Key('push_prompt_not_now')));
      await tester.pumpAndSettle();
      expect(push.adapter.requestCalls, 0);
      expect(push.memory.isAnswered, isTrue);

      // The shell again (next launch / tab rebuild): nothing.
      await tester.pumpWidget(const SizedBox());
      await _pumpShell(tester, _deps(push));
      expect(find.text('Turn on notifications?'), findsNothing);
    });

    testWidgets('closing the sheet counts as Not now', (tester) async {
      final push = _Push();
      await push.signIn(tester);
      await _pumpShell(tester, _deps(push));
      await tester.tapAt(const Offset(180, 40)); // the scrim
      await tester.pumpAndSettle();
      expect(find.text('Turn on notifications?'), findsNothing);
      expect(push.memory.isAnswered, isTrue);
      expect(push.adapter.requestCalls, 0);
    });

    testWidgets('waits for sign-in to read the permission', (tester) async {
      final push = _Push();
      await _pumpShell(tester, _deps(push));
      expect(find.text('Turn on notifications?'), findsNothing);
      await push.signIn(tester);
      await tester.pumpAndSettle();
      expect(find.text('Turn on notifications?'), findsOneWidget);
    });

    testWidgets('owner and courier copy', (tester) async {
      final owner = _Push();
      await owner.signIn(tester);
      await _pumpShell(tester, _deps(owner, role: 'owner'));
      expect(find.textContaining('a customer books an order'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      final courier = _Push();
      await courier.signIn(tester);
      await _pumpShell(tester, _deps(courier, role: 'employee'));
      expect(find.textContaining('new job offers'), findsOneWidget);
    });

    for (final (name, make) in [
      ('push unavailable in this build', () => _Push(available: false)),
      ('already allowed', () => _Push(status: PushPermission.granted)),
      ('already refused', () => _Push(status: PushPermission.denied)),
      ('refused for good', () => _Push(status: PushPermission.blocked)),
    ]) {
      testWidgets('not shown: $name', (tester) async {
        final push = make();
        await push.signIn(tester);
        await _pumpShell(tester, _deps(push));
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Turn on notifications?'), findsNothing);
        expect(push.adapter.requestCalls, 0);
      });
    }

    testWidgets('no PushNotificationService above (page tests): nothing',
        (tester) async {
      await pumpAccount(tester, AccountTestDeps(), _shell);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('shell'), findsOneWidget);
      expect(find.text('Turn on notifications?'), findsNothing);
    });
  });

  group('account page: phone notifications', () {
    testWidgets('allowed: row says On, no hint; tap opens the settings',
        (tester) async {
      final push = _Push(status: PushPermission.granted);
      await pumpAccount(tester, _deps(push), const AccountPage());
      await _scrollToAppSection(tester);
      final row = find.byKey(const Key('account_push'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('On')),
          findsOneWidget);
      expect(find.byKey(const Key('account_push_off_hint')), findsNothing);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(push.settingsOpened, 1);
      expect(push.adapter.requestCalls, 0);
    });

    testWidgets('refused once: Off + hint; the row asks the phone again',
        (tester) async {
      final push = _Push(status: PushPermission.denied);
      await pumpAccount(tester, _deps(push), const AccountPage());
      await _scrollToAppSection(tester);
      final row = find.byKey(const Key('account_push'));
      expect(find.descendant(of: row, matching: find.text('Off')),
          findsOneWidget);
      expect(find.byKey(const Key('account_push_off_hint')), findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(push.adapter.requestCalls, 1);
      // Granted now: On, hint gone.
      expect(find.descendant(of: row, matching: find.text('On')),
          findsOneWidget);
      expect(find.byKey(const Key('account_push_off_hint')), findsNothing);
    });

    testWidgets('refused for good: the hint opens the phone settings',
        (tester) async {
      final push = _Push(status: PushPermission.blocked);
      await pumpAccount(tester, _deps(push), const AccountPage());
      await _scrollToAppSection(tester);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(push.settingsOpened, 1);
      await tester.tap(find.byKey(const Key('account_push')));
      await tester.pumpAndSettle();
      expect(push.settingsOpened, 2);
      expect(push.adapter.requestCalls, 0);
    });

    testWidgets('re-reads the permission when the app resumes',
        (tester) async {
      final push = _Push(status: PushPermission.blocked);
      await pumpAccount(tester, _deps(push), const AccountPage());
      await _scrollToAppSection(tester);
      expect(find.byKey(const Key('account_push_off_hint')), findsOneWidget);
      push.adapter.status = PushPermission.granted; // turned on in settings
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account_push_off_hint')), findsNothing);
    });

    testWidgets('push unavailable in this build: no row, no hint',
        (tester) async {
      final push = _Push(available: false);
      await pumpAccount(tester, _deps(push), const AccountPage());
      await _scrollToAppSection(tester);
      expect(find.byKey(const Key('account_push')), findsNothing);
      expect(find.byKey(const Key('account_push_off_hint')), findsNothing);
    });
  });

  group('goldens', () {
    setUpAll(cust.loadPlexFont);

    final variants = [
      (en, ThemeMode.light, 'en_ltr'),
      (ar, ThemeMode.light, 'ar_rtl'),
      (en, ThemeMode.dark, 'dark_en_ltr'),
    ];
    for (final (locale, mode, dir) in variants) {
      testWidgets('GOLDEN push prompt $dir', (tester) async {
        final push = _Push();
        await push.signIn(tester);
        final deps = _deps(push);
        await deps.theme.setThemeMode(mode);
        await _pumpShell(tester, deps, locale: locale);
        expect(tester.takeException(), isNull);
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/push_prompt_${dir}_360x800.png'));
      });

      testWidgets('GOLDEN account push off $dir', (tester) async {
        final push = _Push(status: PushPermission.blocked);
        final deps = _deps(push);
        await deps.theme.setThemeMode(mode);
        await pumpAccount(tester, deps, const AccountPage(), locale: locale);
        await _scrollToAppSection(tester);
        expect(tester.takeException(), isNull);
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/push_account_off_${dir}_360x800.png'));
      });
    }
  });
}
