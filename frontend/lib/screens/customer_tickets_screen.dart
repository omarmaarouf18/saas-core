import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/support_ticket.dart';
import '../providers/chat_provider.dart';
import '../widgets/create_ticket_dialog.dart';
import '../widgets/list_screen_template.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_panel.dart';
import 'ticket_chat_screen.dart';

class CustomerTicketsScreen extends StatefulWidget {
  const CustomerTicketsScreen({super.key});

  @override
  State<CustomerTicketsScreen> createState() => _CustomerTicketsScreenState();
}

class _CustomerTicketsScreenState extends State<CustomerTicketsScreen> {
  String _selectedFilter = 'all'; // 'all', 'open', 'resolved'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadTickets();
      }
    });
  }

  Future<void> _loadTickets() async {
    final chat = Provider.of<ChatProvider>(context, listen: false);
    await chat.fetchCustomerTickets(refresh: true);
  }

  List<SupportTicket> _filterTickets(List<SupportTicket> tickets) {
    if (_selectedFilter == 'open') {
      return tickets.where((t) => !t.isResolved).toList();
    } else if (_selectedFilter == 'resolved') {
      return tickets.where((t) => t.isResolved).toList();
    }
    return tickets;
  }

  Future<void> _openCreateTicketDialog() async {
    final res = await showDialog(
      context: context,
      builder: (context) => const CreateTicketDialog(),
    );

    if (res != null && mounted) {
      final chat = Provider.of<ChatProvider>(context, listen: false);
      await chat.fetchCustomerTickets(refresh: true);

      final ticketId = res['ticket_id']?.toString() ?? res['id']?.toString();
      if (ticketId != null && mounted) {
        // Find created ticket or build placeholder
        final ticket = chat.customerTickets.firstWhere(
          (t) => t.id == ticketId,
          orElse: () => SupportTicket(
            id: ticketId,
            customerId: '',
            status: 'pending',
            createdAt: DateTime.now(),
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TicketChatScreen(ticket: ticket),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final chat = Provider.of<ChatProvider>(context);
    final allTickets = chat.customerTickets;
    final filteredTickets = _filterTickets(allTickets);

    return ListScreenTemplate<SupportTicket>(
      title: l10n.supportTicketsTitle,
      subtitle: l10n.supportTicketsSubtitle,
      showBackButton: true,
      isLoading: chat.isLoadingTickets && allTickets.isEmpty,
      errorMessage: chat.ticketsError,
      onRetry: _loadTickets,
      onRefresh: _loadTickets,
      items: filteredTickets,
      header: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.marginMobile,
          vertical: AppSpacing.xs,
        ),
        child: PillFilterBar<String>(
          items: [
            PillFilterItem<String>(value: 'all', label: l10n.ticketFilterAll),
            PillFilterItem<String>(value: 'open', label: l10n.ticketFilterOpen),
            PillFilterItem<String>(
                value: 'resolved', label: l10n.ticketFilterResolved),
          ],
          selectedValue: _selectedFilter,
          onSelected: (val) {
            setState(() {
              _selectedFilter = val;
            });
          },
        ),
      ),
      emptyWidget: ThemedEmptyState(
        icon: Icons.support_agent_outlined,
        title: l10n.emptyTicketsTitle,
        description: l10n.emptyTicketsDesc,
        actionText: l10n.openNewTicketBtn,
        onActionPressed: _openCreateTicketDialog,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_ticket_fab'),
        onPressed: _openCreateTicketDialog,
        icon: const Icon(Icons.add),
        label: Text(l10n.createTicketFab),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      itemBuilder: (context, ticket, index) {
        return _buildTicketCard(context, ticket);
      },
    );
  }

  Widget _buildTicketCard(BuildContext context, SupportTicket ticket) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final subject = ticket.subject != null && ticket.subject!.isNotEmpty
        ? ticket.subject!
        : (ticket.contextId != null && ticket.contextId!.isNotEmpty
            ? l10n.ticketContextJob(ticket.contextId!)
            : l10n.ticketChatTitle(ticket.id));

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.marginMobile,
        vertical: AppSpacing.xxs,
      ),
      child: ThemedCard(
        key: Key('ticket_card_${ticket.id}'),
        padding: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => TicketChatScreen(ticket: ticket),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Ticket ID + Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.ticketChatTitle(ticket.id),
                      style: AppTypography.labelMd.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    StatusBadge(
                      status: ticket.status,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                // Subject / Context
                Text(
                  subject,
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),

                // Resolution preview if resolved
                if (ticket.isResolved &&
                    ticket.resolutionNote != null &&
                    ticket.resolutionNote!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: ThemedPanel(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      color: context.semanticColors.success
                          .withValues(alpha: 0.08),
                      borderRadius: AppRadius.xsBorder,
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: AppIconSize.xs,
                            color: context.semanticColors.success,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              ticket.resolutionNote!,
                              style: AppTypography.caption.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Footer row: Assigned Agent / Pending status + Timestamp
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        ticket.assignedAgentId != null
                            ? l10n.ticketAssignedAgent(ticket.assignedAgentId!)
                            : l10n.ticketPendingAgent,
                        style: AppTypography.caption.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatDate(ticket.createdAt),
                      style: AppTypography.caption.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour:$min';
  }
}
