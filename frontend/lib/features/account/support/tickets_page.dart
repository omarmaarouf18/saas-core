import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/support_ticket.dart';
import '../../../providers/chat_provider.dart';
import '../../../ui/qd_ui.dart';
import '../../customer/chat/chat_page.dart';
import '../../customer/customer_format.dart';
import '../account_nav.dart';
import 'new_complaint_sheet.dart';
import 'ticket_rules.dart';

/// Support (A-Tickets): the customer's complaints, open / resolved, and
/// "new complaint".
///
/// Behaviour kept from CustomerTicketsScreen: a full reload on open, after
/// returning from a ticket and on pull to refresh; a loader only while the
/// list is empty; the load error with retry; the resolution note on
/// resolved tickets; after creating a complaint the list reloads and its
/// chat opens. Changed: two tabs instead of all / open / resolved; the
/// card shows the subject and order from the ticket's context instead of
/// the raw context string and agent id.
class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key, this.now, this.pickAttachment});

  /// Clock for dates (tests).
  final DateTime Function()? now;

  /// Passed to the ticket chat (tests).
  final ChatAttachmentPicker? pickAttachment;

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push<void>(qdPageRoute((_) => const TicketsPage()));

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  bool _resolvedTab = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() =>
      context.read<ChatProvider>().fetchCustomerTickets(refresh: true);

  Future<void> _openTicket(SupportTicket ticket) async {
    await openTicketChat(context, ticket,
        pickAttachment: widget.pickAttachment);
    if (mounted) await _load();
  }

  Future<void> _newComplaint() async {
    final ticket = await NewComplaintSheet.show(context);
    if (ticket == null || !mounted) return;
    showAccountNotice(context, context.l10n.supSent);
    await _load();
    if (!mounted) return;
    final chat = context.read<ChatProvider>();
    final created =
        chat.customerTickets.where((t) => t.id == ticket.id).firstOrNull ??
            ticket;
    await _openTicket(created);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final chat = context.watch<ChatProvider>();
    final all = chat.customerTickets;
    final open = all.where((t) => !t.isResolved).toList();
    final resolved = all.where((t) => t.isResolved).toList();
    final shown = _resolvedTab ? resolved : open;

    final Widget body;
    if (all.isEmpty && chat.isLoadingTickets) {
      body = const Center(
          key: Key('tickets_loading'), child: CircularProgressIndicator());
    } else if (all.isEmpty && chat.ticketsError != null) {
      body = Center(
        child: SingleChildScrollView(
          child: QdErrorState(
            key: const Key('tickets_error'),
            body: l10n.supLoadError,
            onRetry: _load,
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('tickets_list'),
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x4),
          children: [
            if (chat.ticketsError != null) ...[
              QdBanner(
                key: const Key('tickets_refresh_error'),
                tone: QdBannerTone.warning,
                message: l10n.supLoadError,
                actionLabel: l10n.retry,
                onAction: _load,
              ),
              const SizedBox(height: QdSpace.x3),
            ],
            for (final t in shown) ...[
              _TicketCard(
                key: Key('ticket_${t.id}'),
                ticket: t,
                now: widget.now,
                onTap: () => _openTicket(t),
              ),
              const SizedBox(height: QdSpace.x3),
            ],
            if (_resolvedTab && shown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: QdSpace.x6),
                child: QdEmptyState(
                  key: const Key('tickets_resolved_empty'),
                  icon: Icons.check_circle_outline,
                  title: l10n.supResolvedEmpty,
                ),
              ),
            if (!_resolvedTab) ...[
              SizedBox(height: shown.isEmpty ? QdSpace.x2 : QdSpace.x3),
              QdCard(
                key: const Key('tickets_hint'),
                subtle: true,
                padding: const EdgeInsets.all(QdSpace.x5),
                child: Column(
                  children: [
                    Text(l10n.supHintTitle,
                        textAlign: TextAlign.center,
                        style:
                            QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                    const SizedBox(height: 6),
                    Text(l10n.supHintBody,
                        textAlign: TextAlign.center,
                        style: QdText.secondary
                            .copyWith(color: c.textSecondary, height: 1.6)),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.surface,
      appBar: accountAppBar(context, l10n.supTitle),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                QdSpace.gutter, 0, QdSpace.gutter, QdSpace.x3),
            child: QdSegmented<bool>(
              key: const Key('tickets_tabs'),
              selected: _resolvedTab,
              onChanged: (v) => setState(() => _resolvedTab = v),
              segments: [
                QdSegment(value: false, label: l10n.supOpenTab(open.length)),
                QdSegment(value: true, label: l10n.supResolvedTab),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: QdFooterBar(
        child: QdButton(
          key: const Key('tickets_new'),
          label: l10n.supNewComplaint,
          fullWidth: true,
          onPressed: _newComplaint,
        ),
      ),
    );
  }
}

/// Opens the chat of [ticket] (title: its subject, subtitle: its order).
Future<void> openTicketChat(BuildContext context, SupportTicket ticket,
    {ChatAttachmentPicker? pickAttachment}) {
  final l10n = context.l10n;
  final job = parseTicketContext(ticket.contextId).jobId;
  return CustomerChatPage.openTicket(
    context,
    ticket: ticket,
    title: ticketSubject(l10n, ticket),
    subtitle: job == null ? ticketRef(ticket.id) : orderRefOf(job),
    emptyBody: l10n.supChatEmpty,
    pickAttachment: pickAttachment,
  );
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    super.key,
    required this.ticket,
    required this.onTap,
    this.now,
  });

  final SupportTicket ticket;
  final VoidCallback onTap;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctx = parseTicketContext(ticket.contextId);
    final (label, tone) = ticketStatusChip(l10n, ticket.status);
    final when = formatWhen(context, ticket.updatedAt ?? ticket.createdAt,
        now: now?.call());
    final about = ctx.jobId == null
        ? l10n.supGeneral(when)
        : l10n.supAboutOrder(orderRefOf(ctx.jobId!), when);
    final note = ticket.resolutionNote?.trim() ?? '';
    final detail = ticket.isResolved && note.isNotEmpty
        ? l10n.supResolution(note)
        : ctx.description;

    return QdCard(
      onTap: onTap,
      semanticLabel: '${ticketSubject(l10n, ticket)}, $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(ticketSubject(l10n, ticket),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
              ),
              const SizedBox(width: QdSpace.x2),
              QdStatusChip(label: label, tone: tone),
            ],
          ),
          const SizedBox(height: QdSpace.x2),
          Text(about, style: QdText.secondary.copyWith(color: c.textSecondary)),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: QdSpace.x2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.chat_bubble_outline,
                      size: 16, color: c.neutral),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: QdText.secondary.copyWith(color: c.neutral)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
