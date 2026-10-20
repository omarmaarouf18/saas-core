import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../models/support_ticket.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/marketplace_provider.dart';
import '../../../ui/qd_ui.dart';
import '../../customer/customer_format.dart';
import 'ticket_rules.dart';

/// Most recent orders offered in the picker.
const int kComplaintOrderChoices = 6;

/// "New complaint" sheet: which order (from the customer's orders, or
/// none), a subject and what happened.
///
/// Behaviour kept from CreateTicketDialog: both fields required (trimmed),
/// the ticket created through ChatProvider.createTicket with the same
/// context format, its error shown in the sheet, the typed text never lost
/// to an outside tap or drag. Fixed: the description had the
/// customer-service subtitle as its label and hint; it now has its own.
/// New: the order picker (the dialog only knew the order it was opened
/// from).
class NewComplaintSheet extends StatefulWidget {
  const NewComplaintSheet({super.key, this.preselectedJobId});

  final String? preselectedJobId;

  /// Opens the sheet; completes with the created ticket, or null.
  static Future<SupportTicket?> show(BuildContext context,
      {String? preselectedJobId}) {
    final c = QdColors.of(context);
    return showModalBottomSheet<SupportTicket>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: c.surface,
      barrierColor: c.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: QdThemeScope(
            child: NewComplaintSheet(preselectedJobId: preselectedJobId)),
      ),
    );
  }

  @override
  State<NewComplaintSheet> createState() => _NewComplaintSheetState();
}

class _NewComplaintSheetState extends State<NewComplaintSheet> {
  final _subject = TextEditingController();
  final _description = TextEditingController();
  late String? _jobId = widget.preselectedJobId;
  String? _subjectError;
  String? _descriptionError;
  String? _error;
  bool _sending = false;
  bool _loadingOrders = false;
  bool _ordersFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrders());
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final market = context.read<MarketplaceProvider>();
    if (market.customerJobs.isNotEmpty) return;
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    setState(() => _loadingOrders = true);
    await market.fetchCustomerJobs(token);
    if (!mounted) return;
    setState(() {
      _loadingOrders = false;
      _ordersFailed = market.error != null;
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final l10n = context.l10n;
    final subject = _subject.text.trim();
    final description = _description.text.trim();
    setState(() {
      _subjectError = subject.isEmpty ? l10n.supSubjectRequired : null;
      _descriptionError =
          description.isEmpty ? l10n.supDescriptionRequired : null;
      _error = null;
    });
    if (_subjectError != null || _descriptionError != null) return;
    final chat = context.read<ChatProvider>();
    final token = context.read<AuthProvider>().token ?? '';
    setState(() => _sending = true);
    try {
      final res = await chat.createTicket(
        contextId: buildTicketContext(
            jobId: _jobId, subject: subject, description: description),
        userToken: token,
      );
      if (!mounted) return;
      final ticket = SupportTicket.fromJson(res);
      Navigator.of(context).pop(ticket);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final jobs = [...context.watch<MarketplaceProvider>().customerJobs]..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    final choices = jobs.take(kComplaintOrderChoices).toList();
    // The order it was opened from stays offered even when older.
    final pre = widget.preselectedJobId;
    if (pre != null && !choices.any((j) => j.id == pre)) {
      final job = jobs.where((j) => j.id == pre).firstOrNull;
      if (job != null) choices.insert(0, job);
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: QdSpace.x5),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.gutter, QdSpace.x3, QdSpace.x2, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(l10n.supNewComplaint,
                        style:
                            QdText.sheetTitle.copyWith(color: c.textPrimary)),
                  ),
                ),
                IconButton(
                  key: const Key('complaint_close'),
                  tooltip: l10n.acctClose,
                  onPressed:
                      _sending ? null : () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: c.textPrimary),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: QdSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    QdBanner(
                      key: const Key('complaint_error'),
                      tone: QdBannerTone.danger,
                      icon: Icons.error_outline,
                      message: _error!,
                      actionLabel: l10n.retry,
                      onAction: _send,
                    ),
                    const SizedBox(height: QdSpace.x4),
                  ],
                  Text(l10n.supOrderLabel,
                      style: QdText.body.copyWith(
                          color: c.textPrimary, fontWeight: FontWeight.w500)),
                  const SizedBox(height: QdSpace.x2),
                  if (_loadingOrders)
                    Text(l10n.supOrdersLoading,
                        key: const Key('complaint_orders_loading'),
                        style:
                            QdText.secondary.copyWith(color: c.textSecondary))
                  else if (_ordersFailed)
                    Text(l10n.supOrdersError,
                        key: const Key('complaint_orders_error'),
                        style:
                            QdText.secondary.copyWith(color: c.textSecondary)),
                  const SizedBox(height: QdSpace.x2),
                  for (final job in choices) ...[
                    _orderOption(context, job),
                    const SizedBox(height: QdSpace.x2),
                  ],
                  QdOptionCard(
                    key: const Key('complaint_no_order'),
                    title: l10n.supNoOrderOption,
                    selected: _jobId == null,
                    onTap: () => setState(() => _jobId = null),
                  ),
                  const SizedBox(height: QdSpace.x4),
                  QdTextField(
                    key: const Key('complaint_subject'),
                    label: l10n.supSubjectLabel,
                    hint: l10n.supSubjectHint,
                    controller: _subject,
                    errorText: _subjectError,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_subjectError != null) {
                        setState(() => _subjectError = null);
                      }
                    },
                  ),
                  const SizedBox(height: QdSpace.x4),
                  QdTextField(
                    key: const Key('complaint_description'),
                    label: l10n.supDescriptionLabel,
                    hint: l10n.supDescriptionHint,
                    controller: _description,
                    errorText: _descriptionError,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    onChanged: (_) {
                      if (_descriptionError != null) {
                        setState(() => _descriptionError = null);
                      }
                    },
                  ),
                  const SizedBox(height: QdSpace.x5),
                  QdButton(
                    key: const Key('complaint_send'),
                    label: l10n.supSend,
                    loading: _sending,
                    fullWidth: true,
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderOption(BuildContext context, Job job) {
    final l10n = context.l10n;
    final status = QdJobStatus.fromBackend(job.status);
    final when =
        job.createdAt == null ? null : formatWhen(context, job.createdAt!);
    return QdOptionCard(
      key: Key('complaint_order_${job.id}'),
      title: jobRefIsolated(job),
      subtitle: [if (when != null) when, status.label(l10n)].join(' · '),
      selected: _jobId == job.id,
      onTap: () => setState(() => _jobId = job.id),
    );
  }
}
