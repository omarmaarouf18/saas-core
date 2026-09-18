class ChatMessage {
  final String? id;
  final String channel;
  final String senderId;
  final String senderUsername;
  final String content;
  final String type; // "message", "join", "leave", "location_update"
  final DateTime? createdAt;

  ChatMessage({
    this.id,
    required this.channel,
    required this.senderId,
    required this.senderUsername,
    required this.content,
    required this.type,
    this.createdAt,
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
      };
}
