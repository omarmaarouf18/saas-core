class PayoutRequest {
  final String id;
  final String tenantId;
  final double amount;
  final String status;
  final String payoutMethod;
  final String? accountDetails;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  PayoutRequest({
    required this.id,
    required this.tenantId,
    required this.amount,
    required this.status,
    required this.payoutMethod,
    this.accountDetails,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PayoutRequest.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    return PayoutRequest(
      id: json['id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'requested',
      payoutMethod: json['payout_method'] as String? ?? '',
      accountDetails: json['account_details'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'amount': amount,
      'status': status,
      'payout_method': payoutMethod,
      if (accountDetails != null) 'account_details': accountDetails,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
