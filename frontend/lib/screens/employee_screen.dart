import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_text_field.dart';
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
  final _regUsernameController = TextEditingController();
  final _regPasswordController = TextEditingController();
  TextDirection? _regUsernameDirection;

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
      _refreshData();
    });
  }

  void _handleTabChange() {
    if (_tabController.index == 1) {
      _refreshAuditLog();
    } else {
      _refreshEmployees();
    }
  }

  void _refreshData() {
    _refreshEmployees();
    if (_tabController.index == 1) {
      _refreshAuditLog();
    }
  }

  Future<void> _refreshEmployees() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    await ownerProvider.fetchEmployees(auth.token);
  }

  Future<void> _refreshAuditLog() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);

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
    _regUsernameController.dispose();
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
      backgroundColor: AppColors.scaffoldBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          color: AppColors.surface,
          child: SafeArea(
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.outline,
              indicatorColor: AppColors.primary,
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
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return RefreshIndicator(
      onRefresh: _refreshEmployees,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ThemedSectionHeader(
                          title: l10n.registeredEmployees,
                        ),
                      ),
                      IconButton(
                        key: const Key('refresh_employees_button'),
                        icon: const Icon(Icons.refresh),
                        tooltip: l10n.tooltipRefreshList,
                        onPressed: _refreshEmployees,
                      ),
                    ],
                  ),
                  const Divider(
                    height: AppSpacing.lg,
                    color: AppColors.outlineVariant,
                  ),
                  if (ownerProvider.isLoading &&
                      ownerProvider.employees.isEmpty)
                    ThemedLoadingIndicator(
                      key: const Key('employees_loading'),
                      message: l10n.loadingEmployeeList,
                    )
                  else if (ownerProvider.error != null &&
                      ownerProvider.employees.isEmpty)
                    ThemedErrorBanner(
                      key: const Key('employees_error_banner'),
                      message: ownerProvider.error!,
                    )
                  else if (ownerProvider.employees.isEmpty)
                    ThemedEmptyState(
                      key: const Key('employees_empty_state'),
                      icon: Icons.badge_outlined,
                      title: l10n.noEmployeesRegistered,
                      description:
                          "Register your first employee account using the form below.",
                    )
                  else
                    ListView.separated(
                      key: const Key('employees_list_view'),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ownerProvider.employees.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final emp = ownerProvider.employees[index];
                        final empId = emp['id']?.toString() ?? '';
                        final username = emp['username']?.toString() ?? '';
                        final email = emp['email']?.toString() ?? '';
                        final isActive = emp['is_active'] == true;

                        return Container(
                          key: Key('employee_item_$empId'),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  username.isNotEmpty
                                      ? username[0].toUpperCase()
                                      : 'E',
                                  style: const TextStyle(
                                      color: AppColors.onPrimary),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      username,
                                      style: AppTypography.titleMd.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      email,
                                      style: AppTypography.bodyMd.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              StatusBadge(
                                status: isActive ? 'active' : 'frozen',
                                compact: true,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 1. Register Employee Form
            ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              child: Form(
                key: _registerFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThemedSectionHeader(
                      title: l10n.registerNewEmployee,
                    ),
                    const Divider(
                      height: AppSpacing.lg,
                      color: AppColors.outlineVariant,
                    ),
                    ThemedTextField(
                      controller: _regUsernameController,
                      textDirection: _regUsernameDirection,
                      labelText: l10n.employeeUsernameLabel,
                      hintText: l10n.employeeUsernameHint,
                      prefixIcon: const Icon(Icons.person_outline,
                          color: AppColors.outline),
                      onChanged: (val) {
                        final trimmed = val.trim();
                        final isRtl = trimmed.isNotEmpty &&
                            RegExp(r'^[\u0600-\u06FF]').hasMatch(trimmed);
                        final newDirection =
                            isRtl ? TextDirection.rtl : TextDirection.ltr;
                        if (_regUsernameDirection != newDirection) {
                          setState(() => _regUsernameDirection = newDirection);
                        }
                      },
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Username is required";
                        }
                        if (value.trim().length < 3) {
                          return "Username must be at least 3 characters";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ThemedTextField(
                      controller: _regEmailController,
                      keyboardType: TextInputType.emailAddress,
                      labelText: l10n.employeeEmailLabel,
                      hintText: l10n.employeeEmailHint,
                      prefixIcon: const Icon(Icons.email_outlined,
                          color: AppColors.outline),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Email is required";
                        }
                        if (!value.contains('@')) {
                          return "Please enter a valid email";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ThemedTextField(
                      controller: _regPasswordController,
                      obscureText: true,
                      isPasswordField: true,
                      labelText: l10n.employeePasswordLabel,
                      hintText: l10n.employeePasswordHint,
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: AppColors.outline),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Password is required";
                        }
                        if (value.length < 6) {
                          return "Password must be at least 6 characters";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      onPressed: _isRegSubmitting
                          ? null
                          : () async {
                              if (_registerFormKey.currentState!.validate()) {
                                setState(() => _isRegSubmitting = true);
                                try {
                                  final res =
                                      await ownerProvider.registerEmployee(
                                    email: _regEmailController.text.trim(),
                                    username:
                                        _regUsernameController.text.trim(),
                                    password: _regPasswordController.text,
                                    ownerId: auth.user!.id,
                                  );

                                  if (mounted) {
                                    _regUsernameController.clear();
                                    _regEmailController.clear();
                                    _regPasswordController.clear();
                                    _showSuccessDialog(
                                      title: l10n.employeeRegisteredTitle,
                                      message:
                                          "Successfully created employee account:\n"
                                          "Username: ${res['username'] ?? ''}\n"
                                          "ID: ${res['user_id'] ?? ''}",
                                    );
                                    _refreshEmployees();
                                  }
                                } catch (e) {
                                  debugPrint('Error registering worker: $e');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(friendlyErrorMessage(e)),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isRegSubmitting = false);
                                  }
                                }
                              }
                            },
                      text: "Register Employee",
                      isLoading: _isRegSubmitting,
                      icon: Icons.person_add_alt_1_outlined,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 2. Freeze/Unfreeze Worker Form
            ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              child: Form(
                key: _toggleFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThemedSectionHeader(
                      title: l10n.freezeUnfreezeWorker,
                    ),
                    const Divider(
                      height: AppSpacing.lg,
                      color: AppColors.outlineVariant,
                    ),
                    ThemedTextField(
                      controller: _togEmailController,
                      keyboardType: TextInputType.emailAddress,
                      labelText: l10n.employeeEmailLabel,
                      hintText: l10n.employeeEmailHint,
                      prefixIcon: const Icon(Icons.email_outlined,
                          color: AppColors.outline),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Employee email is required";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Target Status",
                                style: AppTypography.titleMd.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _togSetActive
                                    ? "Set account to Active (Unfreeze)"
                                    : "Set account to Frozen (Suspended)",
                                style: AppTypography.bodyMd.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _togSetActive,
                          onChanged: (val) {
                            setState(() {
                              _togSetActive = val;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ThemedTextField(
                      controller: _togPasswordController,
                      obscureText: true,
                      isPasswordField: true,
                      labelText: l10n.confirmOwnerPassword,
                      hintText:
                          "Required for secure out-of-band operations verification.",
                      prefixIcon: const Icon(Icons.vpn_key_outlined,
                          color: AppColors.outline),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Owner password is required to re-authenticate";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      onPressed: _isTogSubmitting
                          ? null
                          : () async {
                              if (_toggleFormKey.currentState!.validate()) {
                                setState(() => _isTogSubmitting = true);
                                try {
                                  final res =
                                      await ownerProvider.toggleEmployee(
                                    employeeEmail:
                                        _togEmailController.text.trim(),
                                    ownerEmail: auth.user!.email,
                                    ownerPassword: _togPasswordController.text,
                                    setActive: _togSetActive,
                                  );

                                  if (mounted) {
                                    _togPasswordController.clear();
                                    _showSuccessDialog(
                                      title: l10n.workerStatusUpdated,
                                      message: res['message'] ??
                                          "Successfully changed status.",
                                    );
                                    _refreshEmployees();
                                  }
                                } catch (e) {
                                  debugPrint(
                                      'Error toggling worker status: $e');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(friendlyErrorMessage(e)),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isTogSubmitting = false);
                                  }
                                }
                              }
                            },
                      text: _togSetActive ? "Unfreeze Worker" : "Freeze Worker",
                      isLoading: _isTogSubmitting,
                      icon: _togSetActive
                          ? Icons.check_circle_outline
                          : Icons.block_flipped,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditTrailTab() {
    final l10n = context.l10n;
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return ownerProvider.isLoading && ownerProvider.auditLogEntries.isEmpty
        ? ThemedLoadingIndicator(message: l10n.loadingAuditTrail)
        : RefreshIndicator(
            onRefresh: _refreshAuditLog,
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: ownerProvider.auditLogEntries.isEmpty
                  ? 1
                  : ownerProvider.auditLogEntries.length,
              itemBuilder: (context, index) {
                if (ownerProvider.auditLogEntries.isEmpty) {
                  return ThemedCard(
                    borderRadius: AppRadius.md,
                    padding: AppSpacing.lg,
                    child: ThemedEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: l10n.noAuditEventsTitle,
                      description: l10n.noAuditEventsDesc,
                    ),
                  );
                }

                final entry = ownerProvider.auditLogEntries[index];
                final action = entry['action'] ?? '';
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

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ThemedCard(
                    borderRadius: AppRadius.md,
                    padding: AppSpacing.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              action.toString().toUpperCase(),
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              dateStr,
                              style: AppTypography.labelMd.copyWith(
                                color: AppColors.outline,
                              ),
                            ),
                          ],
                        ),
                        if (clientIp.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            "IP: $clientIp",
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
  }

  void _showSuccessDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(ctx)!.ok),
          ),
        ],
      ),
    );
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
