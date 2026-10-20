import '../../../l10n/app_localizations.dart';
import '../../../models/support_ticket.dart';
import '../../../ui/qd_ui.dart';

/// `POST /chat/tickets` takes one free-text `context_id`; the subject and
/// description travel inside it. Same format as the old CreateTicketDialog,
/// so tickets made by either client read the same in the ops console:
/// `Job #<job id> - <subject>: <description>`, or `<subject>: <description>`
/// without an order.
String buildTicketContext(
    {String? jobId, required String subject, required String description}) {
  final body = '$subject: $description';
  return jobId == null || jobId.isEmpty ? body : 'Job #$jobId - $body';
}

/// What a ticket's `context_id` says.
class TicketContext {
  const TicketContext({this.jobId, required this.subject, this.description});

  final String? jobId;
  final String subject;
  final String? description;
}

final RegExp _withJob = RegExp(r'^Job #(\S+) - (.*)$', dotAll: true);

/// Reads [buildTicketContext]'s format back. Anything else (older tickets,
/// a bare job id) becomes the subject; a bare job id is also the job.
TicketContext parseTicketContext(String? raw) {
  final text = (raw ?? '').trim();
  String? jobId;
  var rest = text;
  final m = _withJob.firstMatch(text);
  if (m != null) {
    jobId = m.group(1);
    rest = m.group(2)!;
  } else if (RegExp(r'^[A-Za-z0-9-]{8,}$').hasMatch(text)) {
    // The order view used to send the plain job id.
    return TicketContext(jobId: text, subject: '');
  }
  final colon = rest.indexOf(': ');
  if (colon == -1) return TicketContext(jobId: jobId, subject: rest);
  return TicketContext(
    jobId: jobId,
    subject: rest.substring(0, colon).trim(),
    description: rest.substring(colon + 2).trim(),
  );
}

/// The subject shown for [ticket]: the server's subject, else the one in
/// the context, else "Complaint #<first 8 id characters>".
String ticketSubject(AppLocalizations l10n, SupportTicket ticket) {
  final server = ticket.subject?.trim() ?? '';
  if (server.isNotEmpty) return server;
  final parsed = parseTicketContext(ticket.contextId).subject;
  if (parsed.isNotEmpty) return parsed;
  return l10n.supComplaintRef(ticketRef(ticket.id));
}

/// `#` + first 8 id characters, upper case, in a left-to-right isolate.
String ticketRef(String id) {
  final short = id.length > 8 ? id.substring(0, 8) : id;
  return '\u2066#${short.toUpperCase()}\u2069';
}

/// `#QD-` order reference for a job id, in a left-to-right isolate (same
/// format as the order pages).
String orderRefOf(String jobId) {
  final short = jobId.length > 8 ? jobId.substring(0, 8) : jobId;
  return '\u2066#QD-${short.toUpperCase()}\u2069';
}

/// Status chip of a ticket (pending / assigned / resolved).
(String, QdTone) ticketStatusChip(AppLocalizations l10n, String status) =>
    switch (status.trim().toLowerCase()) {
      'pending' => (l10n.supStatusPending, QdTone.warning),
      'assigned' => (l10n.supStatusAssigned, QdTone.success),
      'resolved' => (l10n.supStatusResolved, QdTone.neutral),
      _ => (l10n.supStatusOpen, QdTone.neutral),
    };
