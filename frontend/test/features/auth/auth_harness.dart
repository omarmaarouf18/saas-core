import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/features/auth/auth_nav.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Shared fakes for the FE-AUTH-ACCOUNT page tests.

const ar = Locale('ar');
const en = Locale('en');
const bothLocales = [ar, en];

/// A scripted failure for one [FakeAuthFlow] method.
class AuthFailure {
  const AuthFailure(this.message, {this.status, this.code, this.reason});

  final String message;
  final int? status;
  final String? code;
  final String? reason;
}

/// AuthProvider fake. Each method records its call in [calls], holds on
/// [gates] (method name → completer) when set, then fails with
/// [failNext] (consumed once; [failAlways] keeps failing) or succeeds with
/// the scripted values below. Error fields behave like the real provider:
/// cleared at the start of a call, set on failure.
class FakeAuthFlow extends ChangeNotifier implements AuthProvider {
  FakeAuthFlow({this.user, this.token});

  @override
  UserProfile? user;

  @override
  String? token;

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  int? lastErrorStatusCode;

  @override
  String? lastErrorCode;

  @override
  String? lastErrorReason;

  @override
  String? resetToken;

  @override
  bool get isAuthenticated => token != null;

  final List<String> calls = [];
  final Map<String, AuthFailure> failNext = {};
  final Map<String, AuthFailure> failAlways = {};
  final Map<String, Completer<void>> gates = {};

  /// `dev_otp` returned by signup / login / resend / forgot / email change.
  String? devOtp = '123456';

  /// Login signs straight in (no 2FA) when true.
  bool loginAuthenticates = false;

  /// What verifyResetCode returns on success.
  String? nextResetToken = 'reset-token';

  /// Last profile PATCH body.
  Map<String, Object?>? lastProfileUpdate;
  final List<(bool, String?)> twoFactorCalls = [];

  static UserProfile customer({
    bool twoFactor = true,
    String? accountStatus,
    String? suspensionReason,
    List<String>? addresses,
    String role = 'user',
  }) =>
      UserProfile(
        id: 'user-1',
        email: 'mona@example.com',
        username: 'Mona',
        phone: '01001234567',
        role: role,
        frequentAddresses: addresses ?? ['Home, 12 Tahrir St', 'Work'],
        twoFactorEnabled: twoFactor,
        accountStatus: accountStatus,
        suspensionReason: suspensionReason,
      );

  void _clear() {
    error = null;
    lastErrorStatusCode = null;
    lastErrorCode = null;
    lastErrorReason = null;
  }

  /// Runs a scripted call; returns false (with error fields set) on failure.
  Future<bool> _run(String name, String arg, {bool loading = true}) async {
    calls.add('$name:$arg');
    _clear();
    if (loading) isLoading = true;
    notifyListeners();
    final gate = gates[name];
    if (gate != null) await gate.future;
    if (loading) isLoading = false;
    final failure = failNext.remove(name) ?? failAlways[name];
    if (failure != null) {
      error = failure.message;
      lastErrorStatusCode = failure.status;
      lastErrorCode = failure.code;
      lastErrorReason = failure.reason;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  @override
  void clearError() {
    _clear();
    notifyListeners();
  }

  @override
  Future<String?> login(String email, String password) async {
    if (!await _run('login', email)) return null;
    if (loginAuthenticates) {
      token = 'jwt';
      user = customer();
      notifyListeners();
    }
    return devOtp;
  }

  @override
  Future<String?> signup(
      String email, String username, String password, String role) async {
    if (!await _run('signup', '$email|$username|$role')) return null;
    return devOtp;
  }

  @override
  Future<bool> verifyOtp(String email, String otp) async {
    if (!await _run('verifyOtp', '$email|$otp')) return false;
    token = 'jwt';
    user = customer();
    notifyListeners();
    return true;
  }

  @override
  Future<String?> resendOtp(String email) async {
    if (!await _run('resendOtp', email)) return null;
    return devOtp;
  }

  @override
  Future<String?> forgotPassword(String email) async {
    if (!await _run('forgotPassword', email)) return null;
    return devOtp;
  }

  @override
  Future<String?> verifyResetCode(String email, String otp) async {
    resetToken = null;
    if (!await _run('verifyResetCode', '$email|$otp')) return null;
    resetToken = nextResetToken;
    return resetToken;
  }

  @override
  Future<bool> resetPassword(
      String email, String resetToken, String newPassword) async {
    if (!await _run('resetPassword', '$email|$resetToken|$newPassword')) {
      return false;
    }
    this.resetToken = null;
    return true;
  }

  @override
  Future<void> fetchUserProfile() async {
    await _run('fetchUserProfile', '', loading: false);
  }

  @override
  Future<bool> updateOwnProfile({
    String? username,
    String? phone,
    List<String>? frequentAddresses,
    bool? twoFactorEnabled,
    String? password,
  }) async {
    lastProfileUpdate = {
      if (username != null) 'username': username,
      if (phone != null) 'phone': phone,
      if (frequentAddresses != null) 'frequent_addresses': frequentAddresses,
    };
    if (!await _run('updateOwnProfile', '')) {
      throw Exception(error);
    }
    user = user?.copyWith(
      username: username,
      phone: phone,
      frequentAddresses: frequentAddresses,
    );
    notifyListeners();
    return true;
  }

  @override
  Future<bool> toggleTwoFactor(bool enabled, {String? password}) async {
    twoFactorCalls.add((enabled, password));
    if (!await _run('toggleTwoFactor', '$enabled', loading: false)) {
      throw Exception(error);
    }
    user = user?.copyWith(twoFactorEnabled: enabled);
    notifyListeners();
    return true;
  }

  @override
  Future<String?> requestEmailChange(String newEmail) async {
    if (!await _run('requestEmailChange', newEmail)) throw Exception(error);
    return devOtp;
  }

  @override
  Future<bool> confirmEmailChange(String otp) async {
    if (!await _run('confirmEmailChange', otp)) throw Exception(error);
    return true;
  }

  @override
  Future<void> logout() async {
    calls.add('logout:');
    token = null;
    user = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeThemeMode extends ChangeNotifier implements ThemeProvider {
  @override
  ThemeMode themeMode = ThemeMode.light;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocale extends ChangeNotifier implements LocaleProvider {
  FakeLocale([this.locale]);

  @override
  Locale? locale;

  final List<Locale?> set = [];

  @override
  Future<void> setLocale(Locale? newLocale) async {
    set.add(newLocale);
    locale = newLocale;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records hand-offs instead of building the signed-in app.
class RecordingAuthNav extends AuthNav {
  int homes = 0;
  int signedOut = 0;
  final List<String?> resets = [];

  /// What [openPasswordReset] completes with.
  String? resetResult;

  @override
  Future<void> goHome(BuildContext context) async => homes++;

  @override
  Future<void> goSignedOut(BuildContext context) async => signedOut++;

  @override
  Future<String?> openPasswordReset(BuildContext context,
      {String? email}) async {
    resets.add(email);
    return resetResult;
  }
}

class AuthTestDeps {
  AuthTestDeps({FakeAuthFlow? auth, RecordingAuthNav? nav})
      : auth = auth ?? FakeAuthFlow(),
        nav = nav ?? RecordingAuthNav();

  final FakeAuthFlow auth;
  final RecordingAuthNav nav;
  final FakeThemeMode theme = FakeThemeMode();
  late final FakeLocale locale = FakeLocale();

  /// Extra providers (customer pages).
  final List<SingleChildWidget> extra = [];
}

/// The app around an auth page: the old app theme (pages bring their own
/// redesign theme), providers, the nav scope, and the locale from the
/// locale provider when one was set (language switch), else [locale].
Widget authApp(AuthTestDeps deps, Widget home, {Locale locale = en}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: deps.auth),
      ChangeNotifierProvider<ThemeProvider>.value(value: deps.theme),
      ChangeNotifierProvider<LocaleProvider>.value(value: deps.locale),
      ...deps.extra,
    ],
    child: AuthNavScope(
      nav: deps.nav,
      child: Consumer2<LocaleProvider, ThemeProvider>(
        builder: (context, l, t, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: quickDeliveryTheme,
          darkTheme: quickDeliveryDarkTheme,
          themeMode: t.themeMode,
          locale: l.locale ?? locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    ),
  );
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Types into the QdTextField with [key].
Future<void> typeInto(WidgetTester tester, String key, String text) =>
    tester.enterText(
        find.descendant(
            of: find.byKey(Key(key)), matching: find.byType(TextField)),
        text);
