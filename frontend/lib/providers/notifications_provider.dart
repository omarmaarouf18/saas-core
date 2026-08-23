import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../models/notification_model.dart';

class NotificationsProvider extends ChangeNotifier {
  final ApiClient apiClient;

  /// Injectable SSE stream source (QA audit A6). Defaults to the real
  /// `flutter_client_sse` client; tests inject a fake stream to observe
  /// subscription lifecycle without network access.
  final Stream<SSEModel> Function({
    required SSERequestType method,
    required String url,
    required Map<String, String> header,
  }) _sseStreamSource;

  final List<NotificationModel> _notifications = [];
  bool _isConnected = false;
  String? _error;
  StreamSubscription<SSEModel>? _sseSubscription;

  List<NotificationModel> get notifications => _notifications;
  bool get isConnected => _isConnected;

  /// Visible for tests: proves whether an underlying SSE subscription is
  /// currently held.
  bool get hasActiveSubscription => _sseSubscription != null;

  String? get error => _error;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  NotificationsProvider(
    this.apiClient, {
    Stream<SSEModel> Function({
      required SSERequestType method,
      required String url,
      required Map<String, String> header,
    })? sseStreamSource,
  }) : _sseStreamSource = sseStreamSource ?? SSEClient.subscribeToSSE;

  void initSse(String token) {
    // Already connected: nothing to do (guards against every MyApp rebuild
    // re-subscribing while healthy).
    if (_isConnected) return;

    try {
      final String sseUrl =
          '${apiClient.baseUrl}/notifications/stream?token=$token';

      // A6: the subscription is now stored and owned by this provider.
      // Previously the `.listen()` result was discarded, making it
      // impossible to cancel the stream; every re-init after a connection
      // error spawned a duplicate SSE HTTP connection that nothing could
      // ever close. Any stale subscription is cancelled BEFORE a new one is
      // created, so at most one underlying connection is ever held.
      _sseSubscription?.cancel();
      _sseSubscription = _sseStreamSource(
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
        onDone: () {
          _isConnected = false;
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
    // A6: unconditional teardown. The previous early-return
    // (`if (!_isConnected) return`) skipped cleanup whenever the socket had
    // errored before its first event — exactly the state in which a stale
    // underlying connection most needs releasing. Cancel our own
    // subscription first so no late events can arrive afterwards.
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _isConnected = false;
    try {
      SSEClient.unsubscribeFromSSE();
    } catch (e) {
      debugPrint('Error unsubscribing from SSE: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sseSubscription?.cancel();
    _sseSubscription = null;
    super.dispose();
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
