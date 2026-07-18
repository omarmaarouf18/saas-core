import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../models/job.dart';
import 'chat_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _currentJob = widget.job;
    _startPolling();
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
        return Colors.orange;
      case 'active':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _getStatusStep(_currentJob.status);
    final isCancelled = _currentJob.status == 'cancelled';
    final statusColor = _getStatusColor(_currentJob.status);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Job Progress"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: "Chat",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChatScreen(jobId: _currentJob.id),
                ),
              );
            },
          ),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: () => _refreshJobStatus(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Banner Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              color: statusColor.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
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
                    const SizedBox(height: 12),
                    Text(
                      "Status: ${_currentJob.status.toUpperCase()}",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Job ID: ${_currentJob.id}",
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Progress Timeline (Stepper visual design)
            if (!isCancelled) ...[
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Live Tracking",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
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
                            : "Employee assigned & active",
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
              ),
              const SizedBox(height: 24),
            ],

            // Job details info
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Job Details",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow("Payment Method",
                        _currentJob.paymentMethod.toUpperCase()),
                    _buildInfoRow("Service ID", _currentJob.serviceId),
                    _buildInfoRow(
                      "Destination",
                      "${_currentJob.location.latitude.toStringAsFixed(4)}, ${_currentJob.location.longitude.toStringAsFixed(4)}",
                    ),
                    if (_currentJob.employeeId != null)
                      _buildInfoRow(
                          "Assigned Employee ID", _currentJob.employeeId!),
                    if (isCancelled && _currentJob.cancellationReason != null)
                      _buildInfoRow("Cancellation Reason",
                          _currentJob.cancellationReason!),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Total Charge (COD)",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          "\$${_currentJob.lockedEscrowAmount ?? '0.00'}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text("Back to Directory"),
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
        ? Colors.green
        : isCurrent
            ? Theme.of(context).colorScheme.primary
            : Colors.grey.shade300;

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
                  color: isDone ? Colors.green : Colors.white,
                  border: Border.all(
                    color: indicatorColor,
                    width: 2,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : isCurrent
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          )
                        : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDone ? Colors.green : Colors.grey.shade300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDone || isCurrent ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
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
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
