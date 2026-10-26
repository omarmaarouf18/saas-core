import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/marketplace_provider.dart';
import '../../../ui/qd_ui.dart';
import '../customer_format.dart';
import 'order_sections.dart';

/// Who the customer rates for [job]: the courier when one was assigned,
/// otherwise the company owner (the old RatingScreen rule for customers).
String? ratedPartyOf(Job job) {
  final employee = job.employeeId?.trim() ?? '';
  if (employee.isNotEmpty) return employee;
  final owner = job.ownerId.trim();
  return owner.isEmpty ? null : owner;
}

/// Rating (A-Rate): stars, a private comment, the blind-rating note, and
/// "not now". Behaviour of the old RatingScreen for a customer: five stars
/// preselected, comment trimmed, the server's "already rated" / conflict
/// answer counts as success, any other failure offers a retry, and the
/// page checks whether the other side already rated (with its own retry).
/// Pops true once the rating is in.
class CustomerRatingPage extends StatefulWidget {
  const CustomerRatingPage({super.key, required this.job, this.courierName});

  final Job job;

  /// Resolved courier name, when known.
  final String? courierName;

  static Future<bool?> open(BuildContext context,
          {required Job job, String? courierName}) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => CustomerRatingPage(job: job, courierName: courierName),
      ));

  @override
  State<CustomerRatingPage> createState() => _CustomerRatingPageState();
}

enum _OtherSide { checking, rated, notYet, failed }

class _CustomerRatingPageState extends State<CustomerRatingPage> {
  int _stars = 5;
  final _comment = TextEditingController();
  bool _sending = false;
  _OtherSide _other = _OtherSide.checking;

  bool get _ratesCourier => (widget.job.employeeId?.trim() ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkOtherSide();
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Whether the rated party already rated this customer for this job
  /// (ratings received by the current user, as before).
  Future<void> _checkOtherSide() async {
    final token = context.read<AuthProvider>().token;
    final marketplace = context.read<MarketplaceProvider>();
    final other = ratedPartyOf(widget.job);
    setState(() => _other = _OtherSide.checking);
    try {
      final res = await marketplace.fetchRatings(token ?? '');
      final list = res['ratings'] as List<dynamic>? ?? const [];
      final found = list.any((r) =>
          r is Map && r['job_id'] == widget.job.id && r['rated_by'] == other);
      if (mounted) {
        setState(() => _other = found ? _OtherSide.rated : _OtherSide.notYet);
      }
    } catch (_) {
      if (mounted) setState(() => _other = _OtherSide.failed);
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final l10n = context.l10n;
    final other = ratedPartyOf(widget.job);
    if (other == null) {
      showOrderNotice(context, l10n.rateIdentityError);
      return;
    }
    final token = context.read<AuthProvider>().token;
    final marketplace = context.read<MarketplaceProvider>();
    setState(() => _sending = true);
    try {
      await marketplace.rateJob(
        jobId: widget.job.id,
        ratedByToken: token ?? '',
        ratedUserId: other,
        stars: _stars,
        comment: _comment.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      if (text.contains('already rated') || text.contains('conflict')) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _sending = false);
      showOrderNotice(context, l10n.rateFailed(friendlyErrorMessage(e)),
          onRetry: _send);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final name = widget.courierName;
    final question = !_ratesCourier
        ? l10n.rateQuestionCompany
        : name == null
            ? l10n.rateQuestionCourier
            : l10n.rateQuestion(name);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('rate_close'),
          tooltip: l10n.rateClose,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.x6, 0, QdSpace.x6, QdSpace.x4),
        children: [
          OrderDeliveredHeader(job: widget.job),
          const SizedBox(height: QdSpace.x5),
          Container(
            padding: const EdgeInsets.all(QdSpace.x5),
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                if (_ratesCourier && name != null)
                  QdAvatarInitial(name: name, size: 56)
                else
                  QdIconTile(
                      icon: _ratesCourier
                          ? Icons.person_outline
                          : Icons.storefront_outlined,
                      size: 56),
                const SizedBox(height: 14),
                Text(question,
                    textAlign: TextAlign.center,
                    style: QdText.rowTitle.copyWith(color: c.textPrimary)),
                const SizedBox(height: QdSpace.x3),
                _Stars(
                  value: _stars,
                  enabled: !_sending,
                  onChanged: (v) => setState(() => _stars = v),
                ),
                const SizedBox(height: QdSpace.x3),
                _OtherSideNote(state: _other, onRetry: _checkOtherSide),
                const SizedBox(height: 14),
                QdTextField(
                  key: const Key('rate_comment'),
                  label: l10n.rateComment,
                  controller: _comment,
                  maxLines: 3,
                  enabled: !_sending,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: QdFooterBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QdButton(
              key: const Key('rate_send'),
              label: l10n.rateSend,
              fullWidth: true,
              loading: _sending,
              onPressed: _send,
            ),
            const SizedBox(height: QdSpace.x1),
            QdButton.text(
              key: const Key('rate_not_now'),
              label: l10n.rateNotNow,
              fullWidth: true,
              onPressed:
                  _sending ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Success disc, "Your order was delivered" and what was paid. Shared by
/// the completed view and the rating page. The API has no delivery time,
/// so no date is shown.
class OrderDeliveredHeader extends StatelessWidget {
  const OrderDeliveredHeader({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final price = jobPrice(job);
    final cod = job.paymentMethod.trim().toLowerCase() == 'cod';
    return OrderStateHeader(
      icon: Icons.check,
      tone: QdTone.success,
      title: l10n.ordDeliveredTitle,
      body: price == null
          ? null
          : cod
              ? l10n.ordDeliveredPaidCash(formatMoney(l10n, price))
              : l10n.ordDeliveredPaid(formatMoney(l10n, price)),
    );
  }
}

/// Five stars as a radio group, always left to right (1 → 5).
class _Stars extends StatelessWidget {
  const _Stars(
      {required this.value, required this.enabled, required this.onChanged});

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Semantics(
      label: l10n.rateStars,
      container: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              Semantics(
                key: Key('rate_star_$i'),
                inMutuallyExclusiveGroup: true,
                checked: i == value,
                button: true,
                label: l10n.rateStar(i),
                excludeSemantics: true,
                child: InkResponse(
                  onTap: enabled ? () => onChanged(i) : null,
                  radius: 24,
                  child: SizedBox.square(
                    dimension: QdSize.minTouch,
                    child: Icon(
                      i <= value ? Icons.star : Icons.star_border,
                      size: 34,
                      color: i <= value ? c.gold : c.decorative,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The blind-rating note, or that the other side already rated, or that
/// the check failed (with retry).
class _OtherSideNote extends StatelessWidget {
  const _OtherSideNote({required this.state, required this.onRetry});

  final _OtherSide state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    if (state == _OtherSide.failed) {
      return QdBanner(
        key: const Key('rate_other_failed'),
        tone: QdBannerTone.warning,
        icon: Icons.error_outline,
        message: l10n.rateOtherCheckFailed,
        actionLabel: l10n.retry,
        onAction: onRetry,
      );
    }
    final rated = state == _OtherSide.rated;
    return Row(
      key: Key(rated ? 'rate_other_rated' : 'rate_blind_note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(rated ? Icons.visibility_outlined : Icons.lock_outline,
            size: 18, color: rated ? c.success : c.textSecondary),
        const SizedBox(width: QdSpace.x2),
        Expanded(
          child: Text(
            rated ? l10n.rateOtherRated : l10n.rateBlindNote,
            style: QdText.secondary.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}
