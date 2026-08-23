import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/map_tracking_provider.dart';
import 'package:frontend/screens/chat_screen.dart';
import 'package:frontend/screens/customer_job_map_screen.dart';
import 'package:frontend/screens/owner_fleet_map_screen.dart';
import 'package:frontend/widgets/otp_pin_input.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// QA audit A6 regression tests: disposal correctness & connection teardown.
///
/// Every test measures an OBSERVABLE lifecycle event (provider disconnect
/// invocations, focus-node instance identity across rebuilds), never a
/// code-smell claim. The screen-level tests reproduce the exact leak: an
/// app-lifetime provider whose live WebSocket/reconnect machinery survives
/// its host screen being popped.

Widget _buildL10nApp({required Widget child}) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

class _SpyChatProvider extends ChatProvider {
  int disconnectCount = 0;

  _SpyChatProvider(super.apiClient);

  @override
  void disconnect() {
    disconnectCount++;
    super.disconnect();
  }
}

class _SpyMapTrackingProvider extends MapTrackingProvider {
  int disconnectCount = 0;

  _SpyMapTrackingProvider(super.apiClient);

  @override
  Future<void> hydrateOwnerFleet(String ownerToken) async {}

  @override
  Future<void> hydrateCustomerJob(String jobId, String userToken) async {}

  @override
  void connectAndSubscribe(String channel, String token,
      {WebSocketChannel? customChannel}) {}

  @override
  void updateMarkerManually(EmployeeMarkerData data) {}

  @override
  void disconnect() {
    disconnectCount++;
    super.disconnect();
  }
}

void main() {
  group('A6: post-dispose teardown safety', () {
    // The screen-level mixin defers disconnect() to end-of-frame, which can
    // land AFTER an ancestor ChangeNotifierProvider disposed the provider
    // (same-frame unmount, e.g. logout). disconnect() past disposal must be
    // a silent no-op, not a debugAssertNotDisposed crash.
    test('ChatProvider.disconnect after dispose is a safe no-op', () {
      final chat = ChatProvider(ApiClient());
      chat.dispose();
      chat.disconnect();
    });

    test('MapTrackingProvider.disconnect after dispose is a safe no-op', () {
      final map = MapTrackingProvider(ApiClient());
      map.dispose();
      map.disconnect();
    });
  });

  group('A6: live-connection teardown on screen disposal', () {
    testWidgets(
        'chat screen pop disconnects the app-lifetime ChatProvider socket',
        (tester) async {
      final chat = _SpyChatProvider(ApiClient());
      final auth = AuthProvider(ApiClient());

      await tester.pumpWidget(
        _buildL10nApp(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<ChatProvider>.value(value: chat),
            ],
            child: const ChatScreen(jobId: 'job-a6-chat'),
          ),
        ),
      );
      await tester.pump();
      expect(chat.disconnectCount, 0,
          reason: 'pre-condition: connected while screen is open');

      await tester.pumpWidget(
        _buildL10nApp(child: const SizedBox.shrink()),
      );
      await tester.pump();

      expect(chat.disconnectCount, 1,
          reason:
              'leaving the chat screen MUST close the WebSocket subscription '
              'and cancel the auto-reconnect timer');
    });

    testWidgets(
        'customer job map screen pop disconnects MapTrackingProvider stream',
        (tester) async {
      final map = _SpyMapTrackingProvider(ApiClient());

      await tester.pumpWidget(
        _buildL10nApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: map,
            child: const CustomerJobMapScreen(jobId: 'job-a6', token: 't'),
          ),
        ),
      );
      await tester.pump();
      expect(map.disconnectCount, 0);

      await tester.pumpWidget(
        _buildL10nApp(child: const SizedBox.shrink()),
      );
      await tester.pump();

      expect(map.disconnectCount, 1,
          reason: 'the job-location WebSocket and its reconnect timer must be '
              'released when the tracking map is closed');
    });

    testWidgets(
        'owner fleet map screen pop disconnects MapTrackingProvider stream',
        (tester) async {
      final map = _SpyMapTrackingProvider(ApiClient());

      await tester.pumpWidget(
        _buildL10nApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: map,
            child: const OwnerFleetMapScreen(ownerId: 'owner-a6', token: 't'),
          ),
        ),
      );
      await tester.pump();
      expect(map.disconnectCount, 0);

      await tester.pumpWidget(
        _buildL10nApp(child: const SizedBox.shrink()),
      );
      await tester.pump();

      expect(map.disconnectCount, 1);
    });
  });

  group('A6: OtpPinInput auxiliary focus-node lifecycle', () {
    testWidgets(
        'auxiliary focus nodes are reused across rebuilds, not '
        'reallocated per build', (tester) async {
      Widget otp() => OtpPinInput(onChanged: (_) {});

      await tester.pumpWidget(
          _buildL10nApp(child: Scaffold(body: Center(child: otp()))));
      final FocusNode before = tester
          .widget<KeyboardListener>(find.byType(KeyboardListener).first)
          .focusNode;

      // Force a rebuild of the same widget subtree (as happens on every
      // keystroke via the parent's setState -> onChanged).
      await tester.pumpWidget(
          _buildL10nApp(child: Scaffold(body: Center(child: otp()))));
      final FocusNode after = tester
          .widget<KeyboardListener>(find.byType(KeyboardListener).first)
          .focusNode;

      expect(identical(before, after), isTrue,
          reason:
              '_buildPinBox creates FocusNode() inline per box per build; each '
              'keystroke-driven rebuild allocates 6 fresh FocusNodes that are '
              'never disposed');
    });
  });
}
