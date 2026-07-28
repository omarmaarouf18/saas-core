import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
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
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Register Employee Form
          ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.lg,
            child: Form(
              key: _registerFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ThemedSectionHeader(
                    title: "Register New Employee",
                  ),
                  const Divider(
                    height: AppSpacing.lg,
                    color: AppColors.outlineVariant,
                  ),
                  ThemedTextField(
                    controller: _regUsernameController,
                    textDirection: _regUsernameDirection,
                    labelText: "Employee Username",
                    prefixIcon: const Icon(Icons.person_outline,
                        color: AppColors.outline),
                    onChanged: (val) {
                      if (val.isNotEmpty) {
                        final firstRune = val.runes.first;
                        if (firstRune >= 0x0600 && firstRune <= 0x06FF) {
                          setState(() {
                            _regUsernameDirection = TextDirection.rtl;
                          });
                        } else {
                          setState(() {
                            _regUsernameDirection = TextDirection.ltr;
                          });
                        }
                      } else {
                        setState(() {
                          _regUsernameDirection = null;
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Username is required";
                      }
                      final trimmed = value.trim();
                      final runeCount = trimmed.runes.length;
                      if (runeCount < 3) {
                        return "Username must be at least 3 characters";
                      }
                      if (runeCount > 30) {
                        return "Username must be at most 30 characters";
                      }
                      final usernameRegex =
                          RegExp(r'^([a-zA-Z0-9_ ]|[\u0600-\u06FF])+$');
                      if (!usernameRegex.hasMatch(trimmed)) {
                        return "Username contains invalid characters";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ThemedTextField(
                    controller: _regEmailController,
                    keyboardType: TextInputType.emailAddress,
                    labelText: "Employee Email",
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: AppColors.outline),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Email is required";
                      }
                      if (!value.contains("@")) {
                        return "Invalid email address";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ThemedTextField(
                    controller: _regPasswordController,
                    obscureText: true,
                    labelText: "Employee Password",
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
                                // ---------------------------------------------------------------------------
                                // API Call: Register Employee
                                // Convention: Uses RAW owner ID (auth.user!.id) as 'owner_id' JSON body parameter.
                                // Why: /auth/signup validates the owner's existence via direct GetByID lookup.
                                // ---------------------------------------------------------------------------
                                final res =
                                    await ownerProvider.registerEmployee(
                                  email: _regEmailController.text.trim(),
                                  username: _regUsernameController.text.trim(),
                                  password: _regPasswordController.text,
                                  ownerId: auth.user!.id,
                                );

                                if (mounted) {
                                  _regEmailController.clear();
                                  _regUsernameController.clear();
                                  _regPasswordController.clear();
                                  _showSuccessDialog(
                                    title: "Employee Registered",
                                    message:
                                        "Successfully created employee account:\n"
                                        "Username: ${res['username'] ?? ''}\n"
                                        "Email: ${res['email'] ?? ''}\n"
                                        "ID: ${res['user_id'] ?? ''}\n\n"
                                        "This account has no 2FA (auto-confirmed) and is ready for direct login.",
                                  );
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
                    text: "Register Worker",
                    isLoading: _isRegSubmitting,
                    icon: Icons.person_add_alt_1_outlined,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 2. Freeze/Activate Toggle Form
          ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.lg,
            child: Form(
              key: _toggleFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ThemedSectionHeader(
                    title: "Freeze / Activate Worker Account",
                  ),
                  const Divider(
                    height: AppSpacing.lg,
                    color: AppColors.outlineVariant,
                  ),
                  ThemedTextField(
                    controller: _togEmailController,
                    keyboardType: TextInputType.emailAddress,
                    labelText: "Employee Email",
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Account Status Setting:",
                        style: AppTypography.bodyLg.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.onSurface,
                        ),
                      ),
                      ChoiceChip(
                        label: Text(_togSetActive ? "ACTIVE" : "FREEZE"),
                        selected: true,
                        selectedColor: _togSetActive
                            ? AppColors.success.withValues(alpha: 0.15)
                            : AppColors.error.withValues(alpha: 0.15),
                        labelStyle: AppTypography.labelLg.copyWith(
                          color: _togSetActive
                              ? AppColors.success
                              : AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                        avatar: Icon(
                          _togSetActive
                              ? Icons.check_circle_outline
                              : Icons.block_flipped,
                          color: _togSetActive
                              ? AppColors.success
                              : AppColors.error,
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
                  const SizedBox(height: AppSpacing.md),
                  ThemedTextField(
                    controller: _togPasswordController,
                    obscureText: true,
                    labelText: "Confirm Owner Password",
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
                                // ---------------------------------------------------------------------------
                                // API Call: Toggle Employee Status (Freeze/Activate)
                                // Convention: Uses owner email and owner password (re-auth) in JSON body.
                                // Why: /auth/employee/toggle re-verifies the owner password via bcrypt.
                                // ---------------------------------------------------------------------------
                                final res = await ownerProvider.toggleEmployee(
                                  employeeEmail:
                                      _togEmailController.text.trim(),
                                  ownerEmail: auth.user!.email,
                                  ownerPassword: _togPasswordController.text,
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
                                debugPrint('Error toggling worker status: $e');
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
    );
  }

  Widget _buildAuditTrailTab() {
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return ownerProvider.isLoading && ownerProvider.auditLogEntries.isEmpty
        ? const ThemedLoadingIndicator(message: "Loading audit trail...")
        : RefreshIndicator(
            onRefresh: _refreshAuditLog,
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: ownerProvider.auditLogEntries.isEmpty
                  ? 1
                  : ownerProvider.auditLogEntries.length,
              itemBuilder: (context, index) {
                if (ownerProvider.auditLogEntries.isEmpty) {
                  return const ThemedCard(
                    borderRadius: AppRadius.md,
                    padding: AppSpacing.lg,
                    child: ThemedEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: "No audit events recorded",
                      description: "No audit events recorded for this tenant.",
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
                        const Divider(
                          height: AppSpacing.md,
                          color: AppColors.outlineVariant,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Worker ID:",
                                  style: AppTypography.labelMd.copyWith(
                                    color: AppColors.outline,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  employeeId,
                                  style: AppTypography.bodyMd.copyWith(
                                    fontFamily: 'monospace',
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "IP Address:",
                                  style: AppTypography.labelMd.copyWith(
                                    color: AppColors.outline,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  clientIp,
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurface,
                                  ),
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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.success),
              const SizedBox(width: AppSpacing.base),
              Text(
                title,
                style: AppTypography.titleMd.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                "OK",
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
