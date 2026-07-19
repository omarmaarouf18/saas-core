import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/employee_jobs_provider.dart';
import '../providers/notifications_provider.dart';
import '../models/job.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';

class EmployeeJobsScreen extends StatefulWidget {
  const EmployeeJobsScreen({super.key});

  @override
  State<EmployeeJobsScreen> createState() => _EmployeeJobsScreenState();
}

class _EmployeeJobsScreenState extends State<EmployeeJobsScreen> {
  final _actionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSimulating = false;

  final List<String> _suggestions = [
    "Arrived at Pickup",
    "Job in Route",
    "Arrived at Destination",
    "Job Completed",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshJobs();
    });
  }

  @override
  void dispose() {
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _refreshJobs() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token != null) {
      await Provider.of<EmployeeJobsProvider>(context, listen: false)
          .fetchAssignedJobs(auth.token!);
    }
  }

  Future<void> _submitAction() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<EmployeeJobsProvider>(context, listen: false);
    final email = auth.user?.email ?? '';
    final action = _actionController.text.trim();

    setState(() => _isSimulating = true);

    try {
      await provider.simulateAction(email: email, action: action);
      if (mounted) {
        _actionController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Action logged successfully: \"$action\""),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString();
        if (errorMsg.contains("employee account is frozen")) {
          _showErrorDialog(
            title: "Account Frozen",
            message:
                "Operation Denied: Your employee account has been frozen by the tenant administrator. Please contact your manager to resolve this issue.",
          );
        } else if (errorMsg.contains("owner KYC approval is pending")) {
          _showErrorDialog(
            title: "KYC Approval Pending",
            message:
                "Operation Denied: The business owner's KYC verification is still pending. All simulated field operations are blocked until the owner is approved by a super administrator.",
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Simulation Failed: $errorMsg"),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSimulating = false);
      }
    }
  }

  void _showErrorDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Dismiss"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    return Consumer<NotificationsProvider>(
      builder: (context, provider, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications),
              tooltip: 'Notifications',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  ),
                );
              },
            ),
            if (provider.unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '${provider.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final jobsProvider = Provider.of<EmployeeJobsProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Employee Jobs Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Jobs",
            onPressed: _refreshJobs,
          ),
          _buildNotificationBell(context),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshJobs,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(auth.user?.username.isNotEmpty == true
                  ? auth.user!.username
                  : (auth.user?.email ?? '')),
              const SizedBox(height: 24),
              _buildActionSimulatorCard(),
              const SizedBox(height: 28),
              const Text(
                "Your Assigned Jobs",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              if (jobsProvider.isLoading && jobsProvider.jobs.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (jobsProvider.error != null && jobsProvider.jobs.isEmpty)
                _buildErrorCard(jobsProvider.error!)
              else
                _buildJobsList(jobsProvider.jobs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String displayName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Welcome back!",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Logged in as: $displayName",
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildActionSimulatorCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Employee Action Simulator",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Log service events directly into the tenant audit trail.",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const Divider(height: 24),
              TextFormField(
                controller: _actionController,
                decoration: const InputDecoration(
                  labelText: "Simulation Action Text",
                  hintText: "e.g., Arrived at Pickup, Job in Route",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.run_circle_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter or select an action to simulate";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _suggestions.map((suggestion) {
                  return ActionChip(
                    label:
                        Text(suggestion, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      setState(() {
                        _actionController.text = suggestion;
                      });
                    },
                    backgroundColor: Colors.grey.shade200,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSimulating ? null : _submitAction,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: _isSimulating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text("Simulate Action"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String errorMsg) {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                errorMsg,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobsList(List<Job> jobs) {
    if (jobs.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(40.0),
          child: Center(
            child: Text(
              "No jobs currently assigned to you.",
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: jobs.length,
      itemBuilder: (context, index) {
        final job = jobs[index];
        return _buildJobCard(job);
      },
    );
  }

  Widget _buildJobCard(Job job) {
    Color statusColor;
    switch (job.status.toLowerCase()) {
      case 'completed':
        statusColor = const Color(0xFF00E676); // kStatusSuccess
        break;
      case 'active':
        statusColor = const Color(0xFFFF7A00); // kStatusWarning
        break;
      case 'cancelled':
        statusColor = const Color(0xFFFF1744); // kStatusDanger
        break;
      case 'pending':
      default:
        statusColor = Colors.grey;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "Job ID: ${job.id}",
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor, width: 1),
                  ),
                  child: Text(
                    job.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildJobDetailRow(
              Icons.location_on_outlined,
              "Destination",
              "Lat: ${job.location.latitude.toStringAsFixed(6)}, Lon: ${job.location.longitude.toStringAsFixed(6)}",
            ),
            const SizedBox(height: 10),
            _buildJobDetailRow(
              Icons.person_outline,
              "Customer ID",
              job.userId,
            ),
            const SizedBox(height: 10),
            _buildJobDetailRow(
              Icons.payment_outlined,
              "Payment Method",
              job.paymentMethod.toUpperCase(),
            ),
            if (job.lockedEscrowAmount != null &&
                job.lockedEscrowAmount! > 0) ...[
              const SizedBox(height: 10),
              _buildJobDetailRow(
                Icons.lock_clock_outlined,
                "Escrow Locked",
                "${job.lockedEscrowAmount!.toStringAsFixed(2)} Credits",
              ),
            ],
            if (job.cancellationReason != null &&
                job.cancellationReason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Cancellation Reason: ${job.cancellationReason}",
                  style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJobDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black54,
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
