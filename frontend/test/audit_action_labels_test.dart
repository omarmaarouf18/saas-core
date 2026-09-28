import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/audit_labels.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/employee_screen.dart';

/// F1: the owner audit trail shows friendly localized labels, never the raw
/// backend action code, and never the client IP.
void main() {
  group('auditActionLabel mapping (EN)', () {
    final l10n = AppLocalizationsEn();

    test('known machine codes map to friendly labels', () {
      expect(auditActionLabel(l10n, 'ACCOUNT_SUSPENDED'), 'Account suspended');
      expect(
          auditActionLabel(l10n, 'ACCOUNT_REACTIVATED'), 'Account reactivated');
      expect(
          auditActionLabel(l10n, 'KYC_REVIEWED'), 'Identity review completed');
      expect(auditActionLabel(l10n, 'DOCUMENT_VIEWED'), 'Document viewed');
    });

    test('unknown codes fall back to humanized sentence case, never raw', () {
      expect(auditActionLabel(l10n, 'SOME_NEW_EVENT'), 'Some new event');
      expect(auditActionLabel(l10n, 'BOOKING_ATTEMPT_CLOSED_BUSINESS'),
          'Booking attempt closed business');
      // The fallback is never the identity function on the raw code.
      expect(
          humanizeAuditAction('SOME_NEW_EVENT') == 'SOME_NEW_EVENT', isFalse);
    });

    test('free-form employee-typed actions pass through untouched', () {
      expect(auditActionLabel(l10n, 'Arrived at Pickup'), 'Arrived at Pickup');
    });

    test('empty action falls back to the unknown-action label', () {
      expect(auditActionLabel(l10n, ''), l10n.unknownActionLabel);
      expect(auditActionLabel(l10n, '   '), l10n.unknownActionLabel);
    });
  });

  group('auditActionLabel mapping (AR)', () {
    final l10n = AppLocalizationsAr();

    test('known machine codes map to Egyptian Arabic labels without parens',
        () {
      expect(auditActionLabel(l10n, 'ACCOUNT_SUSPENDED'), 'تم تجميد الحساب');
      expect(auditActionLabel(l10n, 'KYC_REVIEWED'), 'مراجعة الهوية اكتملت');
      for (final label in [
        auditActionLabel(l10n, 'ACCOUNT_SUSPENDED'),
        auditActionLabel(l10n, 'ACCOUNT_REACTIVATED'),
        auditActionLabel(l10n, 'KYC_REVIEWED'),
        auditActionLabel(l10n, 'DOCUMENT_VIEWED'),
      ]) {
        expect(label.contains('('), isFalse);
        expect(label.contains(')'), isFalse);
      }
    });
  });

  group('humanizeAuditAction fallback', () {
    test('underscores become spaces with sentence case', () {
      expect(humanizeAuditAction('ACCOUNT_SUSPENDED'), 'Account suspended');
      expect(humanizeAuditAction('A_B_C'), 'A b c');
    });

    test('already-lowercase input is sentence-cased, never uppercased', () {
      expect(humanizeAuditAction('arrived at pickup'), 'Arrived at pickup');
    });
  });

  testWidgets('Audit trail card renders friendly labels with no IP text (F1)',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockOwner = _MockOwnerProvider(apiClient);
    mockOwner.mockIsLoading = false;
    mockOwner.mockAuditLogEntries = [
      {
        'action': 'ACCOUNT_SUSPENDED',
        'timestamp': '2026-09-01T10:00:00Z',
        'client_ip': '192.168.1.50',
      },
      {
        'action': 'KYC_REVIEWED',
        'timestamp': '2026-09-02T11:00:00Z',
        'client_ip': '10.0.0.9',
      },
      {
        'action': 'SOME_NEW_EVENT',
        'timestamp': '2026-09-03T12:00:00Z',
        'client_ip': '',
      },
    ];

    await tester.pumpWidget(_buildEmployeeScreen(mockOwner));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Audit Trail'));
    await tester.pumpAndSettle();

    // Friendly labels render...
    expect(find.text('Account suspended'), findsOneWidget);
    expect(find.text('Identity review completed'), findsOneWidget);
    expect(find.text('Some new event'), findsOneWidget);

    // ...raw uppercase codes never do...
    expect(find.text('ACCOUNT_SUSPENDED'), findsNothing);
    expect(find.text('KYC_REVIEWED'), findsNothing);
    expect(find.text('SOME_NEW_EVENT'), findsNothing);

    // ...and no client IP leaks into the owner UI.
    expect(find.textContaining('192.168.1.50'), findsNothing);
    expect(find.textContaining('10.0.0.9'), findsNothing);
    expect(find.textContaining('IP:'), findsNothing);
  });
}

class _MockAuthProvider extends AuthProvider {
  _MockAuthProvider(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-1',
        email: 'owner@example.com',
        username: 'OwnerUser',
        role: 'owner',
      );

  @override
  String? get token => 'test-owner-token';

  @override
  Future<void> fetchUserProfile() async {}
}

class _MockOwnerProvider extends OwnerProvider {
  List<dynamic> mockEmployees = [];
  bool mockIsLoading = false;
  String? mockError;
  List<Map<String, dynamic>> mockAuditLogEntries = [];

  _MockOwnerProvider(super.apiClient);

  @override
  List<dynamic> get employees => mockEmployees;

  @override
  bool get isLoading => mockIsLoading;

  @override
  String? get error => mockError;

  @override
  List<Map<String, dynamic>> get auditLogEntries => mockAuditLogEntries;

  @override
  Future<List<dynamic>> fetchEmployees([String? ownerToken]) async =>
      mockEmployees;

  @override
  Future<void> fetchAuditLog({
    String? tenantId,
    String? requesterToken,
    String? userId,
    String? userToken,
  }) async {}
}

Widget _buildEmployeeScreen(_MockOwnerProvider ownerProvider) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
          value: _MockAuthProvider(apiClient)),
      ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
    ],
    child: const MaterialApp(
      home: EmployeeScreen(),
    ),
  );
}
