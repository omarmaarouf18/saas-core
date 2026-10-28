class NotificationModel {
  final String id;
  final String type;
  final String tenantId;

  /// Present when the sender targets a specific user (e.g. KYC review
  /// outcomes per ADR-0021). Null for tenant-wide broadcasts.
  final String? userId;

  /// The job the notification is about (`job_id`, USER-AUTH-BE item 7);
  /// null for other notifications and older payloads.
  final String? jobId;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.type,
    required this.tenantId,
    this.userId,
    this.jobId,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String? ?? '',
      type: typeOf(json),
      tenantId: json['tenant_id'] as String? ?? '',
      userId: json['user_id'] as String?,
      jobId: _nonEmpty(json['job_id']),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  static String? _nonEmpty(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  /// The stable event type: `event_type` (job notifications, BE-GAPS-FIX;
  /// equal to `type` there), else `type`, else `system`.
  static String typeOf(Map<String, dynamic> data) =>
      _nonEmpty(data['event_type']) ?? _nonEmpty(data['type']) ?? 'system';

  /// A push message's data (FCM sends strings: `id`, `type`, `tenant_id`,
  /// and `job_id` + `event_type` for job notifications) with the shown
  /// [title] and [body].
  factory NotificationModel.fromPushData(Map<String, dynamic> data,
          {String title = '', String body = ''}) =>
      NotificationModel(
        id: data['id']?.toString() ?? '',
        type: typeOf(data),
        tenantId: data['tenant_id']?.toString() ?? '',
        userId: _nonEmpty(data['user_id']),
        jobId: _nonEmpty(data['job_id']),
        title: title,
        body: body,
        timestamp: DateTime.now(),
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'tenant_id': tenantId,
      if (userId != null) 'user_id': userId,
      if (jobId != null) 'job_id': jobId,
      'title': title,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
    };
  }
}
