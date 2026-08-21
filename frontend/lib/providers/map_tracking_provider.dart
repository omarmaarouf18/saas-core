import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/error_messages.dart';
import '../models/employee_marker.dart';
import '../models/job.dart';

class MapTrackingProvider extends ChangeNotifier {
  final ApiClient apiClient;

  WebSocketChannel? _webSocketChannel;
  StreamSubscription? _webSocketSubscription;

  final Map<String, EmployeeMarkerData> _employeeMarkers = {};
  JobLocation? _customerJobLocation;
  String? _assignedEmployeeId;

  bool _isLoading = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _error;
  String? _subscriptionError;

  // Reconnection state
  Timer? _reconnectTimer;
  int _reconnectDelaySeconds = 2;
  String? _currentChannel;
  String? _currentToken;

  Map<String, EmployeeMarkerData> get employeeMarkers => _employeeMarkers;
  List<EmployeeMarkerData> get markersList => _employeeMarkers.values.toList();
  JobLocation? get customerJobLocation => _customerJobLocation;
  String? get assignedEmployeeId => _assignedEmployeeId;

  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get error => _error;
  String? get subscriptionError => _subscriptionError;

  MapTrackingProvider(this.apiClient);

  /// Hydrate initial fleet positions for tenant owner via GET /users/jobs/owner
  Future<void> hydrateOwnerFleet(String ownerToken) async {
    _isLoading = true;
    _error = null;
    _subscriptionError = null;
    _employeeMarkers.clear();
    notifyListeners();

    try {
      final res = await apiClient.get(
        '/users/jobs/owner',
        queryParams: {'owner_token': ownerToken},
      );

      if (res is List) {
        final now = DateTime.now();
        for (final item in res) {
          if (item is Map<String, dynamic>) {
            final job = Job.fromJson(item);
            final empId = job.employeeId;
            if (empId == null || empId.isEmpty) continue;

            // Include employees with active jobs or recent updates (within 15 minutes)
            final isRecent = job.updatedAt == null ||
                now.difference(job.updatedAt!).inMinutes <= 15;
            final isActiveStatus = job.status == 'active';

            if (isActiveStatus || isRecent) {
              final loc = job.currentLocation ?? job.location;
              _employeeMarkers[empId] = EmployeeMarkerData(
                employeeId: empId,
                jobId: job.id,
                latitude: loc.latitude,
                longitude: loc.longitude,
                updatedAt: job.updatedAt ?? now,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error hydrating owner fleet: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Hydrate initial position for assigned employee for a customer job via GET /users/jobs/get
  Future<void> hydrateCustomerJob(String jobId, String userToken) async {
    _isLoading = true;
    _error = null;
    _subscriptionError = null;
    _employeeMarkers.clear();
    _customerJobLocation = null;
    _assignedEmployeeId = null;
    notifyListeners();

    try {
      // requester_id (not the legacy user_token alias): the backend resolves
      // the job ID solely from `id` and requires requester_id for party
      // authorization. Sending user_token here previously caused 404s because
      // it was once preferred as the job-ID parameter.
      final res = await apiClient.get(
        '/users/jobs/get',
        queryParams: {'id': jobId, 'requester_id': userToken},
      );

      Map<String, dynamic>? jobMap;
      if (res is Map<String, dynamic>) {
        jobMap = res;
      } else if (res is List && res.isNotEmpty) {
        jobMap = res.first as Map<String, dynamic>;
      }

      if (jobMap != null) {
        final job = Job.fromJson(jobMap);
        _customerJobLocation = job.location;
        _assignedEmployeeId = job.employeeId;

        if (job.employeeId != null && job.employeeId!.isNotEmpty) {
          final loc = job.currentLocation ?? job.location;
          _employeeMarkers[job.employeeId!] = EmployeeMarkerData(
            employeeId: job.employeeId!,
            jobId: job.id,
            latitude: loc.latitude,
            longitude: loc.longitude,
            updatedAt: job.updatedAt ?? DateTime.now(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error hydrating customer job: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Connect to chat-service WebSocket hub and subscribe to channel ("fleet:<owner_id>" or "job:<job_id>")
  void connectAndSubscribe(String channel, String token,
      {WebSocketChannel? customChannel}) {
    _currentChannel = channel;
    _currentToken = token;
    _reconnectTimer?.cancel();

    if (customChannel != null) {
      _webSocketChannel = customChannel;
      _isConnecting = false;
      _isConnected = true;
      _webSocketSubscription?.cancel();
      _webSocketSubscription = _webSocketChannel!.stream.listen(
        (data) => _handleIncomingData(data),
        onError: (err) {
          _isConnected = false;
          _isConnecting = false;
          _error = err.toString();
          notifyListeners();
        },
        onDone: () {
          _isConnected = false;
          _isConnecting = false;
          notifyListeners();
        },
      );
      notifyListeners();
      return;
    }

    _connect();
  }

  void _connect() {
    if (_currentToken == null || _currentChannel == null) return;

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
      _subscribe(_currentChannel!);

      _webSocketSubscription = _webSocketChannel!.stream.listen(
        (data) {
          _handleIncomingData(data);
        },
        onError: (err) {
          _isConnected = false;
          _isConnecting = false;
          _error = err.toString();
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
      debugPrint('Error establishing map WebSocket: $e');
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
          _reconnectTimer?.cancel();
        } else {
          _error = messageVal;
        }
        _isConnecting = false;
        notifyListeners();
      } else if (type == 'location_update' ||
          (map['latitude'] != null && map['longitude'] != null)) {
        final empId = map['employee_id']?.toString() ??
            map['sender_id']?.toString() ??
            _assignedEmployeeId;
        final lat = (map['latitude'] as num?)?.toDouble();
        final lon = (map['longitude'] as num?)?.toDouble();

        if (empId != null && empId.isNotEmpty && lat != null && lon != null) {
          final existing = _employeeMarkers[empId];
          _employeeMarkers[empId] = EmployeeMarkerData(
            employeeId: empId,
            jobId: map['job_id']?.toString() ?? existing?.jobId,
            latitude: lat,
            longitude: lon,
            updatedAt: DateTime.now(),
          );
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Failed to parse websocket map data: $e");
    }
  }

  void _subscribe(String channel) {
    _webSocketChannel?.sink.add(jsonEncode({
      'action': 'subscribe',
      'channel': channel,
    }));
  }

  void updateMarkerManually(EmployeeMarkerData marker) {
    _employeeMarkers[marker.employeeId] = marker;
    notifyListeners();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaySeconds), () {
      if (_reconnectDelaySeconds < 30) {
        _reconnectDelaySeconds *= 2;
      }
      _connect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _webSocketSubscription?.cancel();
    _webSocketChannel?.sink.close();
    _webSocketChannel = null;
    _isConnected = false;
    _isConnecting = false;
    _currentChannel = null;
    _currentToken = null;
    _employeeMarkers.clear();
    _customerJobLocation = null;
    _assignedEmployeeId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
