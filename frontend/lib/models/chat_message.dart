class ChatMessage {
  final String channel;
  final String senderId;
  final String senderUsername;
  final String content;
  final String type; // "message", "join", "leave", "location_update"

  ChatMessage({
    required this.channel,
    required this.senderId,
    required this.senderUsername,
    required this.content,
    required this.type,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      channel: json['channel'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderUsername: json['sender_username'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? 'message',
    );
  }

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'sender_id': senderId,
        'sender_username': senderUsername,
        'content': content,
        'type': type,
      };
}
