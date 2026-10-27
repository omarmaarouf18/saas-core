import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/saved_address.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';

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
    List<SavedAddress>? savedAddresses,
    bool? twoFactorEnabled,
    String? password,
  }) async =>
      true;
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

}
