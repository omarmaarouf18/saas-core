class NotificationModel {
  final String id;
  final String type;
  final String tenantId;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.type,
    required this.tenantId,
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
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      isRead: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'tenant_id': tenantId,
      'title': title,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
