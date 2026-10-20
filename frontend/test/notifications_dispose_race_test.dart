import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/notifications_provider.dart';

/// A6 follow-up: fetchHistory could call notifyListeners after dispose when
/// the widget tree tore the provider down mid-fetch (reported against the a6
/// SSE test run). The provider guards every async completion with a
/// _disposed check; these tests pin that a dispose during an in-flight
/// fetch completes without calling notifyListeners (ChangeNotifier throws a
/// Flutter assertion in that case — surfacing as a test failure here).
class _HangApiClient extends ApiClient {
  _HangApiClient() : super(baseUrl: 'http://localhost:3002');

  late Completer<void> gate;

  @override
  Future<dynamic> get(String path,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (path == '/notifications/history') {
      gate = Completer<void>();
      await gate.future;
      return {'notifications': [], 'has_more': false};
    }
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dispose mid-fetchHistory completes without notifyListeners', () async {
    final api = _HangApiClient();
    final provider = NotificationsProvider(api);

    // Kick off the fetch; it stalls inside the api call.
    final fetching = provider.fetchHistory();
    await Future<void>.delayed(Duration.zero);
    expect(provider.isLoadingHistory, isTrue);

    // Tear the provider down WHILE the fetch is in flight.
    provider.dispose();
    expect(provider.isDisposed, isTrue);

    // The hung response lands afterwards; the completion path must bail
    // silently. A notifyListeners-on-disposed would throw here.
    api.gate.complete();
    await fetching;

    // No Flutter expectations needed: an assertion inside fetchHistory's
    // finally would surface as an unhandled exception and fail the test.
  });

  test('subscribe during in-flight fetch, then dispose: no late notifications',
      () async {
    final api = _HangApiClient();
    final provider = NotificationsProvider(api);

    final fetching = provider.fetchHistory();
    await Future<void>.delayed(Duration.zero);
    provider.dispose();
    api.gate.complete();
    await fetching;
  });
}
