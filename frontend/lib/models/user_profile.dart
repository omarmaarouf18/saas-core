class UserProfile {
  final String id;
  final String email;
  final String username;
  final String role;
  final String? tenantId;
  final String? kycStatus;
  final String? kyeStatus;
  final String? rejectionReason;
  final String? idFrontDoc;
  final String? idBackDoc;
  final String? selfieDoc;
  final String? businessProofDoc;

  UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    this.tenantId,
    this.kycStatus,
    this.kyeStatus,
    this.rejectionReason,
    this.idFrontDoc,
    this.idBackDoc,
    this.selfieDoc,
    this.businessProofDoc,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['user_id'] ?? json['id'] ?? '',
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      role: json['role'] ?? '',
      tenantId: json['tenant_id'],
      kycStatus: json['kyc_status'],
      kyeStatus: json['kye_status'],
      rejectionReason: json['rejection_reason'],
      idFrontDoc: json['id_front_doc'],
      idBackDoc: json['id_back_doc'],
      selfieDoc: json['selfie_doc'],
      businessProofDoc: json['business_proof_doc'],
    );
  }

  String get effectiveKycStatus {
    if (role == 'employee') {
      return kyeStatus ?? '';
    }
    return kycStatus ?? '';
  }

  bool get isApproved => effectiveKycStatus == 'approved';
  bool get isPendingApproval =>
      effectiveKycStatus == 'pending_super_admin_approval';
  bool get isRejected => effectiveKycStatus == 'rejected';
  bool get isUnverified =>
      effectiveKycStatus.isEmpty ||
      effectiveKycStatus == 'none' ||
      effectiveKycStatus == 'unverified';
}
