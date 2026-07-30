import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../models/notification_model.dart';

class NotificationsProvider extends ChangeNotifier {
  final ApiClient apiClient;

  final List<NotificationModel> _notifications = [];
  bool _isConnected = false;
  String? _error;

  List<NotificationModel> get notifications => _notifications;
  bool get isConnected => _isConnected;
  String? get error => _error;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  NotificationsProvider(this.apiClient);

  void initSse(String token) {
    if (_isConnected) return;

    try {
      final String sseUrl =
          '${apiClient.baseUrl}/notifications/stream?token=$token';

      SSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: sseUrl,
        header: {
          "Accept": "text/event-stream",
          "Cache-Control": "no-cache",
        },
      ).listen(
        (event) {
          _isConnected = true;
          _error = null;

          if (event.event == 'notification' && event.data != null) {
            try {
              final Map<String, dynamic> rawData = jsonDecode(event.data!);
              final notif = NotificationModel.fromJson(rawData);

              // Prevent duplicate notification entries
              if (!_notifications.any((n) => n.id == notif.id)) {
                _notifications.insert(0, notif);
                notifyListeners();
              }
            } catch (e) {
              debugPrint('Error parsing notification JSON: $e');
            }
          } else if (event.event == 'connected') {
            debugPrint('SSE successfully connected: ${event.data}');
            notifyListeners();
          }
        },
        onError: (e) {
          debugPrint('SSE stream error: $e');
          _isConnected = false;
          _error = friendlyErrorMessage(e);
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('SSE connection error: $e');
      _isConnected = false;
      _error = friendlyErrorMessage(e);
      notifyListeners();
    }
  }

  void unsubscribe() {
    if (!_isConnected) return;
    try {
      SSEClient.unsubscribeFromSSE();
    } catch (e) {
      debugPrint('Error unsubscribing from SSE: $e');
    }
    _isConnected = false;
    notifyListeners();
  }

  void markAsRead(String id) {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _notifications[idx].isRead = true;
      notifyListeners();
    }
  }

  void markAllAsRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void dismiss(String id) {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clearAll() {
    _notifications.clear();
    notifyListeners();
  }
}
