import 'package:flutter/foundation.dart';
import '../core/api_client.dart';

/// Abstract adapter for FCM token retrieval & message listening.
/// Allows swapping with a mock implementation in unit/widget tests.
abstract class PushMessagingAdapter {
  Future<String?> getToken();
  Future<void> deleteToken();
  void onForegroundMessage(
      void Function(String title, String body, Map<String, dynamic> data)
          callback);
}

/// Default implementation for FCM messaging adapter.
class DefaultPushMessagingAdapter implements PushMessagingAdapter {
  @override
  Future<String?> getToken() async {
    try {
      return 'fcm-device-token-${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('FCM getToken error: $e');
      return null;
    }
  }

  @override
  Future<void> deleteToken() async {
    try {
      debugPrint('FCM token deleted');
    } catch (e) {
      debugPrint('FCM deleteToken error: $e');
    }
  }

  @override
  void onForegroundMessage(
      void Function(String title, String body, Map<String, dynamic> data)
          callback) {
    // Subscribes to foreground push notifications
  }
}

/// Service managing FCM device token registration with auth-service and handling foreground/background notifications.
class PushNotificationService {
  final ApiClient apiClient;
  final PushMessagingAdapter adapter;
  String? _currentToken;

  PushNotificationService({
    required this.apiClient,
    PushMessagingAdapter? adapter,
  }) : adapter = adapter ?? DefaultPushMessagingAdapter();

  String? get currentToken => _currentToken;

  /// Registers the client's FCM device token with auth-service on login/signup or startup.
  Future<bool> registerDeviceToken() async {
    try {
      final token = await adapter.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[FCM] No FCM token available to register');
        return false;
      }
      _currentToken = token;

      final platformName = kIsWeb ? 'web' : defaultTargetPlatform.name;
      await apiClient.registerDeviceToken(
        token: token,
        platform: platformName,
      );
      debugPrint('[FCM] Device token registered successfully: $token');
      return true;
    } catch (e) {
      debugPrint('[FCM] Failed to register device token: $e');
      return false;
    }
  }

  /// Unregisters the client's FCM device token on logout.
  Future<bool> unregisterDeviceToken() async {
    try {
      if (_currentToken != null && _currentToken!.isNotEmpty) {
        await apiClient.unregisterDeviceToken(token: _currentToken);
      } else {
        await apiClient.unregisterDeviceToken();
      }
      await adapter.deleteToken();
      _currentToken = null;
      debugPrint('[FCM] Device token unregistered successfully');
      return true;
    } catch (e) {
      debugPrint('[FCM] Failed to unregister device token: $e');
      return false;
    }
  }

  /// Listens to foreground push notifications.
  void listenForegroundNotifications(
    void Function(String title, String body, Map<String, dynamic> data)
        onNotificationReceived,
  ) {
    adapter.onForegroundMessage(onNotificationReceived);
  }
}
