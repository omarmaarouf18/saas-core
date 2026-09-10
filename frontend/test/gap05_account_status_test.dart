import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/my_account_screen.dart';

class MockAuthProviderForAccountStatus extends AuthProvider {
  final UserProfile? mockUser;

  MockAuthProviderForAccountStatus(super.apiClient, {this.mockUser});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => 'mock-token';

  @override
  Future<void> fetchUserProfile() async {}

  @override
  Future<bool> updateOwnProfile({
    String? username,
    String? phone,
    List<String>? frequentAddresses,
  }) async =>
      true;
}

Widget _buildTestApp({
  required UserProfile user,
  Locale locale = const Locale('en'),
}) {
  final apiClient = ApiClient();
  final authProvider =
      MockAuthProviderForAccountStatus(apiClient, mockUser: user);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
      ],
      home: const MyAccountScreen(),
    ),
  );
}

void main() {
  group('GAP-05: UserProfile Model Deserialization & Getters', () {
    test('deserializes account_status and suspension_reason correctly', () {
      final json = {
        'id': 'user-123',
        'email': 'suspended@example.com',
        'username': 'bad_actor',
        'role': 'user',
        'account_status': 'suspended',
        'suspension_reason': 'Fraudulent chargeback activity detected',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.accountStatus, 'suspended');
      expect(
          profile.suspensionReason, 'Fraudulent chargeback activity detected');
      expect(profile.isSuspended, isTrue);
      expect(profile.isActiveAccount, isFalse);
    });

    test('deserializes active status and handles null reason', () {
      final json = {
        'id': 'user-456',
        'email': 'good@example.com',
        'username': 'good_user',
        'role': 'user',
        'account_status': 'active',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.accountStatus, 'active');
      expect(profile.suspensionReason, isNull);
      expect(profile.isSuspended, isFalse);
      expect(profile.isActiveAccount, isTrue);
    });

    test('defaults isSuspended to false when account_status is missing', () {
      final json = {
        'id': 'user-789',
        'email': 'legacy@example.com',
        'username': 'legacy_user',
        'role': 'user',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.accountStatus, isNull);
      expect(profile.isSuspended, isFalse);
      expect(profile.isActiveAccount, isTrue);
    });
  });

  group('GAP-05: MyAccountScreen Account Standing UI', () {
    testWidgets(
        'renders account_suspended_banner with specific reason when suspended',
        (tester) async {
      final suspendedUser = UserProfile(
        id: 'susp-1',
        email: 'blocked@example.com',
        username: 'blocked_user',
        role: 'user',
        accountStatus: 'suspended',
        suspensionReason: 'Terms of service violation: Policy breach',
      );

      await tester.pumpWidget(_buildTestApp(user: suspendedUser));
      await tester.pumpAndSettle();

      // Banner is present
      expect(find.byKey(const Key('account_suspended_banner')), findsOneWidget);
      expect(find.text('Account Suspended'), findsOneWidget);
      expect(find.text('Terms of service violation: Policy breach'),
          findsOneWidget);

      // Status badge displays Suspended
      expect(find.byKey(const Key('account_status_badge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('account_status_badge')),
          matching: find.text('Suspended'),
        ),
        findsOneWidget,
      );

      // Save button is disabled
      final saveButton = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('my_account_save_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(saveButton.onPressed, isNull);

      // Change email button is disabled
      final changeEmailButton = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('change_email_button')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(changeEmailButton.onPressed, isNull);
    });

    testWidgets(
        'renders account_suspended_banner with default reason when suspensionReason is null',
        (tester) async {
      final suspendedUser = UserProfile(
        id: 'susp-2',
        email: 'blocked2@example.com',
        username: 'blocked_user2',
        role: 'user',
        accountStatus: 'suspended',
        suspensionReason: null,
      );

      await tester.pumpWidget(_buildTestApp(user: suspendedUser));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account_suspended_banner')), findsOneWidget);
      expect(find.text('Account Suspended'), findsOneWidget);
      expect(
        find.text(
            'Your account has been suspended by an administrator. Please contact support for more information.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'hides account_suspended_banner and shows Active badge for active account',
        (tester) async {
      final activeUser = UserProfile(
        id: 'act-1',
        email: 'active@example.com',
        username: 'active_user',
        role: 'user',
        accountStatus: 'active',
      );

      await tester.pumpWidget(_buildTestApp(user: activeUser));
      await tester.pumpAndSettle();

      // Banner is hidden
      expect(find.byKey(const Key('account_suspended_banner')), findsNothing);

      // Status badge displays Active
      expect(find.byKey(const Key('account_status_badge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('account_status_badge')),
          matching: find.text('Active'),
        ),
        findsOneWidget,
      );

      // Save button is enabled
      final saveButton = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('my_account_save_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('renders desktop overview badge on wide screens',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final suspendedUser = UserProfile(
        id: 'susp-desk-1',
        email: 'desk@example.com',
        username: 'desk_user',
        role: 'owner',
        accountStatus: 'suspended',
        suspensionReason: 'Administrative review required',
      );

      await tester.pumpWidget(_buildTestApp(user: suspendedUser));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account_suspended_banner')), findsOneWidget);
      expect(find.byKey(const Key('account_status_badge')), findsOneWidget);
      expect(find.byKey(const Key('account_status_overview_badge')),
          findsOneWidget);
    });

    testWidgets('renders Arabic localization correctly for suspended account',
        (tester) async {
      final suspendedUser = UserProfile(
        id: 'susp-ar-1',
        email: 'ar@example.com',
        username: 'ar_user',
        role: 'user',
        accountStatus: 'suspended',
      );

      await tester.pumpWidget(
          _buildTestApp(user: suspendedUser, locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.text('الحساب معلق'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('account_status_badge')),
          matching: find.text('معلق'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
            'تم تعليق حسابك من قبل الإدارة. يرجى التواصل مع الدعم الفني لمزيد من المعلومات.'),
        findsOneWidget,
      );
    });
  });
}
