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
import '../widgets/cancel_job_dialog.dart';
import '../widgets/create_ticket_dialog.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
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
    final input = _counterOfferController.text.trim();
    final proposed = double.tryParse(input);

    final minPrice = 0.5 * suggestedPrice;
    final maxPrice = 1.5 * suggestedPrice;

    if (proposed == null) {
      setState(() => _proposalError = "Enter a valid number");
      return;
    }
    const eps = 1e-9;
    if (proposed < (minPrice - eps) || proposed > (maxPrice + eps)) {
      setState(() => _proposalError =
          "Price must be between \$${minPrice.toStringAsFixed(2)} and \$${maxPrice.toStringAsFixed(2)}");
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
          msg =
              "Job state changed — the other party already acted or status changed.";
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
            "Price proposal accepted! Job is now active.",
          );
        } else {
          ThemedSnackBar.showError(
            context,
            "Price proposal declined. Job cancelled.",
          );
        }
        _refreshJobStatus();
      }
    } catch (e) {
      if (mounted) {
        String msg;
        if (e is ApiClientException && e.statusCode == 409) {
          msg =
              "Job state changed — the other party already acted or status changed.";
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
        return 0;
      case 'active':
        return 1;
      case 'completed':
        return 2;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _getStatusStep(_currentJob.status);
    final isCancelled = _currentJob.status == 'cancelled';
    final isCompleted = _currentJob.status == 'completed';
    final isActive = _currentJob.status == 'active';
    final isPending = _currentJob.status == 'pending';
    final displayId = _currentJob.id.length > 8
        ? _currentJob.id.substring(0, 8).toUpperCase()
        : _currentJob.id.toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(context.l10n.jobStatusTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [
          IconButton(
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Current Status Header Bar (Stitch Mobile Status Header)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.smBorder,
                border: Border.all(color: AppColors.outlineVariant, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCancelled
                              ? AppColors.error
                              : isCompleted
                                  ? AppColors.success
                                  : AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        isCancelled
                            ? "Cancelled"
                            : isCompleted
                                ? "Completed"
                                : isActive
                                    ? "In Transit"
                                    : "Pending",
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        "#QD-$displayId",
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      StatusBadge(status: _currentJob.status),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // 2. Track Job Hero Banner (Stitch Live Tracking Action)
            ThemedCard(
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
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.map_outlined,
                      color: AppColors.secondary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Track Job",
                          style: AppTypography.titleMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "View real-time location on map",
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
            ),
            const SizedBox(height: AppSpacing.md),

            // 3. Negotiable Transport Pricing Card (if transport)
            if (_isNegotiableTransportJob) ...[
              _buildNegotiationCard(),
              const SizedBox(height: AppSpacing.md),
            ],

            // 4. Fulfillment Progress Stepper Card (Stitch Stepper Card)
            ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Fulfillment Progress",
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildFulfillmentStep(
                    index: 0,
                    title: "Pending",
                    subtitle: "Request placed & queued",
                    icon: Icons.check,
                    isDone: step > 0 || isCompleted || isActive,
                    isActive: step == 0 && !isCancelled,
                    isLast: false,
                  ),
                  _buildFulfillmentStep(
                    index: 1,
                    title: "Assigned",
                    subtitle: _currentJob.employeeId == null
                        ? "Matching courier..."
                        : (_resolvedUsername != null &&
                                _resolvedUsername!.isNotEmpty
                            ? "Assigned to $_resolvedUsername"
                            : "Courier assigned"),
                    icon: Icons.person_pin_circle_outlined,
                    isDone: step > 1 || isCompleted,
                    isActive: step == 1 && !isCancelled,
                    isLast: false,
                  ),
                  _buildFulfillmentStep(
                    index: 2,
                    title: "In Transit",
                    subtitle: "Package on route to destination",
                    icon: Icons.local_shipping_outlined,
                    isDone: isCompleted,
                    isActive: isActive,
                    isLast: false,
                  ),
                  _buildFulfillmentStep(
                    index: 3,
                    title: "Completed",
                    subtitle: isCompleted
                        ? "Delivered successfully"
                        : "Pending delivery",
                    icon: Icons.flag_outlined,
                    isDone: isCompleted,
                    isActive: false,
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // 4. Route & Itinerary Card (Stitch Bento Itinerary Card)
            ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.route,
                          size: 20, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        "Itinerary",
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
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
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryContainer,
                              border: Border.all(
                                  color: AppColors.surface, width: 2),
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 36,
                            color: AppColors.outlineVariant,
                          ),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.secondary,
                              border: Border.all(
                                  color: AppColors.surface, width: 2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "PICKUP",
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Origin / Customer Location",
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w500,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              "DROPOFF",
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Delivery Destination",
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w500,
                                color: AppColors.onSurface,
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
                  // Cargo load & vehicle spec
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: AppRadius.smBorder,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Payment",
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _currentJob.paymentMethod.toUpperCase(),
                                style: AppTypography.bodySm.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: AppRadius.smBorder,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Total Fare",
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "\$${(_currentJob.agreedPrice ?? _currentJob.suggestedPrice ?? 0).toStringAsFixed(2)}",
                                style: AppTypography.bodySm.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // 5. Assigned Courier Driver Card (if assigned)
            if (_currentJob.employeeId != null) ...[
              ThemedCard(
                borderRadius: AppRadius.md,
                padding: AppSpacing.md,
                child: Row(
                  children: [
                    EntityAvatar(
                      name: _resolvedUsername ?? "Courier Driver",
                      radius: 22,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _resolvedUsername != null &&
                                    _resolvedUsername!.isNotEmpty
                                ? _resolvedUsername!
                                : "Assigned Courier",
                            style: AppTypography.bodyLg.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Verified Courier Driver",
                            style: AppTypography.caption.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('open_chat_button'),
                      icon: const Icon(
                        Icons.chat_outlined,
                        color: AppColors.primary,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                ChatScreen(jobId: _currentJob.id),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // 7. Cancellation reason banner if cancelled
            if (isCancelled && _currentJob.cancellationReason != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smBorder,
                  border: Border.all(color: AppColors.error),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        "Cancellation Reason: ${_currentJob.cancellationReason!}",
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // 8. Action Buttons
            if (isCompleted) ...[
              PrimaryButton(
                key: const Key('rate_job_button'),
                text: "Rate Your Experience",
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

            if (isPending) ...[
              SecondaryButton(
                key: const Key('cancel_job_button'),
                text: "Cancel Job",
                icon: Icons.cancel_outlined,
                isOutlined: true,
                onPressed: () async {
                  final auth =
                      Provider.of<AuthProvider>(context, listen: false);
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
                        final isNonCod =
                            _currentJob.paymentMethod.toLowerCase() != 'cod';
                        final msg = isNonCod
                            ? "Job cancelled successfully. Escrow refunded to wallet."
                            : "Job cancelled successfully.";
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
                text: "Open a Complaint Ticket",
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
              text: "Back to Directory",
              isOutlined: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
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
        ? AppColors.primary
        : isActive
            ? AppColors.secondary
            : AppColors.surfaceContainerHigh;
    final Color nodeColor =
        isDone || isActive ? AppColors.onPrimary : AppColors.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: nodeBg,
                boxShadow: isActive ? AppElevation.shadowLevel1List : null,
              ),
              child: Icon(icon, size: 16, color: nodeColor),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color:
                    isDone ? AppColors.primary : AppColors.surfaceContainerHigh,
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
                        ? AppColors.onSurface
                        : AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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

    return ThemedCard(
      elevation: AppElevation.shadowLevel2List,
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThemedSectionHeader(
            title: l10n.priceNegotiationTitle,
            trailing: (status == 'awaiting_price_response' && !expired)
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xs / 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: AppRadius.smBorder,
                      border: Border.all(color: AppColors.warning),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _remainingTimeString,
                          key: const Key('countdown_timer_text'),
                          style: AppTypography.labelMd.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.md),

          // Expired state banner
          if (expired) ...[
            Container(
              key: const Key('negotiation_expired_banner'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: AppRadius.smBorder,
                border: Border.all(color: AppColors.error),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alarm_off, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      "Negotiation Window Expired (5-min limit lapsed)",
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // System Suggested Price display
          _buildInfoRow(
              "Original System Price", "\$${suggested.toStringAsFixed(2)}"),

          if (_currentJob.agreedPrice != null)
            _buildInfoRow("Agreed Price",
                "\$${_currentJob.agreedPrice!.toStringAsFixed(2)}"),

          // If an active price proposal exists (proposed != null)
          if (proposed != null &&
              status == 'awaiting_price_response' &&
              !expired) ...[
            const Divider(
                height: AppSpacing.md, color: AppColors.outlineVariant),
            Container(
              key: const Key('incoming_proposal_card'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.smBorder,
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Incoming Proposal",
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        "by ${proposedBy == 'customer' ? 'Customer' : 'Driver / Employee'}",
                        style: AppTypography.labelMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Proposed Fare:",
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.onSurface),
                      ),
                      Text(
                        "\$${proposed.toStringAsFixed(2)}",
                        key: const Key('proposed_price_text'),
                        style: AppTypography.headlineLgMobile.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "Comparison: ${proposed - suggested >= 0 ? '+' : ''}\$${(proposed - suggested).toStringAsFixed(2)} (${proposed - suggested >= 0 ? '+' : ''}${(suggested > 0 ? ((proposed - suggested) / suggested) * 100 : 0.0).toStringAsFixed(1)}% vs System Price)",
                    key: const Key('proposal_comparison_text'),
                    style: AppTypography.labelMd.copyWith(
                      color: (proposed - suggested) > 0
                          ? AppColors.warning
                          : AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if ((proposedBy == 'customer' &&
                    currentUserId == _currentJob.userId) ||
                (proposedBy == 'employee' &&
                    currentUserId == _currentJob.employeeId))
              Text(
                "Waiting for response to your proposal...",
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      key: const Key('accept_proposal_button'),
                      text: "Accept Proposal",
                      icon: Icons.check,
                      isLoading: _isRespondingProposal,
                      onPressed: () => _respondToProposal('accept'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: SecondaryButton(
                      key: const Key('decline_proposal_button'),
                      text: "Decline",
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
              "Submit Counter-Offer",
              style: AppTypography.bodyMd.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Allowed bound: \$${minPrice.toStringAsFixed(2)} – \$${maxPrice.toStringAsFixed(2)} (±50%)",
              style: AppTypography.labelMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThemedTextField(
                        key: const Key('counter_offer_input'),
                        controller: _counterOfferController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        hintText: l10n.negotiationHintExample(
                            suggested.toStringAsFixed(2)),
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
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 150,
                  child: PrimaryButton(
                    key: const Key('submit_proposal_button'),
                    text: "Submit",
                    isLoading: _isSubmittingProposal,
                    onPressed: () => _submitCounterOffer(suggested),
                  ),
                ),
              ],
            ),
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
          Text(
            label,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface,
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
