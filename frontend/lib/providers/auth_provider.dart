import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../models/user_profile.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient apiClient;
  final _secureStorage = const FlutterSecureStorage();

  UserProfile? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  UserProfile? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null;

  AuthProvider(this.apiClient) {
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
      _error = friendlyErrorMessage(e);
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
      _error = friendlyErrorMessage(e);
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
      _error = friendlyErrorMessage(e);
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
      _error = friendlyErrorMessage(e);
      return null;
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
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    _token = null;
    _user = null;
    apiClient.setToken(null);

    await _secureStorage.deleteAll();

    _isLoading = false;
    notifyListeners();
  }
}
