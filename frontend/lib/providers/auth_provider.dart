import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../models/user_profile.dart';
import '../services/push_notification_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient apiClient;
  final PushNotificationService pushService;
  final _secureStorage = const FlutterSecureStorage();

  UserProfile? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  List<dynamic> _pendingSubmissions = [];
  bool _isLoadingPending = false;
  String? _pendingError;

  UserProfile? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null;

  List<dynamic> get pendingSubmissions => _pendingSubmissions;
  bool get isLoadingPending => _isLoadingPending;
  String? get pendingError => _pendingError;

  AuthProvider(this.apiClient, {PushNotificationService? pushService})
      : pushService =
            pushService ?? PushNotificationService(apiClient: apiClient) {
    // Intercept token refresh events from ApiClient
    apiClient.onTokenRefreshed = (newToken) async {
      _token = newToken;
      await _secureStorage.write(key: 'jwt_token', value: newToken);
      notifyListeners();
    };

    apiClient.onAuthFailed = () async {
      await forceLogout();
    };

    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();
    try {
      final token = await _secureStorage.read(key: 'jwt_token');
      final email = await _secureStorage.read(key: 'user_email');
      final username = await _secureStorage.read(key: 'user_username') ?? '';
      final role = await _secureStorage.read(key: 'user_role');
      final id = await _secureStorage.read(key: 'user_id');
      final kyc = await _secureStorage.read(key: 'user_kyc');

      if (token != null && email != null && role != null && id != null) {
        _token = token;
        _user = UserProfile(
          id: id,
          email: email,
          username: username,
          role: role,
          kycStatus: kyc,
        );
        apiClient.setToken(_token);
        // Register FCM device token on auto-login startup
        pushService.registerDeviceToken();
        // Refresh full user profile asynchronously on auto-login
        fetchUserProfile();
      }
    } catch (_) {
      // Silent fail on load
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchUserProfile() async {
    if (_token == null) return;
    try {
      final res = await apiClient
          .get('/auth/user', queryParams: {'user_token': _token!});
      if (res is Map<String, dynamic>) {
        _user = UserProfile.fromJson(res);
        if (_user!.effectiveKycStatus.isNotEmpty) {
          await _secureStorage.write(
              key: 'user_kyc', value: _user!.effectiveKycStatus);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Fetch user profile error: $e');
    }
  }

  Future<bool> uploadDocument({
    required String docType,
    required List<int> fileBytes,
    required String filename,
  }) async {
    if (_token == null || _user == null) {
      throw ApiClientException('User is not authenticated');
    }

    final isOwner = _user!.role == 'owner';
    final isEmployee = _user!.role == 'employee';

    if (!isOwner && !isEmployee) {
      throw ApiClientException(
          'Only owners and employees can upload verification documents');
    }

    final path = isOwner
        ? '/auth/kyb/upload?type=$docType'
        : '/auth/kye/upload?type=$docType';

    final res = await apiClient.postMultipart(
      path,
      fieldName: 'file',
      fileBytes: fileBytes,
      filename: filename,
    );

    if (res is Map && res['status'] == 'uploaded') {
      await fetchUserProfile();
      return true;
    }
    return false;
  }

  Future<List<dynamic>> fetchPendingSubmissions({
    String? internalToken,
    String? reviewerToken,
  }) async {
    _isLoadingPending = true;
    _pendingError = null;
    notifyListeners();

    try {
      final headers = <String, String>{};
      if (internalToken != null && internalToken.isNotEmpty) {
        headers['X-Internal-Token'] = internalToken;
      }
      if (reviewerToken != null && reviewerToken.isNotEmpty) {
        headers['X-Reviewer-Token'] = reviewerToken;
      }

      final res = await apiClient.get(
        '/auth/kyb-kye/pending',
        headers: headers.isNotEmpty ? headers : null,
      );

      if (res is List) {
        _pendingSubmissions = res;
      } else if (res is Map &&
          res.containsKey('submissions') &&
          res['submissions'] is List) {
        _pendingSubmissions = res['submissions'] as List<dynamic>;
      } else {
        _pendingSubmissions = [];
      }
      return _pendingSubmissions;
    } catch (e) {
      _pendingError = friendlyErrorMessage(e);
      _pendingSubmissions = [];
      return [];
    } finally {
      _isLoadingPending = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<String?> signup(
      String email, String username, String password, String role) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/signup', {
        'email': email,
        'username': username,
        'password': password,
        'role': role,
      });
      return res['dev_otp'] as String?;
    } catch (e) {
      debugPrint('Signup error: $e');
      _error = e is ApiClientException ? e.message : friendlyErrorMessage(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/login', {
        'email': email,
        'password': password,
      });

      if (res.containsKey('token')) {
        await _handleAuthSuccess(
          res['token'],
          res['user_id'] ?? '',
          email,
          res['username'] ?? '',
          res['role'] ?? 'employee',
          res['kyc_status'],
        );
      }
      return res['dev_otp'] as String?;
    } catch (e) {
      debugPrint('Login error: $e');
      _error = e is ApiClientException ? e.message : friendlyErrorMessage(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String email, String otp) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/verify-otp', {
        'email': email,
        'otp': otp,
      });

      if (res.containsKey('token')) {
        await _handleAuthSuccess(
          res['token'],
          res['user_id'] ?? '',
          email,
          res['username'] ?? '',
          res['role'] ?? '',
          res['kyc_status'],
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Verify OTP error: $e');
      _error = e is ApiClientException ? e.message : friendlyErrorMessage(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> resendOtp(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/resend-otp', {
        'email': email,
      });
      return res['dev_otp'] as String?;
    } catch (e) {
      debugPrint('Resend OTP error: $e');
      _error = e is ApiClientException ? e.message : friendlyErrorMessage(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Initiates password recovery by sending a 6-digit OTP code to the specified email.
  Future<String?> forgotPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/forgot-password', {
        'email': email,
      });
      return res['dev_otp'] as String?;
    } catch (e) {
      debugPrint('Forgot password error: $e');
      _error = e is ApiClientException ? e.message : friendlyErrorMessage(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resets the user's password using the received 6-digit OTP code.
  Future<bool> resetPassword(
      String email, String otp, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await apiClient.post('/auth/reset-password', {
        'email': email,
        'otp': otp,
        'new_password': newPassword,
      });
      return true;
    } catch (e) {
      debugPrint('Reset password error: $e');
      _error = e is ApiClientException ? e.message : friendlyErrorMessage(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _handleAuthSuccess(String token, String id, String email,
      String username, String role, String? kycStatus) async {
    _token = token;
    _user = UserProfile(
      id: id,
      email: email,
      username: username,
      role: role,
      kycStatus: kycStatus,
    );
    apiClient.setToken(token);

    await _secureStorage.write(key: 'jwt_token', value: token);
    await _secureStorage.write(key: 'user_id', value: id);
    await _secureStorage.write(key: 'user_email', value: email);
    await _secureStorage.write(key: 'user_username', value: username);
    await _secureStorage.write(key: 'user_role', value: role);
    if (kycStatus != null) {
      await _secureStorage.write(key: 'user_kyc', value: kycStatus);
    } else {
      await _secureStorage.delete(key: 'user_kyc');
    }

    // Register FCM device token on login/signup success
    await pushService.registerDeviceToken();
  }

  /// Revokes active session on backend, unregisters device tokens, and purges local state.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    // 1. Unregister FCM device token before clearing token state
    try {
      await pushService.unregisterDeviceToken();
    } catch (e) {
      debugPrint('Unregister device token error during logout: $e');
    }

    // 2. Call backend POST /auth/logout
    if (_token != null && _token!.isNotEmpty) {
      try {
        await apiClient.post('/auth/logout', {});
      } catch (e) {
        debugPrint('Backend logout endpoint error: $e');
      }
    }

    // 3. Clear local token, user, and secure storage
    _token = null;
    _user = null;
    apiClient.setToken(null);
    await _secureStorage.deleteAll();

    _isLoading = false;
    notifyListeners();
  }

  /// Forces immediate local logout when session is expired or refresh fails.
  Future<void> forceLogout() async {
    _token = null;
    _user = null;
    apiClient.setToken(null);
    await _secureStorage.deleteAll();
    notifyListeners();
  }

  /// Fetches raw document bytes for viewing a KYB/KYE document image or PDF.
  Future<Uint8List> fetchDocumentBytes(
    String documentUrl, {
    String? internalToken,
    String? reviewerToken,
  }) async {
    final Map<String, String> headers = {};
    if (internalToken != null && internalToken.isNotEmpty) {
      headers['X-Internal-Token'] = internalToken;
    }
    if (reviewerToken != null && reviewerToken.isNotEmpty) {
      headers['X-Reviewer-Token'] = reviewerToken;
    }
    return await apiClient.getBytes(documentUrl,
        headers: headers.isNotEmpty ? headers : null);
  }

  /// Submits an approve or reject review action for a pending KYB/KYE submission.
  Future<bool> reviewSubmission({
    required String userId,
    required String action,
    String? reason,
    String? internalToken,
    String? reviewerToken,
  }) async {
    _isLoading = true;
    _pendingError = null;
    notifyListeners();

    try {
      final Map<String, String> headers = {};
      if (internalToken != null && internalToken.isNotEmpty) {
        headers['X-Internal-Token'] = internalToken;
      }
      if (reviewerToken != null && reviewerToken.isNotEmpty) {
        headers['X-Reviewer-Token'] = reviewerToken;
      }

      final body = {
        'user_id': userId,
        'action': action,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      };

      final response = await apiClient.post(
        '/auth/kyb-kye/review',
        body,
        headers: headers.isNotEmpty ? headers : null,
      );

      if (response != null && response['status'] == 'reviewed') {
        _pendingSubmissions.removeWhere((item) => item['user_id'] == userId);
        return true;
      }
      return false;
    } catch (e) {
      _pendingError = e.toString().replaceAll('ApiClientException: ', '');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates current authenticated user profile via PATCH /auth/user.
  Future<bool> updateOwnProfile({
    String? username,
    String? phone,
    List<String>? frequentAddresses,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final body = <String, dynamic>{};
      if (username != null) body['username'] = username;
      if (phone != null) body['phone'] = phone;
      if (frequentAddresses != null) {
        body['frequent_addresses'] = frequentAddresses;
      }

      final res = await apiClient.patch('/auth/user', body);
      if (res is Map<String, dynamic> && res.containsKey('user')) {
        final userObj = res['user'];
        if (userObj is Map<String, dynamic>) {
          _user = UserProfile.fromJson(userObj);
          if (_user!.username.isNotEmpty) {
            await _secureStorage.write(
                key: 'user_username', value: _user!.username);
          }
        }
      } else {
        await fetchUserProfile();
      }
      return true;
    } catch (e) {
      debugPrint('Update profile error: $e');
      _error = e is ApiClientException ? e.message : friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
