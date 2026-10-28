import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../core/password_policy.dart';
import '../l10n/app_localizations_en.dart';
import '../models/user_profile.dart';
import '../models/saved_address.dart';
import '../services/push_notification_service.dart';

/// B2: server text reaches the auth banner ONLY for 429 lockouts (the
/// wait-time is server-computed and has no localized equivalent) and an
/// explicit allowlist of curated static strings the backend intentionally
/// emits verbatim (wrong-credential / wrong-code / duplicate-registration
/// copy — all uniform anti-oracle responses with no internals).
/// Everything else renders localized friendly copy, so even if the backend
/// regresses to err-derived text, it can never reach these banners.
const _verbatimServerCopy = {
  'invalid email or password',
  'invalid or expired OTP code',
  'invalid or expired reset verification',
  'email already registered',
  'username already taken',
};

String _authBannerMessage(Object? e) {
  if (e is ApiClientException) {
    if (e.statusCode == 429) return e.message;
    if (_verbatimServerCopy.contains(e.message)) return e.message;
    // SEC-03: a policy rejection carries the machine error code from the
    // JSON body. Map it to the dedicated ARB copy via the contextless EN
    // variant — the provider has no BuildContext, matching the verbatim
    // server-copy convention for auth banners above.
    if (e.statusCode == 400 && e.errorCode == 'weak_password') {
      return weakPasswordServerMessage(AppLocalizationsEn(), e.message);
    }
  }
  return friendlyErrorMessage(e);
}

class AuthProvider extends ChangeNotifier {
  final ApiClient apiClient;
  final PushNotificationService pushService;
  final _secureStorage = const FlutterSecureStorage();

  UserProfile? _user;
  String? _token;
  bool _isLoading = false;
  // HOTFIX-LOGIN: true only while the stored session is restored at launch
  // (_tryAutoLogin). [isLoading] is also true during every auth request, so
  // the launch gate must key off this flag instead.
  bool _isRestoringSession = false;
  String? _error;
  // HTTP status of the most recent failed auth call, if the failure carried
  // one (e.g. 429 lockout on verify-code). Screens branch on this for
  // status-specific messaging; cleared alongside _error.
  int? _lastErrorStatusCode;
  String? _resetToken;
  // FE-AUTH-ACCOUNT: machine code (e.g. `weak_password`) and raw server
  // reason of the most recent failed auth call. [error] stays the banner
  // text (English for weak_password, mapped without a BuildContext); the
  // redesigned screens localize from these instead. Cleared with [error].
  String? _lastErrorCode;
  String? _lastErrorReason;

  UserProfile? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  String? get error => _error;
  int? get lastErrorStatusCode => _lastErrorStatusCode;
  String? get lastErrorCode => _lastErrorCode;
  String? get lastErrorReason => _lastErrorReason;
  // Phase-1 reset token (ADR-0026 amendment): the single-use possession
  // token minted by verifyResetCode, held here (never in a static) for the
  // phase-2 call. Null until a verify succeeds; cleared on reset success.
  String? get resetToken => _resetToken;
  bool get isAuthenticated => _token != null;

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
    _isRestoringSession = true;
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
        // Push (PUSH-FCM): token + permission, never awaited.
        unawaited(pushService.onSignedIn());
        // Refresh full user profile asynchronously on auto-login
        fetchUserProfile();
      }
    } catch (_) {
      // Silent fail on load
    } finally {
      _isLoading = false;
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  Future<void> fetchUserProfile() async {
    if (_token == null) return;
    // Audit A4: a refresh failure used to vanish into debugPrint with
    // nothing stored, so screens (KYC status, dashboards) rendered stale
    // data with zero signal. Store it like every sibling method so the
    // calling screen can surface a retryable inline banner.
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    _lastErrorStatusCode = null;
    notifyListeners();
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
      _error = friendlyErrorMessage(e);
      _lastErrorStatusCode = e is ApiClientException ? e.statusCode : null;
      notifyListeners();
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
    _lastErrorCode = null;
    _lastErrorReason = null;
    _lastErrorStatusCode = null;
    notifyListeners();
  }

  /// Banner text for a failed auth call, recording the machine code and
  /// server reason alongside it.
  String _fail(Object e) {
    _lastErrorCode = e is ApiClientException ? e.errorCode : null;
    _lastErrorReason = e is ApiClientException ? e.message : null;
    return _authBannerMessage(e);
  }

  Future<String?> signup(
      String email, String username, String password, String role) async {
    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
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
      _error = _fail(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
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
          twoFactorEnabled: res['two_factor_enabled'] is bool
              ? res['two_factor_enabled'] as bool
              : null,
        );
      }
      return res['dev_otp'] as String?;
    } catch (e) {
      debugPrint('Login error: $e');
      _error = _fail(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String email, String otp) async {
    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
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
          twoFactorEnabled: res['two_factor_enabled'] is bool
              ? res['two_factor_enabled'] as bool
              : null,
        );
        return true;
      }
      // QA audit A5: a 2xx without a token previously returned false with
      // _error == null, leaving the OTP screen with no visible feedback at
      // all — a silent dead-end on an auth-critical flow.
      _error = ErrorMessages.genericFallback;
      return false;
    } catch (e) {
      debugPrint('Verify OTP error: $e');
      _error = _fail(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> resendOtp(String email) async {
    _isLoading = true;
    _error = null;
    _lastErrorStatusCode = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    notifyListeners();

    try {
      // One endpoint for both flows: a pending sign-up, or a pending 2FA
      // sign-in challenge (USER-AUTH-BE item 6).
      final res = await apiClient.post('/auth/resend-otp', {
        'email': email,
      });
      return res['dev_otp'] as String?;
    } catch (e) {
      debugPrint('Resend OTP error: $e');
      _error = _fail(e);
      // FE-BE-GAPS: the code screen words a 429 lockout itself.
      _lastErrorStatusCode = e is ApiClientException ? e.statusCode : null;
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
    _lastErrorCode = null;
    _lastErrorReason = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/forgot-password', {
        'email': email,
      });
      return res['dev_otp'] as String?;
    } catch (e) {
      debugPrint('Forgot password error: $e');
      _error = _fail(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Phase 1 of the two-phase reset (ADR-0026): verifies the 6-digit code
  /// for [email] via POST /auth/reset-password/verify-code. Returns the
  /// single-use reset token on success (held in [resetToken] for phase 2;
  /// the code itself is consumed server-side and must not be carried
  /// forward), null on failure. On failure [_error] holds the server
  /// message and [lastErrorStatusCode] the HTTP status (notably 429 when
  /// locked out).
  Future<String?> verifyResetCode(String email, String otp) async {
    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    _lastErrorStatusCode = null;
    _resetToken = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/reset-password/verify-code', {
        'email': email,
        'otp': otp,
      });
      _resetToken = res['reset_token'] as String?;
      return _resetToken;
    } catch (e) {
      debugPrint('Verify reset code error: $e');
      _error = _fail(e);
      _lastErrorStatusCode = e is ApiClientException ? e.statusCode : null;
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Phase 2 of the two-phase reset (ADR-0026 as amended): sets the new
  /// password, presenting the possession [resetToken] minted by phase 1.
  /// The email alone is never sufficient server-side. Clears the held
  /// token on success (single-use).
  Future<bool> resetPassword(
      String email, String resetToken, String newPassword) async {
    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    _lastErrorStatusCode = null;
    notifyListeners();

    try {
      await apiClient.post('/auth/reset-password', {
        'email': email,
        'reset_token': resetToken,
        'new_password': newPassword,
      });
      _resetToken = null;
      return true;
    } catch (e) {
      debugPrint('Reset password error: $e');
      _error = _fail(e);
      _lastErrorStatusCode = e is ApiClientException ? e.statusCode : null;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Initiates an email change by sending a 6-digit OTP code to the new email address.
  Future<String?> requestEmailChange(String newEmail) async {
    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/email-change/request', {
        'new_email': newEmail,
      });
      return res['dev_otp'] as String?;
    } catch (e) {
      debugPrint('Request email change error: $e');
      _error = _fail(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Confirms the email change using the 6-digit OTP code.
  Future<bool> confirmEmailChange(String otp) async {
    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/email-change/confirm', {
        'otp': otp,
      });

      if (res['token'] != null && res['user'] != null) {
        final newToken = res['token'] as String;
        final updatedUser = UserProfile.fromJson(res['user']);
        await _handleAuthSuccess(
          newToken,
          updatedUser.id,
          updatedUser.email,
          updatedUser.username,
          updatedUser.role,
          updatedUser.kycStatus,
          twoFactorEnabled: updatedUser.twoFactorEnabled,
        );
      }
      return true;
    } catch (e) {
      debugPrint('Confirm email change error: $e');
      _error = _fail(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _handleAuthSuccess(
    String token,
    String id,
    String email,
    String username,
    String role,
    String? kycStatus, {
    bool? twoFactorEnabled,
  }) async {
    _token = token;
    _user = UserProfile(
      id: id,
      email: email,
      username: username,
      role: role,
      kycStatus: kycStatus,
      twoFactorEnabled: twoFactorEnabled ?? true,
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

    // Push (PUSH-FCM): register the token and follow its refreshes. Not
    // awaited: sign-in never waits for, or fails on, push.
    unawaited(pushService.onSignedIn());
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
    // 4. Clear any stale provider error so logged-out screens (e.g. the
    // login inline error banner) never render a previous session's failure.
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    _lastErrorStatusCode = null;
    apiClient.setToken(null);
    await _secureStorage.deleteAll();

    _isLoading = false;
    notifyListeners();
  }

  /// Forces immediate local logout when session is expired or refresh fails.
  Future<void> forceLogout() async {
    // PUSH-FCM: no API call is possible any more; drop the push token on
    // the phone so pushes stop (not awaited).
    unawaited(pushService.forgetLocalToken());
    _token = null;
    _user = null;
    // Same stale-error clearing as logout(): logged-out screens must not
    // render a previous session's provider failure.
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    _lastErrorStatusCode = null;
    apiClient.setToken(null);
    await _secureStorage.deleteAll();
    notifyListeners();
  }

  /// Fetches raw document bytes for viewing a KYB/KYE document image or PDF.
  /// Updates current authenticated user profile via PATCH /auth/user.
  Future<bool> updateOwnProfile({
    String? username,
    String? phone,
    List<String>? frequentAddresses,
    List<SavedAddress>? savedAddresses,
    bool? twoFactorEnabled,
    String? password,
  }) async {
    _isLoading = true;
    _error = null;
    _lastErrorCode = null;
    _lastErrorReason = null;
    notifyListeners();

    try {
      final body = <String, dynamic>{};
      if (username != null) body['username'] = username;
      if (phone != null) body['phone'] = phone;
      if (frequentAddresses != null) {
        body['frequent_addresses'] = frequentAddresses;
      }
      // The whole list; the server re-derives frequent_addresses from it.
      if (savedAddresses != null) {
        body['saved_addresses'] = [
          for (final a in savedAddresses) a.toJson(),
        ];
      }
      if (twoFactorEnabled != null) {
        body['two_factor_enabled'] = twoFactorEnabled;
      }
      if (password != null && password.isNotEmpty) {
        body['password'] = password;
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
      _error = _fail(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> toggleTwoFactor(bool enabled, {String? password}) async {
    final previousProfile = _user;
    if (enabled && _user != null) {
      _user = _user!.copyWith(twoFactorEnabled: true);
      notifyListeners();
    }

    try {
      final body = <String, dynamic>{
        'two_factor_enabled': enabled,
      };
      if (password != null && password.isNotEmpty) {
        body['password'] = password;
      }
      final res = await apiClient.patch('/auth/user', body);
      if (res is Map<String, dynamic> && res.containsKey('user')) {
        final userObj = res['user'];
        if (userObj is Map<String, dynamic>) {
          _user = UserProfile.fromJson(userObj);
        }
      } else {
        await fetchUserProfile();
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Toggle 2FA error: $e');
      _user = previousProfile;
      notifyListeners();
      _error = _fail(e);
      // Audit S5: store the status alongside the message (mirroring
      // fetchUserProfile/verifyResetCode) so the disable dialog can tell a
      // 429 lockout from a true 401 instead of blaming the password.
      _lastErrorStatusCode = e is ApiClientException ? e.statusCode : null;
      rethrow;
    }
  }
}
