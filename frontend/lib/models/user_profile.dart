class UserProfile {
  final String id;
  final String email;
  final String username;
  final String? phone;
  final List<String>? frequentAddresses;
  final String role;
  final String? tenantId;
  final String? kycStatus;
  final String? kyeStatus;
  final String? rejectionReason;
  final String? idFrontDoc;
  final String? idBackDoc;
  final String? selfieDoc;
  final String? businessProofDoc;
  final String? accountStatus;
  final String? suspensionReason;
  final bool twoFactorEnabled;

  UserProfile({
    required this.id,
    required this.email,
    required this.username,
    this.phone,
    this.frequentAddresses,
    required this.role,
    this.tenantId,
    this.kycStatus,
    this.kyeStatus,
    this.rejectionReason,
    this.idFrontDoc,
    this.idBackDoc,
    this.selfieDoc,
    this.businessProofDoc,
    this.accountStatus,
    this.suspensionReason,
    this.twoFactorEnabled = true,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    List<String>? addresses;
    if (json['frequent_addresses'] != null &&
        json['frequent_addresses'] is List) {
      addresses = (json['frequent_addresses'] as List)
          .map((e) => e.toString())
          .toList();
    }

    final twoFactorRaw = json['two_factor_enabled'];
    final bool twoFactorEnabled = twoFactorRaw is bool ? twoFactorRaw : true;

    return UserProfile(
      id: json['user_id'] ?? json['id'] ?? '',
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      phone: json['phone'],
      frequentAddresses: addresses,
      role: json['role'] ?? '',
      tenantId: json['tenant_id'],
      kycStatus: json['kyc_status'],
      kyeStatus: json['kye_status'],
      rejectionReason: json['rejection_reason'],
      idFrontDoc: json['id_front_doc'],
      idBackDoc: json['id_back_doc'],
      selfieDoc: json['selfie_doc'],
      businessProofDoc: json['business_proof_doc'],
      accountStatus: json['account_status'] as String?,
      suspensionReason: json['suspension_reason'] as String?,
      twoFactorEnabled: twoFactorEnabled,
    );
  }

  UserProfile copyWith({
    String? id,
    String? email,
    String? username,
    String? phone,
    List<String>? frequentAddresses,
    String? role,
    String? tenantId,
    String? kycStatus,
    String? kyeStatus,
    String? rejectionReason,
    String? idFrontDoc,
    String? idBackDoc,
    String? selfieDoc,
    String? businessProofDoc,
    String? accountStatus,
    String? suspensionReason,
    bool? twoFactorEnabled,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      frequentAddresses: frequentAddresses ?? this.frequentAddresses,
      role: role ?? this.role,
      tenantId: tenantId ?? this.tenantId,
      kycStatus: kycStatus ?? this.kycStatus,
      kyeStatus: kyeStatus ?? this.kyeStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      idFrontDoc: idFrontDoc ?? this.idFrontDoc,
      idBackDoc: idBackDoc ?? this.idBackDoc,
      selfieDoc: selfieDoc ?? this.selfieDoc,
      businessProofDoc: businessProofDoc ?? this.businessProofDoc,
      accountStatus: accountStatus ?? this.accountStatus,
      suspensionReason: suspensionReason ?? this.suspensionReason,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
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
  bool get isSuspended => accountStatus == 'suspended';
  bool get isActiveAccount => !isSuspended;
}
