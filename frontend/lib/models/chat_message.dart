class ChatMessage {
  final String? id;
  final String channel;
  final String senderId;
  final String senderUsername;
  final String content;
  final String type; // "message", "join", "leave", "location_update"
  final DateTime? createdAt;

  final String? attachmentKey;
  final String? attachmentUrl;
  final String? attachmentName;
  final String? attachmentType;
  final int? attachmentSize;

  ChatMessage({
    this.id,
    required this.channel,
    required this.senderId,
    required this.senderUsername,
    required this.content,
    required this.type,
    this.createdAt,
    this.attachmentKey,
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentType,
    this.attachmentSize,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    if (json['created_at'] != null) {
      dt = DateTime.tryParse(json['created_at'].toString());
    } else if (json['timestamp'] != null) {
      dt = DateTime.tryParse(json['timestamp'].toString());
    }
    return ChatMessage(
      id: json['id']?.toString(),
      channel: json['channel'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderUsername: json['sender_username'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? 'message',
      createdAt: dt,
      attachmentKey: json['attachment_key']?.toString(),
      attachmentUrl: json['attachment_url']?.toString(),
      attachmentName: json['attachment_name']?.toString(),
      attachmentType: json['attachment_type']?.toString(),
      attachmentSize: json['attachment_size'] != null
          ? int.tryParse(json['attachment_size'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'channel': channel,
        'sender_id': senderId,
        'sender_username': senderUsername,
        'content': content,
        'type': type,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (attachmentKey != null) 'attachment_key': attachmentKey,
        if (attachmentUrl != null) 'attachment_url': attachmentUrl,
        if (attachmentName != null) 'attachment_name': attachmentName,
        if (attachmentType != null) 'attachment_type': attachmentType,
        if (attachmentSize != null) 'attachment_size': attachmentSize,
      };
}
