import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Platforms the push code supports. Android today; iOS only needs its
/// Firebase config, an APNs key and the Xcode capabilities
/// (docs/PUSH.md, "iOS later"). Desktop and web have no push.
bool get pushPlatformSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Runs in a background isolate for each push that arrives while the
/// app is in the background or killed. Must stay top-level (or static).
///
/// Every push the server sends has a `notification` part, so the system
/// shows it itself on `qd_default` and a tap opens the app
/// (`getInitialMessage` / `onMessageOpenedApp` → the role-checked links).
/// Nothing to do here; it is registered so a later data-only push has a
/// place to land, and must not touch the UI or app state.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {}

/// Starts Firebase for push before the app runs (PUSH-FCM). Returns
/// whether push can work in this build.
///
/// Guarded: a build without `google-services.json` (or, on iOS,
/// `GoogleService-Info.plist`), an unsupported platform or any Firebase
/// error leaves push off with exactly one log line; the app works the same
/// otherwise. [initializeApp], [registerBackgroundHandler] and [supported]
/// are for tests.
Future<bool> initPushFirebase({
  Future<Object?> Function()? initializeApp,
  void Function()? registerBackgroundHandler,
  bool? supported,
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (!(supported ?? pushPlatformSupported)) {
    debugPrint('[PUSH] push disabled: not supported on this platform');
    return false;
  }
  try {
    await (initializeApp ?? Firebase.initializeApp)().timeout(timeout);
    (registerBackgroundHandler ??
        () => FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler))();
    debugPrint('[PUSH] push enabled');
    return true;
  } catch (e) {
    debugPrint('[PUSH] push disabled: Firebase not configured in this build '
        '($e)');
    return false;
  }
}
