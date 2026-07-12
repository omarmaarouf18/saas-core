class UserProfile {
  final String id;
  final String email;
  final String role;
  final String? tenantId;
  final String? kycStatus;

  UserProfile({
    required this.id,
    required this.email,
    required this.role,
    this.tenantId,
    this.kycStatus,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['user_id'] ?? json['id'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      tenantId: json['tenant_id'],
      kycStatus: json['kyc_status'],
    );
  }
}
