class SupportTicket {
  final String id;
  final String customerId;
  final String? assignedAgentId;
  final String? contextId;
  final String? subject;
  final String status; // 'pending', 'assigned', 'resolved'
  final String? resolutionNote;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  SupportTicket({
    required this.id,
    required this.customerId,
    this.assignedAgentId,
    this.contextId,
    this.subject,
    required this.status,
    this.resolutionNote,
    this.resolvedBy,
    this.resolvedAt,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isResolved => status.toLowerCase() == 'resolved';
  bool get isAssigned => status.toLowerCase() == 'assigned';
  bool get isPending => status.toLowerCase() == 'pending';

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      id: json['ticket_id'] as String? ?? json['id'] as String? ?? '',
      customerId: json['customer_id'] as String? ?? '',
      assignedAgentId: json['assigned_agent_id'] as String?,
      contextId: json['context_id'] as String?,
      subject: json['subject'] as String?,
      status: json['status'] as String? ?? 'pending',
      resolutionNote: json['resolution_note'] as String?,
      resolvedBy: json['resolved_by'] as String?,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ticket_id': id,
      'customer_id': customerId,
      if (assignedAgentId != null) 'assigned_agent_id': assignedAgentId,
      if (contextId != null) 'context_id': contextId,
      if (subject != null) 'subject': subject,
      'status': status,
      if (resolutionNote != null) 'resolution_note': resolutionNote,
      if (resolvedBy != null) 'resolved_by': resolvedBy,
      if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
