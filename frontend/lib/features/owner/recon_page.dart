import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/reconciliation_job.dart';
import '../../providers/reconciliation_provider.dart';
import '../../ui/qd_ui.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_nav.dart';
import 'owner_sheets.dart';
import 'owner_widgets.dart';

/// Payment review (O-Recon): orders whose held money waits for the owner's
/// decision. Release to the courier or refund the customer, after a
/// confirm sheet, one resolution at a time (the old screen's in-flight
/// guard, QA audit A4). Mostly empty while only cash on delivery runs.
class OwnerReconPage extends StatefulWidget {
  const OwnerReconPage({super.key});

  static Future<void> open(BuildContext context) => OwnerNavScope.of(context)
      .push<void>(context, (_) => const OwnerReconPage());

  @override
  State<OwnerReconPage> createState() => _OwnerReconPageState();
}

class _OwnerReconPageState extends State<OwnerReconPage> {
  bool _fetched = false;

  /// The job whose resolution is in flight; every action is disabled
  /// meanwhile so a second money-moving request can never start.
  String? _resolvingId;
  String? _resolvingDecision;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<ReconciliationProvider>().fetchQueue();
    if (mounted) setState(() => _fetched = true);
  }

  Future<void> _resolve(ReconciliationJob job, String decision) async {
    if (_resolvingId != null) return;
    final l10n = context.l10n;
    final provider = context.read<ReconciliationProvider>();
    final data = context.read<OwnerDataController>();
    final release = decision == 'release_to_employee';
    final amount = formatMoney(l10n, job.lockedEscrowAmount);
    final ref = _reconRef(job);
    final ok = await showOwnerConfirmSheet(
      context,
      key: Key('own_recon_confirm_$decision'),
      title: release ? l10n.ownReconPayTitle : l10n.ownReconRefundTitle,
      message: release
          ? l10n.ownReconPayBody(
              amount,
              ref,
              courierNameOf(l10n, data, job.employeeId) ??
                  l10n.ownReconTheCourier)
          : l10n.ownReconRefundBody(amount, ref),
      confirmLabel: release ? l10n.ownReconPay : l10n.ownReconRefund,
      destructive: !release,
    );
    if (!ok || !mounted || _resolvingId != null) return;
    setState(() {
      _resolvingId = job.id;
      _resolvingDecision = decision;
    });
    final success =
        await provider.resolveJob(jobId: job.id, decision: decision);
    if (!mounted) return;
    setState(() => _resolvingId = _resolvingDecision = null);
    if (success) {
      showOwnerNotice(
          context, release ? l10n.ownReconPaid : l10n.ownReconRefunded);
      // Today's "needs you" count reads the owner jobs list.
      await data.refreshJobs();
    } else {
      showOwnerNotice(context, provider.error ?? l10n.ownReconFailed,
          onRetry: () => _resolve(job, decision));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final recon = context.watch<ReconciliationProvider>();
    final queue = recon.queue;

    Widget body;
    if (queue.isEmpty && (!_fetched || recon.isLoading)) {
      body = const OwnerScrollableCenter(
        key: Key('own_recon_loading'),
        child: CircularProgressIndicator(),
      );
    } else if (queue.isEmpty && recon.error != null) {
      body = OwnerScrollableCenter(
        key: const Key('own_recon_error'),
        child: QdErrorState(title: l10n.ownReconLoadError, onRetry: _load),
      );
    } else {
      body = ListView(
        key: const Key('own_recon_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
        children: [
          Text(l10n.ownReconIntro,
              style: QdText.body.copyWith(color: c.textSecondary)),
          const SizedBox(height: QdSpace.x4),
          if (queue.isEmpty)
            QdEmptyState(
              key: const Key('own_recon_empty'),
              icon: Icons.check_circle_outline,
              title: l10n.ownReconEmpty,
            ),
          for (final job in queue) ...[
            _ReconCard(
              job: job,
              resolvingDecision:
                  _resolvingId == job.id ? _resolvingDecision : null,
              locked: _resolvingId != null,
              onRelease: () => _resolve(job, 'release_to_employee'),
              onRefund: () => _resolve(job, 'refund_to_customer'),
            ),
            const SizedBox(height: QdSpace.x3),
          ],
          const SizedBox(height: QdSpace.x2),
          Container(
            key: const Key('own_recon_cod_note'),
            padding: const EdgeInsetsDirectional.all(14),
            decoration: BoxDecoration(
              color: c.fillMuted,
              borderRadius: BorderRadius.circular(QdRadius.button),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.ownReconCodTitle,
                    style: QdText.bodyStrong.copyWith(color: c.textPrimary)),
                const SizedBox(height: 2),
                Text(l10n.ownReconCodBody,
                    style: QdText.secondary.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      key: const Key('own_recon_page'),
      backgroundColor: c.surface,
      appBar: ownerAppBar(context, title: l10n.ownReconTitle),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

/// `#QD-` reference of a queue entry, LTR-isolated (same format as
/// [jobRefIsolated], which takes a Job).
String _reconRef(ReconciliationJob job) {
  final s = job.id.length > 8 ? job.id.substring(0, 8) : job.id;
  return '\u2066#QD-${s.toUpperCase()}\u2069';
}

class _ReconCard extends StatelessWidget {
  const _ReconCard({
    required this.job,
    required this.resolvingDecision,
    required this.locked,
    required this.onRelease,
    required this.onRefund,
  });

  final ReconciliationJob job;
  final String? resolvingDecision;
  final bool locked;
  final VoidCallback onRelease;
  final VoidCallback onRefund;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final note = job.reconciliationNote.trim();
    return Container(
      key: Key('own_recon_${job.id}'),
      padding: const EdgeInsetsDirectional.all(QdSpace.x4),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(QdRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.ownOrderTitle(_reconRef(job)),
              style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: QdStatusChip(
                label: reconReasonLabel(l10n, job.escrowFailureReason),
                tone: QdTone.warning),
          ),
          const SizedBox(height: QdSpace.x3),
          OwnerInfoGroup(rows: [
            OwnerInfoRow(
              label: l10n.ownReconHeld,
              value: formatMoney(l10n, job.lockedEscrowAmount),
            ),
            OwnerInfoRow(
              label: l10n.ownRowCourier,
              value: courierNameOf(l10n, data, job.employeeId) ??
                  l10n.ownCourierNone,
            ),
            OwnerInfoRow(
              label: l10n.ownRowCustomer,
              value: l10n.ownCustomerRef(shortRefIsolated(job.userId)),
            ),
          ]),
          if (note.isNotEmpty) ...[
            const SizedBox(height: QdSpace.x3),
            Text(note,
                key: const Key('own_recon_note'),
                style: QdText.secondary.copyWith(color: c.textSecondary)),
          ],
          const SizedBox(height: QdSpace.x3),
          // Stacked: both labels fit at 360 dp in either language.
          QdButton.secondary(
            key: Key('own_recon_pay_${job.id}'),
            label: l10n.ownReconPay,
            small: true,
            fullWidth: true,
            loading: resolvingDecision == 'release_to_employee',
            onPressed: locked ? null : onRelease,
          ),
          const SizedBox(height: QdSpace.x2),
          QdButton.secondary(
            key: Key('own_recon_refund_${job.id}'),
            label: l10n.ownReconRefund,
            small: true,
            fullWidth: true,
            loading: resolvingDecision == 'refund_to_customer',
            onPressed: locked ? null : onRefund,
          ),
        ],
      ),
    );
  }
}

/// Short chip label for a backend escrow failure reason.
String reconReasonLabel(AppLocalizations l10n, String code) =>
    switch (code.trim()) {
      'under_distance_mismatch' => l10n.ownReasonShortDistance,
      'implausible_speed' => l10n.ownReasonSpeed,
      'escrow_amount_unrecorded' => l10n.ownReasonUnrecorded,
      _ => l10n.ownReasonOther,
    };
