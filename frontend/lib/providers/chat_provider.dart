import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/error_messages.dart';
import '../models/chat_message.dart';

class ChatProvider extends ChangeNotifier {
  final ApiClient apiClient;

  IOWebSocketChannel? _webSocketChannel;
  StreamSubscription? _webSocketSubscription;

  List<ChatMessage> _messages = [];
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isLoading = false;
  String? _error;
  String? _subscriptionError;

  // Reconnection state
  Timer? _reconnectTimer;
  int _reconnectDelaySeconds = 2;
  String? _currentJobId;
  String? _currentToken;

  // A6: guards notifyListeners() after disposal — the screen-level teardown
  // mixin defers disconnect() to the end of the frame, which can land AFTER
  // an ancestor ChangeNotifierProvider has disposed this provider (same-frame
  // unmount, e.g. logout swapping the whole tree).
  bool _isDisposed = false;

  List<ChatMessage> get messages => _messages;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get subscriptionError => _subscriptionError;

  ChatProvider(this.apiClient);

  Future<void> fetchHistory(String jobId, String token) async {
    _error = null;
    _subscriptionError = null;
    _messages = [];
    notifyListeners();

    try {
      final res = await apiClient.get(
        '/chat/history',
        queryParams: {
          'channel': 'job:$jobId',
          'token': token,
        },
      );

      if (res is List) {
        _messages = res
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching chat history: $e');
      _error = friendlyErrorMessage(e);
      if (e is ApiClientException &&
          (e.statusCode == 401 || e.statusCode == 403)) {
        _subscriptionError = "not authorized for this channel";
      }
    } finally {
      notifyListeners();
    }
  }

  void connectAndSubscribe(String jobId, String token) {
    _currentJobId = jobId;
    _currentToken = token;
    _reconnectTimer?.cancel();

    _connect();
  }

  void _connect() {
    if (_currentToken == null || _currentJobId == null) return;

    _isConnecting = true;
    _isConnected = false;
    _error = null;
    _subscriptionError = null;
    notifyListeners();

    final baseWs = apiClient.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final wsUrl = '$baseWs/chat/ws?token=$_currentToken';

    try {
      _webSocketSubscription?.cancel();
      _webSocketChannel?.sink.close();

      _webSocketChannel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {
          'Origin': chatWsOrigin
        }, // see core/constants.dart (CHAT_WS_ORIGIN)
      );

      // Immediately send subscribe action on connection
      _subscribe('job:$_currentJobId');

      _webSocketSubscription = _webSocketChannel!.stream.listen(
        (data) {
          _handleIncomingData(data);
        },
        onError: (err) {
          debugPrint('Chat WebSocket error: $err');
          _isConnected = false;
          _isConnecting = false;
          _error = friendlyErrorMessage(err);
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _isConnecting = false;
          notifyListeners();
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('Chat WebSocket connection failed: $e');
      _isConnecting = false;
      _isConnected = false;
      _error = friendlyErrorMessage(e);
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _handleIncomingData(dynamic data) {
    try {
      final Map<String, dynamic> map = jsonDecode(data.toString());
      final type = map['type'];

      if (type == 'subscribed') {
        _isConnected = true;
        _isConnecting = false;
        _reconnectDelaySeconds = 2; // Reset reconnect delay on success
        _subscriptionError = null;
        notifyListeners();
      } else if (type == 'error') {
        final errorVal = map['error'];
        final messageVal = map['message'] ?? errorVal;

        if (errorVal == 'not authorized for this channel') {
          _subscriptionError = 'not authorized for this channel';
          // Since it's a security/auth rejection, do not auto-reconnect
          _reconnectTimer?.cancel();
        } else {
          _error = messageVal;
        }
        _isConnecting = false;
        notifyListeners();
      } else if (type == 'message' || map['content'] != null) {
        final msg = ChatMessage.fromJson(map);
        // Avoid duplicating messages already fetched via history
        final isDuplicate = _messages.any((m) =>
            m.senderId == msg.senderId &&
            m.content == msg.content &&
            m.type == msg.type);
        if (!isDuplicate) {
          _messages.add(msg);
          notifyListeners();
        }
      }
    } catch (e) {
      // Gracefully handle parsing failures without crashing
      debugPrint("Failed to parse websocket data: $e");
    }
  }

  void _subscribe(String channel) {
    _webSocketChannel?.sink.add(jsonEncode({
      'action': 'subscribe',
      'channel': channel,
    }));
  }

  Future<void> sendMessage(String content) async {
    if (_webSocketChannel == null || !_isConnected || _currentJobId == null) {
      throw Exception("WebSocket is not connected");
    }

    _webSocketChannel!.sink.add(jsonEncode({
      'action': 'message',
      'channel': 'job:$_currentJobId',
      'content': content,
    }));
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaySeconds), () {
      if (_reconnectDelaySeconds < 30) {
        _reconnectDelaySeconds *= 2; // Exponential backoff
      }
      _connect();
    });
  }

  Future<Map<String, dynamic>> createTicket({
    required String contextId,
    required String userToken,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post(
        '/chat/tickets',
        {'context_id': contextId},
      );

      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {};
    } catch (e) {
      debugPrint('Error creating support ticket: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void disconnect() {
    // A6: safe against post-dispose invocation (see _isDisposed note).
    if (_isDisposed) return;
    _teardownConnection();
    notifyListeners();
  }

  /// Releases the socket, subscription, and reconnect timer without
  /// notifying listeners (used both by [disconnect] and [dispose]).
  void _teardownConnection() {
    _reconnectTimer?.cancel();
    _webSocketSubscription?.cancel();
    _webSocketChannel?.sink.close();
    _webSocketChannel = null;
    _isConnected = false;
    _isConnecting = false;
    _currentJobId = null;
    _currentToken = null;
    _messages = [];
  }

  @override
  void dispose() {
    _isDisposed = true;
    _teardownConnection();
    super.dispose();
  }
}
