import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/map_tracking_provider.dart';

/// QA audit A6 regression tests: disposal correctness & connection teardown.
///
/// Every test measures an OBSERVABLE lifecycle event (provider disconnect
/// invocations, focus-node instance identity across rebuilds), never a
/// code-smell claim. The screen-level tests reproduce the exact leak: an
/// app-lifetime provider whose live WebSocket/reconnect machinery survives
/// its host screen being popped.

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



  // C9 waiting-notice indicator. Lives here (not in a map-themed file)
  // because this file owns the only CustomerJobMapScreen widget harness
  // (_buildL10nApp + _SpyMapTrackingProvider); there is no dedicated map
  // screen test file to extend.
}
