import 'dart:convert';

class NotificationLocalizedText {
  final String title;
  final String body;

  const NotificationLocalizedText({this.title = '', this.body = ''});

  factory NotificationLocalizedText.fromJson(dynamic json) {
    if (json is! Map) return const NotificationLocalizedText();
    return NotificationLocalizedText(
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationLocalizedText &&
          other.title == title &&
          other.body == body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => 'NotificationLocalizedText(title: $title, body: $body)';
}

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

  /// Template parameters (PUSH-L10N): e.g. `ticket_id`, `variant`,
  /// `deep_link`, `title_ar`, etc.
  final Map<String, String> params;

  /// Localized titles and bodies keyed by language code (`ar`, `en`),
  /// rendered server-side when the notification type has a template.
  final Map<String, NotificationLocalizedText> texts;

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
    Map<String, String>? params,
    Map<String, NotificationLocalizedText>? texts,
  })  : params = params == null ? const {} : Map.unmodifiable(params),
        texts = texts == null ? const {} : Map.unmodifiable(texts);

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
      params: _parseParams(json['params']),
      texts: _parseTexts(json['texts']),
    );
  }

  static String? _nonEmpty(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static Map<String, String> _parseParams(dynamic raw) {
    if (raw == null) return const {};
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return _parseParams(decoded);
      } catch (_) {}
      return const {};
    }
    if (raw is! Map) return const {};
    final map = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString().trim();
      if (key == null || key.isEmpty) continue;
      final val = entry.value?.toString() ?? '';
      map[key] = val;
    }
    return map;
  }

  static Map<String, NotificationLocalizedText> _parseTexts(dynamic raw) {
    if (raw == null) return const {};
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return _parseTexts(decoded);
      } catch (_) {}
      return const {};
    }
    if (raw is! Map) return const {};
    final map = <String, NotificationLocalizedText>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString().trim();
      if (key == null || key.isEmpty) continue;
      if (entry.value is Map) {
        map[key] = NotificationLocalizedText.fromJson(entry.value);
      }
    }
    return map;
  }

  /// The stable event type: `event_type` (job notifications, BE-GAPS-FIX;
  /// equal to `type` there), else `type`, else `system`.
  static String typeOf(Map<String, dynamic> data) =>
      _nonEmpty(data['event_type']) ?? _nonEmpty(data['type']) ?? 'system';

  /// A push message's data (FCM sends strings: `id`, `type`, `tenant_id`,
  /// and `job_id` + `event_type` for job notifications) with the shown
  /// [title] and [body].
  factory NotificationModel.fromPushData(Map<String, dynamic> data,
      {String title = '', String body = ''}) {
    final parsedParams = Map<String, String>.from(_parseParams(data['params']));
    final dl = _nonEmpty(data['deep_link']);
    if (dl != null && !parsedParams.containsKey('deep_link')) {
      parsedParams['deep_link'] = dl;
    }
    return NotificationModel(
      id: data['id']?.toString() ?? '',
      type: typeOf(data),
      tenantId: data['tenant_id']?.toString() ?? '',
      userId: _nonEmpty(data['user_id']),
      jobId: _nonEmpty(data['job_id']),
      title: title,
      body: body,
      timestamp: DateTime.now(),
      params: parsedParams,
      texts: _parseTexts(data['texts']),
    );
  }

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
      if (params.isNotEmpty) 'params': params,
      if (texts.isNotEmpty)
        'texts': texts.map((k, v) => MapEntry(k, v.toJson())),
    };
  }
}
