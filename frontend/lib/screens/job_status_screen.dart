import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
import 'chat_screen.dart';
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

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _refreshJobStatus(silent: true);
    });
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Counter-offer submitted successfully!"),
            backgroundColor: AppColors.success,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.error,
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(decision == 'accept'
                ? "Price proposal accepted! Job is now active."
                : "Price proposal declined. Job cancelled."),
            backgroundColor:
                decision == 'accept' ? AppColors.success : AppColors.error,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.error,
          ),
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
    final statusColor = StatusBadge.getStatusColor(_currentJob.status);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: const Text("Job Progress"),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Banner Card
            ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              color: statusColor.withValues(alpha: 0.08),
              child: Column(
                children: [
                  Icon(
                    isCancelled
                        ? Icons.cancel_outlined
                        : _currentJob.status == 'completed'
                            ? Icons.check_circle_outline
                            : Icons.hourglass_empty,
                    size: 48,
                    color: statusColor,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Status: ${_currentJob.status.toUpperCase()}",
                    style: AppTypography.headlineLgMobile.copyWith(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "Job ID: ${_currentJob.id}",
                    style: AppTypography.labelMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Negotiable Transport Pricing Card
            if (_isNegotiableTransportJob) ...[
              _buildNegotiationCard(),
              const SizedBox(height: AppSpacing.md),
            ],

            // Progress Timeline (Stepper visual design)
            if (!isCancelled) ...[
              ThemedCard(
                borderRadius: AppRadius.md,
                padding: AppSpacing.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ThemedSectionHeader(
                      title: "Live Tracking",
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildStepRow(
                      index: 0,
                      currentStep: step,
                      title: "Request Placed",
                      subtitle: "Waiting for operator approval",
                      isLast: false,
                    ),
                    _buildStepRow(
                      index: 1,
                      currentStep: step,
                      title: "Worker Dispatched",
                      subtitle: _currentJob.employeeId == null
                          ? "Assigning an employee..."
                          : (_resolvedUsername != null &&
                                  _resolvedUsername!.isNotEmpty
                              ? "Assigned to: $_resolvedUsername"
                              : "Employee assigned & active"),
                      isLast: false,
                    ),
                    _buildStepRow(
                      index: 2,
                      currentStep: step,
                      title: "Job Completed",
                      subtitle: "Delivery completed successfully",
                      isLast: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Job details info
            ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ThemedSectionHeader(
                    title: "Job Details",
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildInfoRow("Payment Method",
                      _currentJob.paymentMethod.toUpperCase()),
                  _buildInfoRow("Service ID", _currentJob.serviceId),
                  _buildInfoRow(
                    "Destination",
                    "${_currentJob.location.latitude.toStringAsFixed(4)}, ${_currentJob.location.longitude.toStringAsFixed(4)}",
                  ),
                  if (_currentJob.employeeId != null)
                    _buildInfoRow(
                      "Assigned Employee",
                      _resolvedUsername != null && _resolvedUsername!.isNotEmpty
                          ? _resolvedUsername!
                          : _currentJob.employeeId!,
                    ),
                  if (isCancelled && _currentJob.cancellationReason != null)
                    _buildInfoRow(
                        "Cancellation Reason", _currentJob.cancellationReason!),
                  const Divider(
                    height: AppSpacing.lg,
                    color: AppColors.outlineVariant,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Total Charge (COD)",
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        "\$${_currentJob.lockedEscrowAmount ?? '0.00'}",
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (_currentJob.status == 'completed') ...[
              PrimaryButton(
                text: "Rate Your Experience",
                icon: Icons.star_outline,
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

            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    text: "Chat Support",
                    icon: Icons.chat_bubble_outline,
                    isOutlined: true,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              ChatScreen(jobId: _currentJob.id),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SecondaryButton(
                    text: "Refresh Status",
                    icon: Icons.refresh,
                    isOutlined: true,
                    isLoading: _isRefreshing,
                    onPressed: () => _refreshJobStatus(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            PrimaryButton(
              text: "Back to Directory",
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNegotiationCard() {
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
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThemedSectionHeader(
            title: "Price Negotiation",
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
                        const SizedBox(width: 4),
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
                  child: TextField(
                    key: const Key('counter_offer_input'),
                    controller: _counterOfferController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: "e.g. ${suggested.toStringAsFixed(2)}",
                      prefixText: "\$ ",
                      errorText: _proposalError,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                      border: const OutlineInputBorder(),
                    ),
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

  Widget _buildStepRow({
    required int index,
    required int currentStep,
    required String title,
    required String subtitle,
    required bool isLast,
  }) {
    final bool isDone = index < currentStep;
    final bool isCurrent = index == currentStep;
    final Color indicatorColor = isDone
        ? AppColors.success
        : isCurrent
            ? AppColors.primary
            : AppColors.outlineVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppColors.success : AppColors.surface,
                border: Border.all(
                  color: indicatorColor,
                  width: 2,
                ),
              ),
              child: isDone
                  ? const Icon(Icons.check,
                      size: 14, color: AppColors.onPrimary)
                  : isCurrent
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: isDone ? AppColors.success : AppColors.outlineVariant,
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDone || isCurrent
                        ? AppColors.onSurface
                        : AppColors.outline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.labelMd.copyWith(
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
