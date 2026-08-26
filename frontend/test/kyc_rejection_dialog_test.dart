import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/widgets/info_alert_dialog.dart';
import 'package:frontend/widgets/kyc_rejection_dialog_host.dart';
import 'package:provider/provider.dart';

/// ADR-0021: KYC rejection outcome popup path.
///
/// Covers (1) the NotificationsProvider emitting `kyc_rejected` SSE events on
/// the [NotificationsProvider.kycRejectionStream], and (2) the
/// [KycRejectionDialogHost] presenting an informational dialog with the
/// rejection reason for the targeted user only.

class _RecordingSseSource {
  final List<StreamController<SSEModel>> controllers = [];

  Stream<SSEModel> call({
    required SSERequestType method,
    required String url,
    required Map<String, String> header,
  }) {
    final c = StreamController<SSEModel>.broadcast(sync: true);
    controllers.add(c);
    return c.stream;
  }

  void emit(String json) {
    controllers.first.add(SSEModel(event: 'notification', data: json));
  }
}

class _StubAuthProvider extends AuthProvider {
  _StubAuthProvider(super.apiClient);

  @override
  bool get isAuthenticated => true;

  @override
  UserProfile? get user => UserProfile(
        id: 'target-user',
        email: 'target@test.local',
        username: 'targeted',
        role: 'employee',
      );

  @override
  String? get token => 'token-kyc-test';
}

Widget _hostedApp({
  required NotificationsProvider notifications,
  required AuthProvider auth,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<NotificationsProvider>.value(value: notifications),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // The host sits below the root Navigator as route content, so dialogs
      // surfaced from its own context resolve against this navigator.
      home: KycRejectionDialogHost(
        child: Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationsProvider kyc_rejected emission', () {
    test('emits kyc_rejected notifications on kycRejectionStream', () async {
      final source = _RecordingSseSource();
      final provider =
          NotificationsProvider(ApiClient(), sseStreamSource: source.call);

      final received = <NotificationModel>[];
      final sub = provider.kycRejectionStream.listen(received.add);

      provider.initSse('token-stream');
      source.emit(
          '{"id":"n-rej-1","type":"kyc_rejected","tenant_id":"t-1","user_id":"target-user","title":"Verification rejected","body":"Your KYE verification was rejected. Reason: selfie mismatch"}');

      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received.first.type, 'kyc_rejected');
      expect(received.first.userId, 'target-user');
      expect(received.first.body, contains('selfie mismatch'));
      expect(provider.notifications.length, 1);

      // Other outcome types must not hit the stream.
      source.emit(
          '{"id":"n-ok-1","type":"kyc_approved","tenant_id":"t-1","user_id":"target-user","title":"ok","body":"approved"}');
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));

      await sub.cancel();
      provider.dispose();
    });

    test('parses optional user_id into NotificationModel', () {
      final withUser = NotificationModel.fromJson({
        'id': 'a',
        'type': 'kyc_rejected',
        'user_id': 'u-1',
        'title': 't',
        'body': 'b',
      });
      expect(withUser.userId, 'u-1');

      final withoutUser = NotificationModel.fromJson({
        'id': 'b',
        'type': 'job_alert',
        'title': 't',
        'body': 'b',
      });
      expect(withoutUser.userId, isNull);
    });
  });

  group('KycRejectionDialogHost', () {
    testWidgets('shows rejection dialog for the targeted user', (tester) async {
      final source = _RecordingSseSource();
      final notifications =
          NotificationsProvider(ApiClient(), sseStreamSource: source.call);
      final auth = _StubAuthProvider(ApiClient());

      await tester
          .pumpWidget(_hostedApp(notifications: notifications, auth: auth));
      await tester.pumpAndSettle();

      notifications.initSse('token-host-test');
      source.emit(
          '{"id":"n-1","type":"kyc_rejected","tenant_id":"t-1","user_id":"target-user","title":"Verification rejected","body":"Your KYE verification was rejected. Reason: blurry document"}');
      await tester.pumpAndSettle();

      expect(find.byType(InfoAlertDialog), findsOneWidget);
      expect(find.text('Verification Rejected'), findsOneWidget);
      expect(find.textContaining('blurry document'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('does not show dialog when targeted at another user',
        (tester) async {
      final source = _RecordingSseSource();
      final notifications =
          NotificationsProvider(ApiClient(), sseStreamSource: source.call);
      final auth = _StubAuthProvider(ApiClient());

      await tester
          .pumpWidget(_hostedApp(notifications: notifications, auth: auth));
      await tester.pumpAndSettle();

      notifications.initSse('token-host-test');
      source.emit(
          '{"id":"n-2","type":"kyc_rejected","tenant_id":"t-1","user_id":"someone-else","title":"Verification rejected","body":"Your KYE verification was rejected. Reason: other user"}');
      await tester.pumpAndSettle();

      expect(find.byType(InfoAlertDialog), findsNothing);
    });

    testWidgets('InfoAlertDialog acknowledges and dismisses', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => InfoAlertDialog.show(
                  context,
                  title: 'Verification Rejected',
                  message: 'Reason text',
                  ackLabel: 'Close',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(InfoAlertDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(InfoAlertDialog), findsNothing);
    });
  });
}
