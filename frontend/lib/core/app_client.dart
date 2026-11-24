import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

/// Which of the three Waddify apps this build is (ADR-0030). One codebase,
/// three Android flavors; the Dart side learns its app from
/// `--dart-define=APP_CLIENT=<customer|console|employees>`.
///
/// Release builds pass both `--flavor X` and `--dart-define=APP_CLIENT=X`.
/// Without the define the app uses the build flavor when it names a client
/// (`flutter run --flavor console`), else [AppClient.customer] (tests, and
/// a `flutter run` without a flavor). A define that names no client, or one
/// that disagrees with the build flavor, throws at start-up: a misbuilt app
/// must not quietly sign people into the wrong role's app.
enum AppClient {
  /// Waddify: the customer marketplace (role `user`).
  customer(
    allowedRoles: {'user'},
    signupRole: 'user',
    displayName: 'Waddify',
  ),

  /// Waddify Console: business owners (role `owner`).
  console(
    allowedRoles: {'owner'},
    signupRole: 'owner',
    displayName: 'Waddify Console',
  ),

  /// Waddify Employees: couriers and drivers (role `employee`). No signup:
  /// owners add their staff (ADR-0001).
  employees(
    allowedRoles: {'employee'},
    signupRole: null,
    displayName: 'Waddify Employees',
  );

  const AppClient({
    required this.allowedRoles,
    required this.signupRole,
    required this.displayName,
  });

  /// Account roles this app signs in. Any other role gets the wrong-app
  /// page, never another role's shell.
  final Set<String> allowedRoles;

  /// The role a signup in this app creates; null when the app has no
  /// signup.
  final String? signupRole;

  /// Store and launcher name (the brand is never translated, ADR-0029).
  final String displayName;

  bool get canSignUp => signupRole != null;

  bool allows(String? role) => role != null && allowedRoles.contains(role);

  /// The app made for [role], or null for roles with no app (admin,
  /// reviewer: they use the web console).
  static AppClient? forRole(String? role) {
    for (final client in values) {
      if (client.allows(role)) return client;
    }
    return null;
  }

  /// The client named [name] (`customer`, `console`, `employees`), or null.
  static AppClient? tryParse(String? name) {
    for (final client in values) {
      if (client.name == name) return client;
    }
    return null;
  }

  /// Resolves the build's client from the APP_CLIENT [define] and the
  /// Flutter build [flavor] (see the class comment).
  static AppClient resolve({required String define, String? flavor}) {
    final fromFlavor = tryParse(flavor);
    if (define.isEmpty) return fromFlavor ?? AppClient.customer;
    final fromDefine = tryParse(define);
    if (fromDefine == null) {
      throw StateError('APP_CLIENT="$define" names no app; use one of '
          '${values.map((c) => c.name).join(', ')}');
    }
    if (fromFlavor != null && fromFlavor != fromDefine) {
      throw StateError('APP_CLIENT="$define" does not match the build '
          'flavor "$flavor"; build with --flavor X --dart-define=APP_CLIENT=X');
    }
    return fromDefine;
  }

  static final AppClient _built = resolve(
    define: const String.fromEnvironment('APP_CLIENT'),
    flavor: appFlavor,
  );

  static AppClient? _override;

  /// This build's app.
  static AppClient get current => _override ?? _built;

  /// Tests pretend to be another app; reset to null in a tearDown.
  @visibleForTesting
  static set debugOverride(AppClient? client) => _override = client;
}
