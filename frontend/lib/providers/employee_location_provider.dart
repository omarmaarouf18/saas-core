import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../core/location_permission.dart';

enum LocationSharingStatus {
  idle,
  requestingPermission,
  permissionDenied,
  serviceDisabled,
  tracking,
  error,
}

class EmployeeLocationProvider extends ChangeNotifier {
  final ApiClient apiClient;
  final GeolocatorPlatform _geolocator;

  LocationSharingStatus _status = LocationSharingStatus.idle;
  String? _error;
  String? _activeJobId;
  DateTime? _lastSentTime;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastKnownPosition;
  Timer? _availabilityHeartbeatTimer;

  EmployeeLocationProvider(
    this.apiClient, {
    GeolocatorPlatform? geolocator,
  }) : _geolocator = geolocator ?? GeolocatorPlatform.instance;

  bool _isAvailable = false;

  LocationSharingStatus get status => _status;
  String? get error => _error;
  String? get activeJobId => _activeJobId;
  bool get isTracking => _status == LocationSharingStatus.tracking;
  bool get isAvailable => _isAvailable;
  Position? get lastKnownPosition => _lastKnownPosition;

  /// Starts live location tracking for an active job assigned to the current employee.
  Future<void> startTracking(String jobId, String userToken) async {
    if (_activeJobId == jobId && _status == LocationSharingStatus.tracking) {
      return;
    }

    await stopTracking();

    _activeJobId = jobId;
    await _startLocationStream(jobId, userToken);
  }

  /// Starts availability location pinging to /users/employee/location while the
  /// employee is online/available without an active job.
  Future<void> startAvailabilityTracking(String userToken) async {
    _isAvailable = true;

    // If already tracking an active job, job location updates already refresh location on backend.
    if (_status == LocationSharingStatus.tracking && _activeJobId != null) {
      return;
    }

    if (_status == LocationSharingStatus.tracking && _activeJobId == null) {
      return;
    }

    await stopTracking();
    await _startLocationStream(null, userToken);
  }

  /// Stops availability tracking when the employee goes offline.
  Future<void> stopAvailabilityTracking() async {
    _isAvailable = false;
    if (_activeJobId == null) {
      await stopTracking();
    } else {
      notifyListeners();
    }
  }

  Future<void> _startLocationStream(String? jobId, String userToken) async {
    _status = LocationSharingStatus.requestingPermission;
    _error = null;
    notifyListeners();

    final permResult = await requestLocationPermission(platform: _geolocator);
    if (permResult == LocationPermissionResult.serviceDisabled) {
      _status = LocationSharingStatus.serviceDisabled;
      notifyListeners();
      return;
    }

    if (permResult == LocationPermissionResult.denied ||
        permResult == LocationPermissionResult.deniedForever) {
      _status = LocationSharingStatus.permissionDenied;
      notifyListeners();
      return;
    }

    _status = LocationSharingStatus.tracking;
    _error = null;
    notifyListeners();

    // Immediately fetch initial position so stationary couriers report right away
    try {
      final initialPosition = await _geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _lastKnownPosition = initialPosition;
      _handlePositionUpdate(_activeJobId, userToken, initialPosition);
    } catch (e) {
      debugPrint('Could not obtain initial position: $e');
    }

    if (_isAvailable && _activeJobId == null) {
      _startAvailabilityHeartbeat(userToken);
    }

    // Distance filter set to 10m to avoid flooding location updates when stationary.
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    try {
      _positionSubscription = _geolocator
          .getPositionStream(locationSettings: locationSettings)
          .listen(
        (Position position) {
          _handlePositionUpdate(_activeJobId, userToken, position);
        },
        onError: (dynamic e) {
          debugPrint('Location stream error: $e');
          _error = friendlyErrorMessage(e);
          _status = LocationSharingStatus.error;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Failed to start location stream: $e');
      _error = friendlyErrorMessage(e);
      _status = LocationSharingStatus.error;
      notifyListeners();
    }
  }

  void _handlePositionUpdate(
      String? jobId, String userToken, Position position) {
    if (_status != LocationSharingStatus.tracking) return;

    _lastKnownPosition = position;

    final now = DateTime.now();
    if (_lastSentTime != null) {
      final elapsedMs = now.difference(_lastSentTime!).inMilliseconds;
      if (elapsedMs < 3500) {
        // Enforce client-side minimum 3.5s interval gate (safety margin over backend 3s rate limit floor).
        debugPrint(
            'Location update skipped due to 3.5s minimum interval gate (${elapsedMs}ms elapsed)');
        return;
      }
    }

    _lastSentTime = now;
    if (jobId != null) {
      _sendLocationUpdate(
          jobId, userToken, position.latitude, position.longitude);
    } else {
      _sendAvailabilityPing(userToken, position.latitude, position.longitude);
    }
  }

  void _startAvailabilityHeartbeat(String userToken) {
    _availabilityHeartbeatTimer?.cancel();
    _availabilityHeartbeatTimer =
        Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_status != LocationSharingStatus.tracking ||
          !_isAvailable ||
          _activeJobId != null) {
        return;
      }
      Position? pos = _lastKnownPosition;
      try {
        pos = await _geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        _lastKnownPosition = pos;
      } catch (e) {
        debugPrint('Availability heartbeat getCurrentPosition error: $e');
      }
      if (pos != null &&
          _status == LocationSharingStatus.tracking &&
          _isAvailable &&
          _activeJobId == null) {
        _sendAvailabilityPing(userToken, pos.latitude, pos.longitude);
      }
    });
  }

  Future<void> _sendLocationUpdate(
      String jobId, String userToken, double lat, double lng) async {
    try {
      await apiClient.post(
        '/users/jobs/location/update',
        {
          'job_id': jobId,
          'requester_id': userToken,
          'latitude': lat,
          'longitude': lng,
        },
      );
      if (_error != null) {
        _error = null;
        notifyListeners();
      }
    } catch (e) {
      if (e is ApiClientException) {
        // 429 rate limit or 400 implausible_speed non-fatal responses:
        // Log quietly, do NOT set error state visible to UI or stop tracking.
        if (e.statusCode == 429 ||
            (e.statusCode == 400 && e.message.contains('implausible_speed'))) {
          debugPrint(
              'Non-fatal location update response (${e.statusCode}): ${e.message}');
          return;
        }
      }
      debugPrint('Genuine location update failure: $e');
      _error = friendlyErrorMessage(e);
      _status = LocationSharingStatus.error;
      notifyListeners();
    }
  }

  Future<void> _sendAvailabilityPing(
      String userToken, double lat, double lng) async {
    _lastSentTime = DateTime.now();
    try {
      await apiClient.post(
        '/users/employee/location',
        {
          'requester_token': userToken,
          'latitude': lat,
          'longitude': lng,
        },
      );
      if (_error != null) {
        _error = null;
        notifyListeners();
      }
    } catch (e) {
      if (e is ApiClientException) {
        if (e.statusCode == 429 ||
            (e.statusCode == 400 && e.message.contains('implausible_speed'))) {
          debugPrint(
              'Non-fatal availability ping response (${e.statusCode}): ${e.message}');
          return;
        }
      }
      debugPrint('Genuine availability ping failure: $e');
      _error = friendlyErrorMessage(e);
      _status = LocationSharingStatus.error;
      notifyListeners();
    }
  }

  /// Cancels position stream subscription and resets tracking status to idle.
  Future<void> stopTracking({bool notify = true}) async {
    _availabilityHeartbeatTimer?.cancel();
    _availabilityHeartbeatTimer = null;
    _lastKnownPosition = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _activeJobId = null;
    _status = LocationSharingStatus.idle;
    _error = null;
    _lastSentTime = null;
    if (notify && hasListeners) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopTracking(notify: false);
    super.dispose();
  }
}
