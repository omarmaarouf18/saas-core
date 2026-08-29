class NotificationModel {
  final String id;
  final String type;
  final String tenantId;

  /// Present when the sender targets a specific user (e.g. KYC review
  /// outcomes per ADR-0021). Null for tenant-wide broadcasts.
  final String? userId;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.type,
    required this.tenantId,
    this.userId,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'system',
      tenantId: json['tenant_id'] as String? ?? '',
      userId: json['user_id'] as String?,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'tenant_id': tenantId,
      if (userId != null) 'user_id': userId,
      'title': title,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
    };
  }
}
