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

  bool _isLoadingHistory = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;

  /// Broadcast stream of KYC/KYE rejection outcome notifications (ADR-0021).
  /// The app root listens to this to present an immediate in-app dialog with
  /// the rejection reason; the notification also lands in the normal list.
  final StreamController<NotificationModel> _kycRejectionController =
      StreamController<NotificationModel>.broadcast();

  Stream<NotificationModel> get kycRejectionStream =>
      _kycRejectionController.stream;

  List<NotificationModel> get notifications => _notifications;
  bool get isConnected => _isConnected;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;

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
    // Cold-start fetch alongside SSE connection
    fetchHistory();

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

              // ADR-0021: surface rejections for the immediate in-app dialog.
              if (notif.type == 'kyc_rejected' &&
                  !_kycRejectionController.isClosed) {
                _kycRejectionController.add(notif);
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
    _kycRejectionController.close();
    super.dispose();
  }

  Future<void> fetchHistory({bool refresh = false, int limit = 30}) async {
    if (_isLoadingHistory) return;
    _isLoadingHistory = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiClient.get(
        '/notifications/history',
        queryParams: {'limit': limit.toString()},
      );

      List<dynamic> rawList = [];
      if (response is Map && response['notifications'] is List) {
        rawList = response['notifications'] as List;
        _hasMore = response['has_more'] as bool? ?? (rawList.length == limit);
      } else if (response is List) {
        rawList = response;
        _hasMore = rawList.length == limit;
      }

      final fetched = rawList
          .map((item) =>
              NotificationModel.fromJson(item as Map<String, dynamic>))
          .toList();

      if (refresh) {
        _notifications.clear();
        _notifications.addAll(fetched);
      } else {
        for (final item in fetched) {
          final idx = _notifications.indexWhere((n) => n.id == item.id);
          if (idx == -1) {
            _notifications.add(item);
          } else {
            _notifications[idx].isRead = item.isRead;
          }
        }
      }
      _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('Error fetching notification history: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> loadMore({int limit = 30}) async {
    if (_isLoadingMore || !_hasMore || _notifications.isEmpty) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final oldest = _notifications.last.timestamp.toUtc().toIso8601String();
      final response = await apiClient.get(
        '/notifications/history',
        queryParams: {
          'limit': limit.toString(),
          'before': oldest,
        },
      );

      List<dynamic> rawList = [];
      if (response is Map && response['notifications'] is List) {
        rawList = response['notifications'] as List;
        _hasMore = response['has_more'] as bool? ?? (rawList.length == limit);
      } else if (response is List) {
        rawList = response;
        _hasMore = rawList.length == limit;
      }

      final fetched = rawList
          .map((item) =>
              NotificationModel.fromJson(item as Map<String, dynamic>))
          .toList();

      for (final item in fetched) {
        if (!_notifications.any((n) => n.id == item.id)) {
          _notifications.add(item);
        }
      }
      _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('Error loading more notifications: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> markAsRead(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    final prevRead = _notifications[idx].isRead;
    _notifications[idx].isRead = true;
    notifyListeners();

    try {
      await apiClient.post('/notifications/$id/read', {});
    } catch (e) {
      if (e is ApiClientException && e.statusCode == 404) {
        // Stale or already marked/removed on server; retain optimistic read state
        // and do not surface an intrusive error banner.
        return;
      }
      final rollIdx = _notifications.indexWhere((n) => n.id == id);
      if (rollIdx != -1) {
        _notifications[rollIdx].isRead = prevRead;
      }
      _error = friendlyErrorMessage(e);
      notifyListeners();
    }
  }

  Future<void> markAllAsRead() async {
    final previousStates = {for (final n in _notifications) n.id: n.isRead};
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();

    try {
      await apiClient.post('/notifications/read-all', {});
    } catch (e) {
      for (final n in _notifications) {
        if (previousStates.containsKey(n.id)) {
          n.isRead = previousStates[n.id]!;
        }
      }
      _error = friendlyErrorMessage(e);
      notifyListeners();
    }
  }

  Future<void> dismiss(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    final removed = _notifications.removeAt(idx);
    notifyListeners();

    try {
      await apiClient.delete('/notifications/$id');
    } catch (e) {
      if (e is ApiClientException && e.statusCode == 404) {
        // Stale or already removed on server; keep removed locally
        // and do not surface an intrusive error banner.
        return;
      }
      _notifications.insert(idx.clamp(0, _notifications.length), removed);
      _error = friendlyErrorMessage(e);
      notifyListeners();
    }
  }

  Future<void> clearAll() async {
    final backup = List<NotificationModel>.from(_notifications);
    _notifications.clear();
    notifyListeners();

    try {
      await apiClient.delete('/notifications');
    } catch (e) {
      _notifications.addAll(backup);
      _error = friendlyErrorMessage(e);
      notifyListeners();
    }
  }
}
