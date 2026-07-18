import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import 'employee_jobs_screen.dart';

class EmployeeScreen extends StatefulWidget {
  const EmployeeScreen({super.key});

  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _registerFormKey = GlobalKey<FormState>();
  final _toggleFormKey = GlobalKey<FormState>();

  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();

  final _togEmailController = TextEditingController();
  final _togPasswordController = TextEditingController();
  bool _togSetActive = true;

  bool _isRegSubmitting = false;
  bool _isTogSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAuditLog();
    });
  }

  void _handleTabChange() {
    if (_tabController.index == 1) {
      _refreshAuditLog();
    }
  }

  Future<void> _refreshAuditLog() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);

    // ---------------------------------------------------------------------------
    // API Call: Fetch Tenant Audit Log
    // Convention: Uses RAW owner ID (auth.user!.id) as 'tenant_id' AND JWT (auth.token) as 'requester_id'.
    // Why: auth-service verifies the requester identity (JWT) matches tenant_id.
    // ---------------------------------------------------------------------------
    await ownerProvider.fetchAuditLog(
      tenantId: auth.user!.id,
      requesterToken: auth.token!,
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _togEmailController.dispose();
    _togPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (auth.user?.role == 'employee') {
      return const EmployeeJobsScreen();
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          color: Colors.white,
          child: SafeArea(
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.people_outline), text: "Manage Workers"),
                Tab(
                    icon: Icon(Icons.receipt_long_outlined),
                    text: "Audit Trail"),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManageWorkersTab(),
          _buildAuditTrailTab(),
        ],
      ),
    );
  }

  Widget _buildManageWorkersTab() {
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Register Employee Form
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _registerFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Register New Employee",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const Divider(height: 24),
                    TextFormField(
                      controller: _regEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "Employee Email",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty)
                          return "Email is required";
                        if (!value.contains("@"))
                          return "Invalid email address";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _regPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Employee Password",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return "Password is required";
                        if (value.length < 6)
                          return "Password must be at least 6 characters";
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isRegSubmitting
                            ? null
                            : () async {
                                if (_registerFormKey.currentState!.validate()) {
                                  setState(() => _isRegSubmitting = true);
                                  try {
                                    // ---------------------------------------------------------------------------
                                    // API Call: Register Employee
                                    // Convention: Uses RAW owner ID (auth.user!.id) as 'owner_id' JSON body parameter.
                                    // Why: /auth/signup validates the owner's existence via direct GetByID lookup.
                                    // ---------------------------------------------------------------------------
                                    final res =
                                        await ownerProvider.registerEmployee(
                                      email: _regEmailController.text.trim(),
                                      password: _regPasswordController.text,
                                      ownerId: auth.user!.id,
                                    );

                                    if (mounted) {
                                      _regEmailController.clear();
                                      _regPasswordController.clear();
                                      _showSuccessDialog(
                                        title: "Employee Registered",
                                        message:
                                            "Successfully created employee account:\n"
                                            "Email: ${res['email'] ?? ''}\n"
                                            "ID: ${res['user_id'] ?? ''}\n\n"
                                            "This account has no 2FA (auto-confirmed) and is ready for direct login.",
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(e.toString()),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted)
                                      setState(() => _isRegSubmitting = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: _isRegSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text("Register Worker"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
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
          ),
          const SizedBox(height: 24),

          // 2. Freeze/Activate Toggle Form
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _toggleFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Freeze / Activate Worker Account",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const Divider(height: 24),
                    TextFormField(
                      controller: _togEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "Employee Email",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty)
                          return "Employee email is required";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Account Status Setting:",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        ChoiceChip(
                          label: Text(_togSetActive ? "ACTIVE" : "FREEZE"),
                          selected: true,
                          selectedColor: _togSetActive
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          labelStyle: TextStyle(
                            color: _togSetActive
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                          avatar: Icon(
                            _togSetActive
                                ? Icons.check_circle_outline
                                : Icons.block_flipped,
                            color: _togSetActive
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                            size: 18,
                          ),
                          onSelected: (_) {
                            setState(() {
                              _togSetActive = !_togSetActive;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _togPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Confirm Owner Password",
                        helperText:
                            "Required for secure out-of-band operations verification.",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return "Owner password is required to re-authenticate";
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isTogSubmitting
                            ? null
                            : () async {
                                if (_toggleFormKey.currentState!.validate()) {
                                  setState(() => _isTogSubmitting = true);
                                  try {
                                    // ---------------------------------------------------------------------------
                                    // API Call: Toggle Employee Status (Freeze/Activate)
                                    // Convention: Uses owner email and owner password (re-auth) in JSON body.
                                    // Why: /auth/employee/toggle re-verifies the owner password via bcrypt.
                                    // ---------------------------------------------------------------------------
                                    final res =
                                        await ownerProvider.toggleEmployee(
                                      employeeEmail:
                                          _togEmailController.text.trim(),
                                      ownerEmail: auth.user!.email,
                                      ownerPassword:
                                          _togPasswordController.text,
                                      setActive: _togSetActive,
                                    );

                                    if (mounted) {
                                      _togPasswordController.clear();
                                      _showSuccessDialog(
                                        title: "Worker Status Updated",
                                        message: res['message'] ??
                                            "Successfully changed status.",
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(e.toString()),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted)
                                      setState(() => _isTogSubmitting = false);
                                  }
                                }
                              },
                        icon: Icon(_togSetActive
                            ? Icons.check_circle_outline
                            : Icons.block_flipped),
                        label: _isTogSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_togSetActive
                                ? "Unfreeze Worker"
                                : "Freeze Worker"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _togSetActive
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          foregroundColor: Colors.white,
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
          ),
        ],
      ),
    );
  }

  Widget _buildAuditTrailTab() {
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return ownerProvider.isLoading && ownerProvider.auditLogEntries.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refreshAuditLog,
            child: ListView.builder(
              padding: const EdgeInsets.all(24.0),
              itemCount: ownerProvider.auditLogEntries.isEmpty
                  ? 1
                  : ownerProvider.auditLogEntries.length,
              itemBuilder: (context, index) {
                if (ownerProvider.auditLogEntries.isEmpty) {
                  return Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(
                        child: Text(
                          "No audit events recorded for this tenant.",
                          style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  );
                }

                // Render logs reverse-chronologically (which the backend GetAuditLog already does)
                final entry = ownerProvider.auditLogEntries[index];
                final action = entry['action'] ?? '';
                final employeeId = entry['employee_id'] ?? '';
                final clientIp = entry['client_ip'] ?? '';

                DateTime? timestamp;
                if (entry['timestamp'] != null) {
                  try {
                    timestamp = DateTime.parse(entry['timestamp']).toLocal();
                  } catch (_) {}
                }

                final dateStr = timestamp != null
                    ? "${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} ${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}:${_twoDigits(timestamp.second)}"
                    : "";

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              action.toString().toUpperCase(),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 14),
                            ),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Worker ID:",
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  employeeId,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Colors.black87),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "IP Address:",
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  clientIp,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black87),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
  }

  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";

  void _showSuccessDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }
}
