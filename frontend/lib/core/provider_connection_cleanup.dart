import 'package:flutter/widgets.dart';

/// Mixin for [State] objects that drive a live connection owned by an
/// app-lifetime [ChangeNotifier] (WebSocket subscriptions, SSE streams,
/// reconnect timers).
///
/// The historical bug this exists to prevent (QA audit A6): tearing the
/// connection down from `dispose()` via a post-frame callback guarded by
/// `if (mounted)`. After [State.dispose] runs, [mounted] is always false,
/// so a guard written that way makes the cleanup callback dead code and the
/// provider's socket, stream subscription, and auto-reconnect timer survive
/// the screen forever.
///
/// Usage: while [context] is still valid (e.g. inside the initState
/// post-frame callback), capture the provider and register its teardown:
///
/// ```dart
/// WidgetsBinding.instance.addPostFrameCallback((_) {
///   if (!mounted) return;
///   addConnectionTeardown(context.read<ChatProvider>().disconnect);
/// });
/// ```
///
/// Registered closures run exactly once when the State is disposed,
/// deferred to the end of the current frame. Deferral keeps
/// `notifyListeners()` out of element-tree finalization (marking widgets
/// dirty mid-teardown is illegal during build-phase disposal), while the
/// unconditional scheduling guarantees execution regardless of mounted
/// state.
mixin ProviderConnectionCleanup<T extends StatefulWidget> on State<T> {
  final List<VoidCallback> _connectionTeardowns = <VoidCallback>[];
  bool _teardownsRun = false;

  /// Registers a teardown closure to run when this State is disposed.
  ///
  /// Must be called while the element is mounted (asserted).
  void addConnectionTeardown(VoidCallback teardown) {
    assert(mounted, 'addConnectionTeardown called after unmount');
    assert(!_teardownsRun);
    _connectionTeardowns.add(teardown);
  }

  @override
  void dispose() {
    if (!_teardownsRun) {
      _teardownsRun = true;
      final teardowns = List<VoidCallback>.of(_connectionTeardowns);
      _connectionTeardowns.clear();
      // No mounted check here — that is precisely the bug class this mixin
      // exists for. Post-frame callbacks always execute at the end of the
      // frame in which they are scheduled; widget disposal only ever happens
      // during a frame, so this is guaranteed to run exactly once.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final teardown in teardowns) {
          teardown();
        }
      });
    }
    super.dispose();
  }
}
