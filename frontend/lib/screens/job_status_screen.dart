import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
import 'chat_screen.dart';
import 'rating_screen.dart';

class JobStatusScreen extends StatefulWidget {
  final Job job;

  const JobStatusScreen({super.key, required this.job});

  @override
  State<JobStatusScreen> createState() => _JobStatusScreenState();
}

class _JobStatusScreenState extends State<JobStatusScreen> {
  late Job _currentJob;
  Timer? _pollingTimer;
  bool _isRefreshing = false;
  String? _resolvedUsername;
  String? _lastResolvedEmployeeId;

  @override
  void initState() {
    super.initState();
    _currentJob = widget.job;
    _startPolling();
    _resolveEmployeeUsername();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _refreshJobStatus(silent: true);
    });
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
        setState(() {
          _resolvedUsername = null;
          _lastResolvedEmployeeId = null;
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'active':
        return AppColors.primary;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _getStatusStep(_currentJob.status);
    final isCancelled = _currentJob.status == 'cancelled';
    final statusColor = _getStatusColor(_currentJob.status);

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

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                Expanded(
                  child: Container(
                    width: 2,
                    color:
                        isDone ? AppColors.success : AppColors.outlineVariant,
                  ),
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
