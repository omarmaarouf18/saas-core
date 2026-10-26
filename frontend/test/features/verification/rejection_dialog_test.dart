import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/verification/rejection_dialog_host.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/ui/qd_theme.dart';
import 'package:provider/provider.dart';

/// ADR-0021: the verification-rejected popup. (1) NotificationsProvider puts
/// `kyc_rejected` SSE events on [NotificationsProvider.kycRejectionStream];
/// (2) [VerificationRejectedHost] shows the redesigned dialog with the
/// reviewer's reason, for the targeted user only.

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
  Locale locale = const Locale('en'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<NotificationsProvider>.value(value: notifications),
    ],
    child: MaterialApp(
      theme: qdLightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const VerificationRejectedHost(
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

  test('reason from the auth-service body', () {
    expect(
        rejectionReason(
            'Your KYB verification was rejected. Reason: blurry document'),
        'blurry document');
    expect(rejectionReason('Your KYE verification was rejected. Reason: '),
        isNull);
    expect(rejectionReason('Rejected'), isNull);
  });

  group('VerificationRejectedHost', () {
    Future<(_RecordingSseSource, NotificationsProvider)> pumpHost(
        WidgetTester tester,
        {Locale locale = const Locale('en')}) async {
      final source = _RecordingSseSource();
      final notifications =
          NotificationsProvider(ApiClient(), sseStreamSource: source.call);
      await tester.pumpWidget(_hostedApp(
          notifications: notifications,
          auth: _StubAuthProvider(ApiClient()),
          locale: locale));
      await tester.pumpAndSettle();
      notifications.initSse('token-host-test');
      return (source, notifications);
    }

    testWidgets('targeted user: the reason, the next step, close',
        (tester) async {
      final (source, _) = await pumpHost(tester);
      source.emit(
          '{"id":"n-1","type":"kyc_rejected","tenant_id":"t-1","user_id":"target-user","title":"Verification rejected","body":"Your KYE verification was rejected. Reason: blurry document"}');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vrf_rejected_dialog')), findsOneWidget);
      expect(find.text("Your documents weren't accepted"), findsOneWidget);
      expect(find.text("Reviewer's note: blurry document"), findsOneWidget);
      expect(find.text('Fix my documents'), findsOneWidget);

      await tester.tap(find.byKey(const Key('vrf_rejected_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vrf_rejected_dialog')), findsNothing);
    });

    testWidgets('no reason in the body: the no-reason note, Arabic',
        (tester) async {
      final (source, _) = await pumpHost(tester, locale: const Locale('ar'));
      source.emit(
          '{"id":"n-3","type":"kyc_rejected","tenant_id":"t-1","user_id":"target-user","title":"Verification rejected","body":"Rejected"}');
      await tester.pumpAndSettle();
      expect(find.text('مستنداتك ما اتقبلتش'), findsOneWidget);
      expect(find.text('مفيش سبب مكتوب. كلّم الدعم لو مش متأكد تغيّر إيه.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('another user: no dialog', (tester) async {
      final (source, _) = await pumpHost(tester);
      source.emit(
          '{"id":"n-2","type":"kyc_rejected","tenant_id":"t-1","user_id":"someone-else","title":"Verification rejected","body":"Your KYE verification was rejected. Reason: other user"}');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vrf_rejected_dialog')), findsNothing);
    });
  });
}
