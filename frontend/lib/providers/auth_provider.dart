import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api_client.dart';
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
      }
    } catch (_) {
      // Silent fail on load
    } finally {
      _isLoading = false;
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
      _error = e.toString().replaceFirst("ApiClientException: ", "");
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
      _error = e.toString().replaceFirst("ApiClientException: ", "");
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
      _error = e.toString().replaceFirst("ApiClientException: ", "");
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
      _error = e.toString().replaceFirst("ApiClientException: ", "");
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
