import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../models/notification_model.dart';
import '../../../models/support_ticket.dart';
import '../../verification/verification_page.dart';
import '../support/tickets_page.dart';

/// Where tapping a notification leads.
enum NotificationTargetKind {
  none,

  /// Customer: My orders. Owner: the Orders tab (no job id in the body).
  orders,

  /// Owner: the order detail of [NotificationTarget.id].
  order,

  /// Owner: the Team tab.
  team,

  /// Owner: the plan page.
  plan,

  /// Owner and courier: the verification page (KYB / KYE).
  verification,

  /// Courier: the Task tab (the offer, or the current job).
  task,

  /// Courier: My jobs.
  jobs,

  /// Support: the chat of ticket [NotificationTarget.id].
  ticket,

  /// Support: the ticket list.
  tickets,

  /// The exact job [NotificationTarget.id] (the payload's `job_id`), for
  /// the signed-in role: customer → the order page, owner → the order
  /// detail, courier → the offer / current job (Task) or My jobs. Where
  /// the shell cannot open a job, [NotificationTarget.fallback] is used.
  job,
}

class NotificationTarget {
  const NotificationTarget(this.kind, [this.id, this.fallback]);

  static const none = NotificationTarget(NotificationTargetKind.none);

  final NotificationTargetKind kind;

  /// The ticket id ([NotificationTargetKind.ticket]) or the job id
  /// ([NotificationTargetKind.order], [NotificationTargetKind.job]).
  final String? id;

  /// For [NotificationTargetKind.job]: where the link led before job ids
  /// were sent (by type alone).
  final NotificationTarget? fallback;

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      other.kind == kind &&
      other.id == id &&
      other.fallback == fallback;

  @override
  int get hashCode => Object.hash(kind, id, fallback);

  @override
  String toString() => 'NotificationTarget($kind, $id'
      '${fallback == null ? '' : ', fallback: $fallback'})';
}

/// Stable event types about one job (USER-AUTH-BE item 7, BE-GAPS-FIX
/// item 1). With a `job_id` they open that job. The payload's `event_type`
/// (= `type` for job notifications) is read first, then `type`.
///
/// Sent today: `job_booked` (to the owner), `job_offer` / `job_alert` (to
/// the courier), `job_accepted`, `job_picked_up`, `job_delivered` and
/// `job_cancelled` (to the customer; cancelled only when someone else
/// cancels), `job_unavailable`, and the cancellation / dispute types.
/// `job_in_transit` and `job_completed` are never sent (picked up is the
/// in-transit event; delivered is the completion); they stay here so old
/// history items keep routing.
const Set<String> kJobEventTypes = {
  'job_booked',
  'job_accepted',
  'job_picked_up',
  'job_in_transit',
  'job_delivered',
  'job_completed',
  'job_cancelled',
  'job_unavailable',
  'job_update',
  'job_offer',
  'job_alert',
  'cancellation_requested',
  'cancellation_request_expired',
  'cancellation_resolved',
  'dispute_resolved',
};

/// Customer notification types that are about an order. Without a
/// `job_id` (older history items) they open My orders; with one, the
/// order itself ([kJobEventTypes]).
const Set<String> kOrderNotificationTypes = {
  'job_booked',
  'job_accepted',
  'job_picked_up',
  'job_in_transit',
  'job_delivered',
  'job_unavailable',
  'job_cancelled',
  'job_completed',
  'job_update',
  'dispute_resolved',
};

const Set<String> kTicketNotificationTypes = {
  'ticket_resolved',
  'ticket_assigned',
};

/// Owner notification types about one order (user-service: cancellation
/// requests, their expiry, dispute results). The job id is only in the
/// body ("... job <id> ..."), so the link opens that order when the id is
/// found and the Orders tab otherwise.
const Set<String> kOwnerOrderNotificationTypes = {
  'cancellation_requested',
  'cancellation_request_expired',
  'dispute_resolved',
};

/// Verification results (auth-service), sent to the reviewed owner or
/// courier.
const Set<String> kVerificationNotificationTypes = {
  'kyc_approved',
  'kyc_rejected',
};

/// Courier notification types that lead to the offer or the current job.
const Set<String> kCourierTaskNotificationTypes = {'job_offer', 'job_alert'};

/// The deep link for [n] when the signed-in user has [role].
///
/// Each role only gets links to its own screens: a courier's job offer
/// never opens an owner page, an owner's cancellation request never opens
/// a courier page, and a role the app does not know gets none (the old
/// screen linked whatever the role).
NotificationTarget notificationTarget(NotificationModel n, String? role) {
  final byType = _targetByType(n, role);
  final jobId = n.jobId;
  if (byType == NotificationTarget.none &&
      !(role == 'user' || role == 'owner' || role == 'employee')) {
    return byType;
  }
  if (jobId != null && kJobEventTypes.contains(n.type)) {
    return NotificationTarget(NotificationTargetKind.job, jobId, byType);
  }
  return byType;
}

/// The link by type alone (no job id, or a type that is not about a job).
NotificationTarget _targetByType(NotificationModel n, String? role) {
  if (role != 'user' && role != 'owner' && role != 'employee') {
    return NotificationTarget.none;
  }
  if (kTicketNotificationTypes.contains(n.type)) {
    final id = ticketIdFromBody(n.body);
    return id == null
        ? const NotificationTarget(NotificationTargetKind.tickets)
        : NotificationTarget(NotificationTargetKind.ticket, id);
  }
  switch (role) {
    case 'user':
      if (kOrderNotificationTypes.contains(n.type)) {
        return const NotificationTarget(NotificationTargetKind.orders);
      }
    case 'owner':
      if (kVerificationNotificationTypes.contains(n.type)) {
        return const NotificationTarget(NotificationTargetKind.verification);
      }
      if (n.type.startsWith('subscription_')) {
        return const NotificationTarget(NotificationTargetKind.plan);
      }
      if (n.type.startsWith('employee_')) {
        return const NotificationTarget(NotificationTargetKind.team);
      }
      if (kOwnerOrderNotificationTypes.contains(n.type)) {
        final id = jobIdFromBody(n.body);
        return id == null
            ? const NotificationTarget(NotificationTargetKind.orders)
            : NotificationTarget(NotificationTargetKind.order, id);
      }
    case 'employee':
      if (kVerificationNotificationTypes.contains(n.type)) {
        return const NotificationTarget(NotificationTargetKind.verification);
      }
      if (kCourierTaskNotificationTypes.contains(n.type)) {
        return const NotificationTarget(NotificationTargetKind.task);
      }
      if (n.type == 'cancellation_resolved') {
        // Approved: the job is cancelled, so it is in My jobs. Declined:
        // the courier keeps it, so it is the current job.
        return n.body.toLowerCase().contains('approved')
            ? const NotificationTarget(NotificationTargetKind.jobs)
            : const NotificationTarget(NotificationTargetKind.task);
      }
      if (n.type == 'dispute_resolved' || n.type.startsWith('job_')) {
        return const NotificationTarget(NotificationTargetKind.jobs);
      }
  }
  return NotificationTarget.none;
}

/// The job id user-service puts in owner and courier notification bodies:
/// "... cancellation of job <id>: ...", "... and job <id> returned to
/// dispatch." Ids carry a digit, so words after "job" ("job offer for
/// job <id>") are skipped. Null when the body names no job.
String? jobIdFromBody(String body) =>
    RegExp(r'\bjob ([A-Za-z_-]*[0-9][A-Za-z0-9_-]*)')
        .firstMatch(body)
        ?.group(1);

/// The ticket id chat-service puts in ticket notification bodies:
/// "Your ticket (<id>) has been resolved: …", "… joined your ticket (<id>)".
/// Same parsing as the old screen: the first parenthesised token, else a
/// raw `tkt-…` / `ticket-…` token.
String? ticketIdFromBody(String body) {
  final paren = RegExp(r'\(([^)\s]+)\)').firstMatch(body)?.group(1);
  final raw = RegExp(r'\b(tkt-[a-zA-Z0-9_-]+|ticket-[a-zA-Z0-9_-]+)\b',
          caseSensitive: false)
      .firstMatch(body)
      ?.group(1);
  final id = paren ?? raw;
  return id == null || id.isEmpty ? null : id;
}

/// Title and body shown for [n]: localized copy for the types the
/// services send (their own text is English and, for an accepted order,
/// quotes the fare in dollars), the server text otherwise.
(String, String) notificationCopy(AppLocalizations l10n, NotificationModel n) {
  switch (n.type) {
    case 'job_accepted':
      return (l10n.ntfAcceptedTitle, l10n.ntfAcceptedBody);
    case 'job_unavailable':
      return (l10n.ntfUnavailableTitle, l10n.ntfUnavailableBody);
    case 'job_cancelled':
      return (l10n.ntfCancelledTitle, l10n.ntfOrdersBody);
    case 'job_completed':
      return (l10n.ntfCompletedTitle, l10n.ntfOrdersBody);
    case 'job_picked_up':
      return (l10n.ntfPickedUpTitle, l10n.ntfPickedUpBody);
    case 'job_booked':
      return (l10n.ntfBookedTitle, n.body);
    case 'job_in_transit':
      return (l10n.ntfInTransitTitle, n.body);
    case 'job_delivered':
      return (l10n.ntfDeliveredTitle, n.body);
    case 'ticket_resolved':
      // The resolution note follows "has been resolved: ".
      final i = n.body.indexOf('resolved: ');
      final note = i == -1 ? '' : n.body.substring(i + 'resolved: '.length);
      return (l10n.ntfTicketResolvedTitle, note.trim().isEmpty ? n.body : note);
    case 'ticket_assigned':
      return (l10n.ntfTicketAssignedTitle, l10n.ntfTicketAssignedBody);
    case 'dispute_resolved':
      return (l10n.ntfDisputeTitle, n.body);
    // Owner and courier types: a localized title over the server text,
    // which carries the reason or the job.
    case 'cancellation_requested':
      return (l10n.ntfCancelRequestedTitle, n.body);
    case 'cancellation_request_expired':
      return (l10n.ntfCancelExpiredTitle, n.body);
    case 'cancellation_resolved':
      return (l10n.ntfCancelResolvedTitle, n.body);
    case 'job_offer':
      return (l10n.ntfJobOfferTitle, l10n.ntfJobOfferBody);
    case 'job_alert':
      return (l10n.ntfJobAlertTitle, n.body);
    case 'kyc_approved':
      return (l10n.ntfKycApprovedTitle, n.body);
    case 'kyc_rejected':
      return (l10n.ntfKycRejectedTitle, n.body);
  }
  return (n.title, n.body);
}

/// Notifications grouped by local calendar day, newest day first; the
/// order inside a day is kept.
List<(DateTime, List<NotificationModel>)> groupByDay(
    List<NotificationModel> list) {
  final groups = <(DateTime, List<NotificationModel>)>[];
  for (final n in list) {
    final t = n.timestamp.toLocal();
    final day = DateTime(t.year, t.month, t.day);
    if (groups.isNotEmpty && groups.last.$1 == day) {
      groups.last.$2.add(n);
    } else {
      groups.add((day, [n]));
    }
  }
  return groups;
}

/// "We couldn't open that order": a job link whose job is gone, is not the
/// user's, or could not be loaded. The shell then shows its order list.
void showJobNotFoundNotice(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      key: const Key('ntf_job_missing'),
      content: Text(context.l10n.ntfJobNotFound),
    ));
}

/// What the signed-in role's shell can show for a notification link.
/// Each shell provides its own through [NotificationShellScope]; a link the
/// shell does not offer does nothing.
class NotificationShellLinks {
  const NotificationShellLinks({
    this.showOrders,
    this.openOrder,
    this.showTeam,
    this.openPlan,
    this.showTask,
    this.showJobs,
    this.openJob,
  });

  /// Customer: the My orders tab. Owner: the Orders tab.
  final VoidCallback? showOrders;

  /// Opens one job for this role (FE-BE-GAPS): customer → its order page,
  /// owner → its order detail, courier → Task (offer / current job) or My
  /// jobs. Each shell checks the job exists and is the user's, and says so
  /// when it is not.
  final void Function(String jobId)? openJob;

  /// Owner: the order detail of a job id.
  final void Function(String jobId)? openOrder;

  /// Owner: the Team tab.
  final VoidCallback? showTeam;

  /// Owner: the plan page.
  final VoidCallback? openPlan;

  /// Courier: the Task tab (offer or current job).
  final VoidCallback? showTask;

  /// Courier: the My jobs tab.
  final VoidCallback? showJobs;
}

/// Provided by each role shell: the [NotificationShellLinks] it offers.
class NotificationShellScope extends InheritedWidget {
  const NotificationShellScope(
      {super.key, required this.links, required super.child});

  final NotificationShellLinks links;

  static NotificationShellLinks? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NotificationShellScope>()
      ?.links;

  @override
  bool updateShouldNotify(NotificationShellScope oldWidget) =>
      links != oldWidget.links;
}

/// Where the notification links go. Swappable for tests; the default
/// ([NotificationLinks.of]) closes the notifications page and lets the
/// shell show the tab or page, and opens the support and verification
/// pages itself.
class NotificationLinks {
  const NotificationLinks({
    this.openOrders,
    this.openOrder,
    this.openTeam,
    this.openPlan,
    this.openVerification,
    this.openTask,
    this.openJobs,
    this.openTicket,
    this.openTickets,
    this.openJob,
  });

  /// Links for a notifications page opened from [context] (inside a role
  /// shell).
  factory NotificationLinks.of(BuildContext context) {
    final shell = NotificationShellScope.maybeOf(context);
    void Function(BuildContext)? backTo(VoidCallback? show) => show == null
        ? null
        : (ctx) {
            Navigator.of(ctx).popUntil((route) => route.isFirst);
            show();
          };
    final openOrder = shell?.openOrder;
    final openJob = shell?.openJob;
    return NotificationLinks(
      openJob: openJob == null
          ? null
          : (ctx, id) {
              Navigator.of(ctx).popUntil((route) => route.isFirst);
              openJob(id);
            },
      openOrders: backTo(shell?.showOrders),
      openOrder: openOrder == null
          ? null
          : (ctx, id) {
              Navigator.of(ctx).popUntil((route) => route.isFirst);
              openOrder(id);
            },
      openTeam: backTo(shell?.showTeam),
      openPlan: backTo(shell?.openPlan),
      openVerification: VerificationPage.open,
      openTask: backTo(shell?.showTask),
      openJobs: backTo(shell?.showJobs),
      openTicket: (ctx, id, {required resolved}) => openTicketChat(
        ctx,
        SupportTicket(
          id: id,
          customerId: '',
          status: resolved ? 'resolved' : 'assigned',
          createdAt: DateTime.now(),
        ),
      ),
      openTickets: TicketsPage.open,
    );
  }

  final void Function(BuildContext context)? openOrders;
  final void Function(BuildContext context, String jobId)? openOrder;
  final void Function(BuildContext context)? openTeam;
  final void Function(BuildContext context)? openPlan;
  final void Function(BuildContext context)? openVerification;
  final void Function(BuildContext context)? openTask;
  final void Function(BuildContext context)? openJobs;

  /// [resolved]: the notification said the ticket was resolved (the chat
  /// opens read-only).
  final void Function(BuildContext context, String ticketId,
      {required bool resolved})? openTicket;
  final void Function(BuildContext context)? openTickets;

  /// The exact job (see [NotificationShellLinks.openJob]).
  final void Function(BuildContext context, String jobId)? openJob;

  /// Follows [target] from [context] (the notifications page).
  void follow(BuildContext context, NotificationTarget target,
      {bool resolved = false}) {
    switch (target.kind) {
      case NotificationTargetKind.orders:
        openOrders?.call(context);
      case NotificationTargetKind.order:
        openOrder?.call(context, target.id!);
      case NotificationTargetKind.team:
        openTeam?.call(context);
      case NotificationTargetKind.plan:
        openPlan?.call(context);
      case NotificationTargetKind.verification:
        openVerification?.call(context);
      case NotificationTargetKind.task:
        openTask?.call(context);
      case NotificationTargetKind.jobs:
        openJobs?.call(context);
      case NotificationTargetKind.ticket:
        openTicket?.call(context, target.id!, resolved: resolved);
      case NotificationTargetKind.tickets:
        openTickets?.call(context);
      case NotificationTargetKind.job:
        final open = openJob;
        if (open != null) {
          open(context, target.id!);
        } else if (target.fallback != null) {
          follow(context, target.fallback!, resolved: resolved);
        }
      case NotificationTargetKind.none:
        break;
    }
  }
}
