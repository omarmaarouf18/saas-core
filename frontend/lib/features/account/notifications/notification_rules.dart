import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/notification_model.dart';
import '../../../models/support_ticket.dart';
import '../../../screens/customer_tickets_screen.dart';
import '../../../screens/ticket_chat_screen.dart';

/// Where tapping a notification leads.
enum NotificationTargetKind { none, orders, ticket, tickets }

class NotificationTarget {
  const NotificationTarget(this.kind, [this.ticketId]);

  static const none = NotificationTarget(NotificationTargetKind.none);

  final NotificationTargetKind kind;
  final String? ticketId;

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      other.kind == kind &&
      other.ticketId == ticketId;

  @override
  int get hashCode => Object.hash(kind, ticketId);

  @override
  String toString() => 'NotificationTarget($kind, $ticketId)';
}

/// Customer notification types that are about an order. The payload has no
/// job id (notification-service does not store one), so they open My
/// orders.
const Set<String> kOrderNotificationTypes = {
  'job_accepted',
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

/// The deep link for [n] when the signed-in user has [role].
///
/// Only customers (role `user`) get links, and only to customer screens:
/// a courier's job offer, KYC or payout notification never opens the
/// courier or owner screens from here (the old screen did, whatever the
/// role).
NotificationTarget notificationTarget(NotificationModel n, String? role) {
  if (role != 'user') return NotificationTarget.none;
  if (kOrderNotificationTypes.contains(n.type)) {
    return const NotificationTarget(NotificationTargetKind.orders);
  }
  if (kTicketNotificationTypes.contains(n.type)) {
    final id = ticketIdFromBody(n.body);
    return id == null
        ? const NotificationTarget(NotificationTargetKind.tickets)
        : NotificationTarget(NotificationTargetKind.ticket, id);
  }
  return NotificationTarget.none;
}

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

/// Title and body shown for [n]: localized copy for the customer types the
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
    case 'ticket_resolved':
      // The resolution note follows "has been resolved: ".
      final i = n.body.indexOf('resolved: ');
      final note = i == -1 ? '' : n.body.substring(i + 'resolved: '.length);
      return (l10n.ntfTicketResolvedTitle, note.trim().isEmpty ? n.body : note);
    case 'ticket_assigned':
      return (l10n.ntfTicketAssignedTitle, l10n.ntfTicketAssignedBody);
    case 'dispute_resolved':
      return (l10n.ntfDisputeTitle, n.body);
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

/// Where the notification links go. Swappable for tests; the default opens
/// the support screens and, for orders, closes the notifications page and
/// shows the customer shell's My orders tab ([OrdersTabScope]).
class NotificationLinks {
  const NotificationLinks({
    required this.openOrders,
    required this.openTicket,
    required this.openTickets,
  });

  /// Links for a notifications page opened from [context] (inside the
  /// customer shell).
  factory NotificationLinks.of(BuildContext context) {
    final showOrders = OrdersTabScope.maybeOf(context);
    return NotificationLinks(
      openOrders: (ctx) {
        Navigator.of(ctx).popUntil((route) => route.isFirst);
        showOrders?.call();
      },
      openTicket: (ctx, id, {required resolved}) =>
          Navigator.of(ctx).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TicketChatScreen(
            ticket: SupportTicket(
              id: id,
              customerId: '',
              status: resolved ? 'resolved' : 'assigned',
              createdAt: DateTime.now(),
            ),
          ),
        ),
      ),
      openTickets: (ctx) => Navigator.of(ctx).push<void>(
        MaterialPageRoute<void>(builder: (_) => const CustomerTicketsScreen()),
      ),
    );
  }

  final void Function(BuildContext context) openOrders;

  /// [resolved]: the notification said the ticket was resolved (the chat
  /// opens read-only).
  final void Function(BuildContext context, String ticketId,
      {required bool resolved}) openTicket;
  final void Function(BuildContext context) openTickets;
}

/// Provided by the customer shell: shows its My orders tab.
class OrdersTabScope extends InheritedWidget {
  const OrdersTabScope(
      {super.key, required this.showOrders, required super.child});

  final VoidCallback showOrders;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrdersTabScope>()?.showOrders;

  @override
  bool updateShouldNotify(OrdersTabScope oldWidget) =>
      showOrders != oldWidget.showOrders;
}
