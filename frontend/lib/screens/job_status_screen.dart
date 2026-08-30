import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/cancel_job_dialog.dart';
import '../widgets/create_ticket_dialog.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/app_shell.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_success_banner.dart';
import '../widgets/themed_text_field.dart';
import 'chat_screen.dart';
import 'customer_job_map_screen.dart';
import 'rating_screen.dart';

class JobStatusScreen extends StatefulWidget {
  final Job job;
  final bool enablePolling;

  const JobStatusScreen({
    super.key,
    required this.job,
    this.enablePolling = true,
  });

  @override
  State<JobStatusScreen> createState() => _JobStatusScreenState();
}

class _JobStatusScreenState extends State<JobStatusScreen> {
  late Job _currentJob;
  Timer? _pollingTimer;
  Timer? _countdownTimer;
  bool _isRefreshing = false;
  // Declutter V2: collapsed-by-default fare details and negotiation panel.
  bool _fareDetailsExpanded = false;
  bool _negotiationExpanded = false;
  String? _resolvedUsername;
  String? _lastResolvedEmployeeId;

  final _counterOfferController = TextEditingController();
  bool _isSubmittingProposal = false;
  bool _isRespondingProposal = false;
  String? _proposalError;

  @override
  void initState() {
    super.initState();
    _currentJob = widget.job;
    if (widget.enablePolling) {
      _startPolling();
      _startCountdownTimer();
    }
    _resolveEmployeeUsername();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    _counterOfferController.dispose();
    super.dispose();
  }

  static const Duration _jobStatusPollingInterval = Duration(seconds: 5);
  static const Duration _countdownTimerInterval = Duration(seconds: 1);

  void _startPolling() {
    _pollingTimer = Timer.periodic(_jobStatusPollingInterval, (timer) {
      _refreshJobStatus(silent: true);
    });
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(_countdownTimerInterval, (_) {
      if (mounted && _currentJob.status == 'awaiting_price_response') {
        setState(() {});
      }
    });
  }

  bool get _isNegotiableTransportJob =>
      (_currentJob.suggestedPrice != null && _currentJob.suggestedPrice! > 0) ||
      _currentJob.status == 'awaiting_price_response' ||
      _currentJob.proposedPrice != null;

  bool get _isNegotiationExpired {
    if (_currentJob.status == 'cancelled' &&
        _currentJob.cancellationReason == 'price_proposal_expired') {
      return true;
    }
    if (_currentJob.priceProposalExpiresAt != null) {
      return _currentJob.priceProposalExpiresAt!
          .difference(DateTime.now())
          .isNegative;
    }
    return false;
  }

  String get _remainingTimeString {
    if (_currentJob.priceProposalExpiresAt == null) return '';
    final diff = _currentJob.priceProposalExpiresAt!.difference(DateTime.now());
    if (diff.isNegative) return '00:00';
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _submitCounterOffer(double suggestedPrice) async {
    final l10n = context.l10n;
    final input = _counterOfferController.text.trim();
    final proposed = double.tryParse(input);

    final minPrice = 0.5 * suggestedPrice;
    final maxPrice = 1.5 * suggestedPrice;

    if (proposed == null) {
      setState(() => _proposalError = l10n.enterValidNumberError);
      return;
    }
    const eps = 1e-9;
    if (proposed < (minPrice - eps) || proposed > (maxPrice + eps)) {
      setState(() => _proposalError = l10n.priceRangeError(
          minPrice.toStringAsFixed(2), maxPrice.toStringAsFixed(2)));
      return;
    }

    setState(() {
      _proposalError = null;
      _isSubmittingProposal = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<MarketplaceProvider>(context, listen: false);
    if (auth.token == null) return;

    try {
      final updated = await provider.proposePrice(
        jobId: _currentJob.id,
        proposedPrice: proposed,
        userToken: auth.token!,
      );
      if (mounted) {
        _counterOfferController.clear();
        if (updated != null) {
          setState(() => _currentJob = updated);
        }
        final l10n = AppLocalizations.of(context)!;
        ThemedSnackBar.showSuccess(context, l10n.counterOfferSuccessMsg);
        _refreshJobStatus();
      }
    } catch (e) {
      if (mounted) {
        String msg;
        if (e is ApiClientException && e.statusCode == 409) {
          msg = l10n.jobStateChangedError;
        } else {
          msg = friendlyErrorMessage(e);
        }
        ThemedSnackBar.showError(
          context,
          msg,
          onRetry: () => _submitCounterOffer(proposed),
        );
        _refreshJobStatus();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingProposal = false);
      }
    }
  }

  Future<void> _respondToProposal(String decision) async {
    setState(() => _isRespondingProposal = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<MarketplaceProvider>(context, listen: false);
    if (auth.token == null) return;

    final l10n = context.l10n;
    try {
      final updated = await provider.respondPrice(
        jobId: _currentJob.id,
        decision: decision,
        userToken: auth.token!,
      );
      if (mounted) {
        if (updated != null) {
          setState(() => _currentJob = updated);
        }
        if (decision == 'accept') {
          ThemedSnackBar.showSuccess(
            context,
            l10n.priceProposalAcceptedMsg,
          );
        } else {
          ThemedSnackBar.showError(
            context,
            l10n.priceProposalDeclinedMsg,
          );
        }
        _refreshJobStatus();
      }
    } catch (e) {
      if (mounted) {
        String msg;
        if (e is ApiClientException && e.statusCode == 409) {
          msg = l10n.jobStateChangedError;
        } else {
          msg = friendlyErrorMessage(e);
        }
        ThemedSnackBar.showError(
          context,
          msg,
          onRetry: () => _respondToProposal(decision),
        );
        _refreshJobStatus();
      }
    } finally {
      if (mounted) {
        setState(() => _isRespondingProposal = false);
      }
    }
  }

  Future<void> _resolveEmployeeUsername() async {
    final employeeId = _currentJob.employeeId;
    if (employeeId == null || employeeId.isEmpty) {
      if (mounted) {
        setState(() {
          _resolvedUsername = null;
          _lastResolvedEmployeeId = null;
        });
      }
      return;
    }

    if (employeeId == _lastResolvedEmployeeId) {
      return; // Already resolved for this ID!
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    if (token == null) return;

    try {
      final res = await authProvider.apiClient.get(
        '/auth/user/public-profile',
        queryParams: {
          'id': employeeId,
          'requester_id': token,
        },
      );
      if (res is Map && res.containsKey('username')) {
        if (mounted) {
          setState(() {
            _resolvedUsername = res['username'];
            _lastResolvedEmployeeId = employeeId;
          });
        }
      }
    } catch (_) {
      // Graceful fallback to raw ID on failure or if auth-service is unreachable
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _resolvedUsername = null;
              _lastResolvedEmployeeId = employeeId;
            });
          }
        });
      }
    }
  }

  Future<void> _refreshJobStatus({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isRefreshing = true;
      });
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<MarketplaceProvider>(context, listen: false);

    if (auth.token == null) return;

    final updated = await provider.fetchJobStatus(_currentJob.id, auth.token!);
    if (updated != null && mounted) {
      setState(() {
        _currentJob = updated;
        _isRefreshing = false;
      });
      _resolveEmployeeUsername();

      // Stop polling if the job is completed or cancelled
      if (_currentJob.status == 'completed' ||
          _currentJob.status == 'cancelled') {
        _pollingTimer?.cancel();
      }
    } else if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  int _getStatusStep(String status) {
    switch (status) {
      case 'pending':
      case 'pending_dispatch':
        return 0;
      case 'active':
        return 1;
      case 'completed':
        return 2;
      default:
        return 0;
    }
  }

  String get _formattedFare {
    if (_currentJob.status == 'pending_dispatch') {
      return context.l10n.matchingCourierLabel;
    }
    final price = _currentJob.agreedPrice ?? _currentJob.suggestedPrice;
    if (price == null || price == 0) {
      return context.l10n.matchingCourierLabel;
    }
    return "\$${price.toStringAsFixed(2)}";
  }

  Widget _buildUnavailableBusyCard(BuildContext context) {
    final l10n = context.l10n;
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.access_time_outlined,
            size: 48,
            color: context.semanticColors.warning,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.allCouriersBusyTitle,
            textAlign: TextAlign.center,
            style: AppTypography.titleMd.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.allCouriersBusyDesc,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            key: const Key('job_status_retry_button'),
            text: l10n.retryBookingAction,
            icon: Icons.refresh,
            onPressed: () => _refreshJobStatus(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final marketplace = Provider.of<MarketplaceProvider>(context);
    final step = _getStatusStep(_currentJob.status);
    final isCancelled = _currentJob.status == 'cancelled';
    final isCompleted = _currentJob.status == 'completed';
    final isActive = _currentJob.status == 'active';
    final isPending = _currentJob.status == 'pending';
    final isPendingDispatch = _currentJob.status == 'pending_dispatch';
    final isUnavailable = _currentJob.status == 'unavailable';
    final displayId = _currentJob.id.length > 8
        ? AppTypography.uppercaseLabel(_currentJob.id.substring(0, 8))
        : AppTypography.uppercaseLabel(_currentJob.id);

    return AppShell(
      title: context.l10n.jobStatusTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.tooltipRefreshStatus,
          key: const Key('job_status_refresh_button'),
          icon: _isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              : const Icon(Icons.refresh),
          onPressed: () => _refreshJobStatus(),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Current Status Header Bar (Stitch Mobile Status Header)
            _buildStatusHeaderBar(
                isCancelled, isCompleted, isActive, displayId),
            const SizedBox(height: AppSpacing.md),

            // Surface job status refresh errors with retry path
            if (!_isRefreshing && marketplace.error != null) ...[
              ThemedErrorBanner(
                key: const Key('job_status_screen_error'),
                message: marketplace.error!,
                onRetry: () => _refreshJobStatus(),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // 2. Track Job Hero Banner (Stitch Live Tracking Action)
            _buildTrackJobBanner(context),
            const SizedBox(height: AppSpacing.md),

            // 3. Negotiable Transport Pricing Card (if transport)
            if (_isNegotiableTransportJob) ...[
              _buildNegotiationCard(),
              const SizedBox(height: AppSpacing.md),
            ],

            // 4. Fulfillment Progress Stepper Card or Unavailable Busy Card
            if (isUnavailable)
              _buildUnavailableBusyCard(context)
            else
              _buildFulfillmentProgressCard(
                  step, isCompleted, isActive, isCancelled),
            const SizedBox(height: AppSpacing.md),

            // 5. Route & Itinerary Card (Stitch Bento Itinerary Card)
            _buildItineraryCard(),
            const SizedBox(height: AppSpacing.md),

            // 6. Assigned Courier Driver Card (if assigned)
            if (_currentJob.employeeId != null) ...[
              _buildAssignedCourierCard(context),
              const SizedBox(height: AppSpacing.md),
            ],

            // 7. Cancellation reason banner if cancelled
            if (isCancelled && _currentJob.cancellationReason != null) ...[
              _buildCancellationBanner(),
              const SizedBox(height: AppSpacing.md),
            ],

            // 8. Contextual Action Buttons
            ..._buildActionButtons(context, isCompleted, isPending, isActive,
                isPendingDispatch, isUnavailable),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeaderBar(
    bool isCancelled,
    bool isCompleted,
    bool isActive,
    String displayId,
  ) {
    final l10n = context.l10n;
    return ThemedPanel(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.smBorder,
        border: Border.all(color: AppColors.outlineVariant, width: 1),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        // A8/B4-F1: Wrap never overflows — the tracking-ID + badge cluster
        // drops to a second line on narrow screens instead of being crushed
        // (this row previously overflowed by up to 213px at 360dp).
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ThemedPanel(
                    shape: BoxShape.circle,
                    color: isCancelled
                        ? AppColors.error
                        : isCompleted
                            ? context.semanticColors.success
                            : AppColors.secondary,
                    width: 10,
                    height: 10),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  isCancelled
                      ? l10n.statusCancelled
                      : isCompleted
                          ? l10n.statusCompleted
                          : isActive
                              ? l10n.stepInTransitTitle
                              : l10n.statusPending,
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            // A8: inner Wrap — a long status badge can exceed the whole
            // line on very narrow screens; wrapping beats clipping here.
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  "#QD-$displayId",
                  style: AppTypography.labelSm.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                StatusBadge(status: _currentJob.status),
              ],
            ),
          ],
        ));
  }

  Widget _buildTrackJobBanner(BuildContext context) {
    return ThemedCard(
      key: const Key('open_map_tracking_button'),
      borderRadius: AppRadius.md,
      color: AppColors.primaryContainer,
      padding: AppSpacing.md,
      onTap: () {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        if (auth.token != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => CustomerJobMapScreen(
                jobId: _currentJob.id,
                token: auth.token!,
              ),
            ),
          );
        }
      },
      child: Row(
        children: [
          ThemedPanel(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              width: 44,
              height: 44,
              child: const Icon(
                Icons.map_outlined,
                color: AppColors.secondary,
                size: 24,
              )),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.trackJobHeroTitle,
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  context.l10n.trackJobHeroSubtitle,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.onPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildFulfillmentProgressCard(
    int step,
    bool isCompleted,
    bool isActive,
    bool isCancelled,
  ) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.fulfillmentProgressHeader,
            style: AppTypography.titleMd.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildFulfillmentStep(
            index: 0,
            title: context.l10n.statusPending,
            subtitle: context.l10n.stepRequestQueuedSub,
            icon: Icons.check,
            isDone: step > 0 || isCompleted || isActive,
            isActive: step == 0 && !isCancelled,
            isLast: false,
          ),
          _buildFulfillmentStep(
            index: 1,
            title: context.l10n.stepAssignedTitle,
            subtitle: _currentJob.employeeId == null
                ? context.l10n.matchingCourierLabel
                : (_resolvedUsername != null && _resolvedUsername!.isNotEmpty
                    ? context.l10n.assignedToLine(_resolvedUsername!)
                    : context.l10n.courierAssignedShort),
            icon: Icons.person_pin_circle_outlined,
            isDone: step > 1 || isCompleted,
            isActive: step == 1 && !isCancelled,
            isLast: false,
          ),
          _buildFulfillmentStep(
            index: 2,
            title: context.l10n.stepInTransitTitle,
            subtitle: context.l10n.stepInTransitSub,
            icon: Icons.local_shipping_outlined,
            isDone: isCompleted,
            isActive: isActive,
            isLast: false,
          ),
          _buildFulfillmentStep(
            index: 3,
            title: context.l10n.statusCompleted,
            subtitle: isCompleted
                ? context.l10n.stepDeliveredOkSub
                : context.l10n.stepPendingDeliverySub,
            icon: Icons.flag_outlined,
            isDone: isCompleted,
            isActive: false,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFulfillmentStep({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDone,
    required bool isActive,
    required bool isLast,
  }) {
    final Color nodeBg = isDone
        ? Theme.of(context).colorScheme.primary
        : isActive
            ? AppColors.secondary
            : Theme.of(context).colorScheme.surfaceContainerHigh;
    final Color nodeColor = isDone || isActive
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            ThemedPanel(
                shape: BoxShape.circle,
                color: nodeBg,
                boxShadow: isActive ? AppElevation.shadowLevel1List : null,
                width: 32,
                height: 32,
                child: Icon(icon, size: 16, color: nodeColor)),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: isDone
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDone || isActive
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItineraryCard() {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Text(
                context.l10n.itineraryHeader,
                style: AppTypography.titleMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Pickup & Dropoff vertical timeline
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  ThemedPanel(
                      shape: BoxShape.circle,
                      color: AppColors.primaryContainer,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2),
                      width: 14,
                      height: 14),
                  Container(
                    width: 2,
                    height: 36,
                    color: AppColors.outlineVariant,
                  ),
                  ThemedPanel(
                      shape: BoxShape.circle,
                      color: AppColors.secondary,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2),
                      width: 14,
                      height: 14),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.pickupStageBadge,
                      style: AppTypography.labelSm.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      context.l10n.originCustomerLocation,
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      context.l10n.dropoffStageBadge,
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      context.l10n.deliveryDestinationLabel,
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          // Payment method & fare summary (declutter V2): one compact row;
          // the itemized breakdown expands on demand.
          InkWell(
            key: const Key('fare_details_toggle'),
            onTap: () =>
                setState(() => _fareDetailsExpanded = !_fareDetailsExpanded),
            borderRadius: AppRadius.smBorder,
            child: ThemedPanel(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.smBorder,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            AppTypography.uppercaseLabel(
                                _currentJob.paymentMethod),
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            context.l10n.totalFareLabel,
                            style: AppTypography.caption.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formattedFare,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      _fareDetailsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                )),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                children: [
                  _buildInfoRow(
                    context.l10n.paymentSectionHeader,
                    AppTypography.uppercaseLabel(_currentJob.paymentMethod),
                  ),
                  _buildInfoRow(
                    context.l10n.totalFareLabel,
                    _formattedFare,
                  ),
                  if (_currentJob.proposedPrice != null)
                    _buildInfoRow(
                      context.l10n.proposedFareLabel,
                      "\$${_currentJob.proposedPrice!.toStringAsFixed(2)}",
                    ),
                  if (_currentJob.lockedEscrowAmount != null)
                    _buildInfoRow(
                      context.l10n.reconciliationLockedEscrow,
                      "\$${_currentJob.lockedEscrowAmount!.toStringAsFixed(2)}",
                    ),
                ],
              ),
            ),
            crossFadeState: _fareDetailsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: AppMotion.durationFast,
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedCourierCard(BuildContext context) {
    final l10n = context.l10n;
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.md,
      child: Row(
        children: [
          EntityAvatar(
            name: _resolvedUsername ?? l10n.courierDriverLabel,
            radius: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _resolvedUsername != null && _resolvedUsername!.isNotEmpty
                      ? _resolvedUsername!
                      : l10n.assignedCourierLabel,
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  context.l10n.verifiedCourierDriver,
                  style: AppTypography.caption.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l10n.tooltipOpenChat,
            key: const Key('open_chat_button'),
            icon: Icon(
              Icons.chat_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChatScreen(jobId: _currentJob.id),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCancellationBanner() {
    return ThemedPanel(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: AppRadius.smBorder,
        border: Border.all(color: AppColors.error),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                context.l10n
                    .cancellationReasonLine(_currentJob.cancellationReason!),
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ));
  }

  List<Widget> _buildActionButtons(
    BuildContext context,
    bool isCompleted,
    bool isPending,
    bool isActive,
    bool isPendingDispatch,
    bool isUnavailable,
  ) {
    return [
      if (isUnavailable) ...[
        PrimaryButton(
          key: const Key('job_status_unavailable_retry_button'),
          text: context.l10n.retryBookingAction,
          icon: Icons.refresh,
          onPressed: () => _refreshJobStatus(),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (isCompleted) ...[
        PrimaryButton(
          key: const Key('rate_job_button'),
          text: context.l10n.rateYourExperienceCta,
          icon: Icons.star_outline,
          trailingIcon: Icons.arrow_forward,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => RatingScreen(job: _currentJob),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (isPending || isPendingDispatch) ...[
        SecondaryButton(
          key: const Key('cancel_job_button'),
          text: context.l10n.ownerHomeCancelJob,
          icon: Icons.cancel_outlined,
          isOutlined: true,
          onPressed: () async {
            final auth = Provider.of<AuthProvider>(context, listen: false);
            final provider =
                Provider.of<MarketplaceProvider>(context, listen: false);
            await CancelJobDialog.show(
              context,
              jobId: _currentJob.id,
              onConfirm: (reason) async {
                await provider.cancelJob(
                  jobId: _currentJob.id,
                  reason: reason,
                  userToken: auth.token!,
                );
                if (mounted) {
                  final cancelL10n = this.context.l10n;
                  final isNonCod =
                      _currentJob.paymentMethod.toLowerCase() != 'cod';
                  final msg = isNonCod
                      ? cancelL10n.ownerHomeJobCancelledEscrowRefunded
                      : cancelL10n.ownerHomeJobCancelled;
                  ThemedSnackBar.showSuccess(this.context, msg);
                  _refreshJobStatus();
                }
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ] else if (isActive) ...[
        SecondaryButton(
          key: const Key('open_complaint_ticket_button'),
          text: context.l10n.openComplaintTicketBtn,
          icon: Icons.report_problem_outlined,
          isOutlined: true,
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => CreateTicketDialog(
                contextId: _currentJob.id,
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      SecondaryButton(
        text: context.l10n.backToDirectoryBtn,
        isOutlined: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
  }

  Widget _buildNegotiationCard() {
    final l10n = context.l10n;
    final suggested = _currentJob.suggestedPrice ?? 0.0;
    final proposed = _currentJob.proposedPrice;
    final proposedBy = _currentJob.proposedBy;
    final expired = _isNegotiationExpired;
    final status = _currentJob.status;

    final minPrice = 0.5 * suggested;
    final maxPrice = 1.5 * suggested;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = auth.user?.id;

    // Declutter V2: collapsed by default behind a compact CTA row; the full
    // matrix (proposal comparison, counter-offer input) expands on demand.
    final negotiationActive = status == 'awaiting_price_response' && !expired;
    return ThemedCard(
      elevation: AppElevation.shadowLevel2List,
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('negotiation_panel_toggle'),
            onTap: () =>
                setState(() => _negotiationExpanded = !_negotiationExpanded),
            borderRadius: AppRadius.smBorder,
            child: Row(
              children: [
                Icon(
                  Icons.handshake_outlined,
                  size: 20,
                  color: context.semanticColors.warning,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.priceNegotiationTitle,
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (negotiationActive)
                  ThemedPanel(
                      color: context.semanticColors.warning
                          .withValues(alpha: 0.15),
                      borderRadius: AppRadius.smBorder,
                      border: Border.all(color: context.semanticColors.warning),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs / 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 14, color: context.semanticColors.warning),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            _remainingTimeString,
                            key: const Key('countdown_timer_text'),
                            style: AppTypography.labelMd.copyWith(
                              color: context.semanticColors.warning,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  _negotiationExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Expired state banner
          if (expired) ...[
            ThemedPanel(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: AppRadius.smBorder,
                border: Border.all(color: AppColors.error),
                key: const Key('negotiation_expired_banner'),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const Icon(Icons.alarm_off, color: AppColors.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        context.l10n.negotiationExpiredBanner,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                )),
            const SizedBox(height: AppSpacing.sm),
          ],

          if (_negotiationExpanded) ...[
            // System Suggested Price display
            _buildInfoRow(l10n.originalSystemPriceLabel,
                "\$${suggested.toStringAsFixed(2)}"),

            if (_currentJob.agreedPrice != null)
              _buildInfoRow(l10n.agreedPriceLabel,
                  "\$${_currentJob.agreedPrice!.toStringAsFixed(2)}"),

            // If an active price proposal exists (proposed != null)
            if (proposed != null &&
                status == 'awaiting_price_response' &&
                !expired) ...[
              const Divider(
                  height: AppSpacing.md, color: AppColors.outlineVariant),
              ThemedPanel(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: AppRadius.smBorder,
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                  key: const Key('incoming_proposal_card'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // A8: flexible + ellipsis — inflexible pair overflowed
                          // at 360dp inside the proposal card.
                          Expanded(
                            child: Text(
                              l10n.incomingProposalCard,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              l10n.proposalByLine(proposedBy == 'customer'
                                  ? l10n.proposalRoleCustomer
                                  : l10n.proposalRoleDriverEmployee),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelMd.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              l10n.proposedFareLabel,
                              style: AppTypography.bodyMd.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              "\$${proposed.toStringAsFixed(2)}",
                              key: const Key('proposed_price_text'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.headlineLgMobile.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        "${l10n.comparisonPrefix} ${proposed - suggested >= 0 ? '+' : ''}\$${(proposed - suggested).toStringAsFixed(2)} (${proposed - suggested >= 0 ? '+' : ''}${(suggested > 0 ? ((proposed - suggested) / suggested) * 100 : 0.0).toStringAsFixed(1)}% ${l10n.vsSystemPrice})",
                        key: const Key('proposal_comparison_text'),
                        style: AppTypography.labelMd.copyWith(
                          color: (proposed - suggested) > 0
                              ? context.semanticColors.warning
                              : context.semanticColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )),
              const SizedBox(height: AppSpacing.md),
              if ((proposedBy == 'customer' &&
                      currentUserId == _currentJob.userId) ||
                  (proposedBy == 'employee' &&
                      currentUserId == _currentJob.employeeId))
                Text(
                  l10n.waitingProposalResponse,
                  style: AppTypography.bodyMd.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        key: const Key('accept_proposal_button'),
                        text: l10n.acceptProposalBtn,
                        icon: Icons.check,
                        isLoading: _isRespondingProposal,
                        onPressed: () => _respondToProposal('accept'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SecondaryButton(
                        key: const Key('decline_proposal_button'),
                        text: l10n.declineProposalBtn,
                        icon: Icons.close,
                        isOutlined: true,
                        isLoading: _isRespondingProposal,
                        onPressed: () => _respondToProposal('decline'),
                      ),
                    ),
                  ],
                ),
            ],

            // If NO proposal exists yet (proposed == null) and state is awaiting_price_response and not expired
            if (proposed == null &&
                status == 'awaiting_price_response' &&
                !expired) ...[
              const Divider(
                  height: AppSpacing.md, color: AppColors.outlineVariant),
              Text(
                l10n.submitCounterOfferBtn,
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.allowedBoundLine(
                    minPrice.toStringAsFixed(2), maxPrice.toStringAsFixed(2)),
                style: AppTypography.labelMd.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // A8/B4-F1: below ~340dp the fixed-width button starves the
              // offer input; stack the pair vertically instead.
              LayoutBuilder(builder: (context, constraints) {
                final narrow = constraints.maxWidth < 340;
                final fieldContent = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThemedTextField(
                      key: const Key('counter_offer_input'),
                      controller: _counterOfferController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      hintText: l10n
                          .negotiationHintExample(suggested.toStringAsFixed(2)),
                      prefixIcon: const Icon(
                        Icons.attach_money,
                        size: AppIconSize.sm,
                        color: AppColors.outline,
                      ),
                    ),
                    if (_proposalError != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _proposalError!,
                        style: AppTypography.labelMd.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                );
                final submitButton = SizedBox(
                  width: narrow ? double.infinity : 150,
                  child: PrimaryButton(
                    key: const Key('submit_proposal_button'),
                    text: l10n.submit,
                    isLoading: _isSubmittingProposal,
                    onPressed: () => _submitCounterOffer(suggested),
                  ),
                );
                // A8/B4-F1: Expanded is horizontal-only; the stacked path must
                // not place flex children inside an unbounded-height column.
                return narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          fieldContent,
                          const SizedBox(height: AppSpacing.sm),
                          submitButton,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: fieldContent),
                          const SizedBox(width: AppSpacing.sm),
                          submitButton,
                        ],
                      );
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMd.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
