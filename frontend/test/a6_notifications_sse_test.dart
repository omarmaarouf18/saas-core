import 'dart:async';

import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';

/// QA audit A6 regression tests: NotificationsProvider SSE lifecycle.
///
/// Pre-fix, these behaviours were unobservable from outside the provider
/// because the `.listen()` subscription was discarded at the only call
/// site; the injectable `sseStreamSource` seam added by the fix makes the
/// subscription lifecycle directly assertable. The pre-fix defect is
/// documented via code-level audit evidence (unstored listen result +
/// `if (!_isConnected) return` early-return in unsubscribe()) in
/// docs/changelog/bug-fixes.md.

class _RecordingSseSource {
  int calls = 0;
  final List<StreamController<SSEModel>> controllers = [];

  Stream<SSEModel> call({
    required SSERequestType method,
    required String url,
    required Map<String, String> header,
  }) {
    calls++;
    final c = StreamController<SSEModel>.broadcast(sync: true);
    controllers.add(c);
    return c.stream;
  }

  bool get allCancelled =>
      controllers.every((c) => !c.hasListener || c.isClosed);
}

void main() {
  test('initSse subscribes exactly once and parses notification events', () {
    final source = _RecordingSseSource();
    final provider =
        NotificationsProvider(ApiClient(), sseStreamSource: source.call);

    provider.initSse('token-a6');
    expect(source.calls, 1);
    expect(provider.hasActiveSubscription, isTrue);

    source.controllers.first.add(SSEModel(
      event: 'notification',
      data: '{"id":"n-1","type":"jobs","title":"t","body":"b"}',
    ));
    expect(provider.notifications.length, 1);
    expect(provider.isConnected, isTrue);

    // A connected re-init must not spawn a second underlying stream.
    provider.initSse('token-a6');
    expect(source.calls, 1);
  });

  test(
      're-init after a stream error does not accumulate duplicate SSE '
      'connections', () {
    final source = _RecordingSseSource();
    final provider =
        NotificationsProvider(ApiClient(), sseStreamSource: source.call);

    provider.initSse('token-a6');
    source.controllers.first.addError(Exception('connection dropped'));
    expect(provider.isConnected, isFalse);

    // The old bug: MyApp rebuilds (theme/locale/auth changes) re-called
    // initSse whenever isConnected was false, opening a fresh SSE HTTP
    // connection while the previous one was still unclosed.
    provider.initSse('token-a6');
    expect(source.calls, 2, reason: 'previous stream must be torn down first');
    expect(provider.hasActiveSubscription, isTrue);
  });

  test('unsubscribe cancels even when the stream never connected', () {
    final source = _RecordingSseSource();
    final provider =
        NotificationsProvider(ApiClient(), sseStreamSource: source.call);

    provider.initSse('token-a6');
    // Error before any event arrived -> isConnected stays false. The old
    // early-return made unsubscribe() a no-op in precisely this state.
    source.controllers.first.addError(Exception('boom'));
    expect(provider.isConnected, isFalse);

    provider.unsubscribe();
    expect(provider.hasActiveSubscription, isFalse);
  });

  test('dispose cancels the held SSE subscription', () {
    final source = _RecordingSseSource();
    final provider =
        NotificationsProvider(ApiClient(), sseStreamSource: source.call);

    provider.initSse('token-a6');
    expect(provider.hasActiveSubscription, isTrue);

    provider.dispose();
    expect(provider.hasActiveSubscription, isFalse);
  });

  test('unsubscribe allows a clean later re-subscribe', () {
    final source = _RecordingSseSource();
    final provider =
        NotificationsProvider(ApiClient(), sseStreamSource: source.call);

    provider.initSse('token-a6');
    provider.unsubscribe();
    expect(provider.hasActiveSubscription, isFalse);

    provider.initSse('token-b');
    expect(source.calls, 2);
    expect(provider.hasActiveSubscription, isTrue);

    source.controllers.last.add(SSEModel(
      event: 'notification',
      data: '{"id":"n-2","type":"jobs","title":"t","body":"b"}',
    ));
    expect(provider.notifications.length, 1);
  });
}
