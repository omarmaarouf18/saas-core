import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api_client.dart';
import 'local_notifications.dart';

/// Whether the phone may show this app's notifications (PUSH-FCM).
enum PushPermission {
  /// Not asked yet (Android 13+ / iOS).
  notDetermined,

  /// Allowed (also Android 12 and older, where nothing is asked).
  granted,

  /// Refused once; the system dialog may still be shown again.
  denied,

  /// Refused for good: only the phone's settings can turn it on.
  blocked,

  /// No push in this build or on this phone (no Firebase config, desktop,
  /// web).
  unavailable,
}

/// Abstract adapter for FCM token retrieval & message listening.
/// Allows swapping with a mock implementation in unit/widget tests.
abstract class PushMessagingAdapter {
  /// False when Firebase is not initialized (no config in this build).
  bool get available;
  Future<String?> getToken();
  Future<void> deleteToken();

  /// Calls [callback] with each new token FCM issues for this install.
  void onTokenRefresh(void Function(String token) callback);
  Future<PushPermission> permissionStatus();

  /// Shows the system permission dialog where it still can.
  Future<PushPermission> requestPermission();
}

/// Default implementation backed by the real `firebase_messaging` plugin.
///
/// When Firebase has not been initialized (no `google-services.json` in
/// the build, so `Firebase.initializeApp()` failed at startup; see
/// `push_setup.dart`), every method degrades to a safe no-op instead of
/// registering fake tokens — push is simply unavailable in that build.
class DefaultPushMessagingAdapter implements PushMessagingAdapter {
  StreamSubscription<String>? _refreshSubscription;

  @override
  bool get available {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      if (!available) {
        debugPrint(
            '[FCM] Firebase is not initialized; skipping device token retrieval');
        return null;
      }
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      // No Google Play services, no network: push stays off on this phone.
      debugPrint('FCM getToken error: $e');
      return null;
    }
  }

  @override
  Future<void> deleteToken() async {
    try {
      if (!available) {
        debugPrint('[FCM] Firebase is not initialized; nothing to delete');
        return;
      }
      await FirebaseMessaging.instance.deleteToken();
      debugPrint('[FCM] FCM token deleted');
    } catch (e) {
      debugPrint('FCM deleteToken error: $e');
    }
  }

  @override
  void onTokenRefresh(void Function(String token) callback) {
    if (!available) return;
    _refreshSubscription?.cancel();
    _refreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen(callback);
  }

  static PushPermission _of(NotificationSettings s) =>
      switch (s.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          PushPermission.granted,
        AuthorizationStatus.denied => PushPermission.denied,
        AuthorizationStatus.deniedPermanently => PushPermission.blocked,
        AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      };

  @override
  Future<PushPermission> permissionStatus() async {
    if (!available) return PushPermission.unavailable;
    try {
      return _of(await FirebaseMessaging.instance.getNotificationSettings());
    } catch (e) {
      debugPrint('[FCM] permission status failed: $e');
      return PushPermission.unavailable;
    }
  }

  @override
  Future<PushPermission> requestPermission() async {
    if (!available) return PushPermission.unavailable;
    try {
      return _of(await FirebaseMessaging.instance.requestPermission());
    } catch (e) {
      debugPrint('[FCM] permission request failed: $e');
      return PushPermission.unavailable;
    }
  }
}

/// Remembers that the in-app "turn on notifications" prompt was answered,
/// so it is shown once. Sign-out clears it with the rest of the app's
/// secure storage; the phone itself never shows its dialog after a
/// permanent refusal anyway.
abstract class PushPromptMemory {
  Future<bool> answered();
  Future<void> markAnswered();
}

class SecureStoragePushPromptMemory implements PushPromptMemory {
  const SecureStoragePushPromptMemory(
      [this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'push_prompt_answered';

  @override
  Future<bool> answered() async {
    try {
      return await _storage.read(key: _key) == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markAnswered() async {
    try {
      await _storage.write(key: _key, value: 'true');
    } catch (e) {
      debugPrint('[PUSH] prompt answer not saved: $e');
    }
  }
}

/// Service managing FCM device token registration with auth-service and
/// the notification permission (PUSH-FCM).
///
/// Nothing here throws to the caller or blocks sign-in: push errors are
/// logged and push stays off.
class PushNotificationService extends ChangeNotifier {
  final ApiClient apiClient;
  final PushMessagingAdapter adapter;
  final PushPromptMemory promptMemory;

  /// Opens the phone's notification settings for this app.
  final Future<bool> Function() _openSettings;

  /// Upper bound for each token fetch and each auth-service call.
  final Duration timeout;
  String? _currentToken;
  bool _signedIn = false;
  bool _refreshListening = false;
  PushPermission _permission = PushPermission.unavailable;
  bool _promptAnswered = false;

  PushNotificationService({
    required this.apiClient,
    PushMessagingAdapter? adapter,
    PushPromptMemory? promptMemory,
    Future<bool> Function()? openSettings,
    this.timeout = const Duration(seconds: 15),
  })  : adapter = adapter ?? DefaultPushMessagingAdapter(),
        promptMemory = promptMemory ?? const SecureStoragePushPromptMemory(),
        _openSettings =
            openSettings ?? (() => PluginLocalNotifier().openAppSettings());

  String? get currentToken => _currentToken;

  /// Push works in this build (Firebase initialized).
  bool get available => adapter.available;

  PushPermission get permission => _permission;

  /// Offer the in-app prompt: push works, the phone has not been asked and
  /// the prompt was not answered before.
  bool get shouldOfferPrompt =>
      available &&
      _permission == PushPermission.notDetermined &&
      !_promptAnswered;

  /// After sign-in (login, OTP, session restore): follows token refreshes,
  /// reads the permission and registers the token. Never throws; sign-in
  /// does not wait for it.
  Future<void> onSignedIn() async {
    _signedIn = true;
    try {
      if (!available) return;
      if (!_refreshListening) {
        _refreshListening = true;
        adapter.onTokenRefresh(_onTokenRefresh);
      }
      _promptAnswered = await promptMemory.answered();
      await refreshPermission();
      await registerDeviceToken();
    } catch (e) {
      debugPrint('[FCM] push setup after sign-in failed: $e');
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    if (!_signedIn || token.isEmpty || token == _currentToken) return;
    try {
      await apiClient
          .registerDeviceToken(token: token, platform: _platformName)
          .timeout(timeout);
      _currentToken = token;
      debugPrint('[FCM] Refreshed device token registered');
    } catch (e) {
      debugPrint('[FCM] Failed to register refreshed token: $e');
    }
  }

  static String get _platformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Registers the client's FCM device token with auth-service on login/signup or startup.
  Future<bool> registerDeviceToken() async {
    try {
      final token = await adapter.getToken().timeout(timeout);
      if (token == null || token.isEmpty) {
        debugPrint('[FCM] No FCM token available to register');
        return false;
      }
      _currentToken = token;

      await apiClient
          .registerDeviceToken(token: token, platform: _platformName)
          .timeout(timeout);
      // The token itself is never logged.
      debugPrint('[FCM] Device token registered successfully');
      return true;
    } catch (e) {
      debugPrint('[FCM] Failed to register device token: $e');
      return false;
    }
  }

  /// Unregisters the client's FCM device token on logout, and deletes it
  /// on the phone so a refresh cannot re-register it.
  Future<bool> unregisterDeviceToken() async {
    _signedIn = false;
    var ok = true;
    try {
      if (_currentToken != null && _currentToken!.isNotEmpty) {
        await apiClient
            .unregisterDeviceToken(token: _currentToken)
            .timeout(timeout);
      } else {
        await apiClient.unregisterDeviceToken().timeout(timeout);
      }
      debugPrint('[FCM] Device token unregistered successfully');
    } catch (e) {
      debugPrint('[FCM] Failed to unregister device token: $e');
      ok = false;
    }
    await adapter.deleteToken();
    _currentToken = null;
    return ok;
  }

  /// The session ended without a sign-out call (expired, refresh failed):
  /// the server cannot be told, so the token is deleted on the phone. FCM
  /// then answers the server's next send with UNREGISTERED and
  /// notification-service drops the stale token, so no more pushes reach
  /// this signed-out phone.
  Future<void> forgetLocalToken() async {
    _signedIn = false;
    _currentToken = null;
    try {
      await adapter.deleteToken();
    } catch (e) {
      debugPrint('[FCM] local token not deleted: $e');
    }
  }

  /// Re-reads the permission (e.g. back from the phone's settings).
  Future<PushPermission> refreshPermission() async {
    final p = available
        ? await adapter.permissionStatus()
        : PushPermission.unavailable;
    _setPermission(p);
    return p;
  }

  /// Asks the phone (system dialog where it still can). Marks the in-app
  /// prompt answered; on a grant, registers the token again.
  Future<PushPermission> requestPermission() async {
    await markPromptAnswered();
    if (!available) return PushPermission.unavailable;
    final p = await adapter.requestPermission();
    _setPermission(p);
    if (p == PushPermission.granted && _signedIn) {
      await registerDeviceToken();
    }
    return p;
  }

  /// Opens the phone's notification settings for this app (the only way
  /// back after a permanent refusal).
  Future<bool> openSettings() => _openSettings();

  /// The in-app prompt was answered ("Not now" included): not shown again.
  Future<void> markPromptAnswered() async {
    if (_promptAnswered) return;
    _promptAnswered = true;
    notifyListeners();
    await promptMemory.markAnswered();
  }

  void _setPermission(PushPermission p) {
    if (p == _permission) return;
    _permission = p;
    notifyListeners();
  }
}
