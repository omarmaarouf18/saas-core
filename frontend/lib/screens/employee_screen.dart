import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/app_shell.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_success_banner.dart';
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

  final _searchController = TextEditingController();
  String _statusFilter = 'all';

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

    if (auth.user != null && auth.token != null) {
      await ownerProvider.fetchAuditLog(
        tenantId: auth.user!.id,
        requesterToken: auth.token!,
      );
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
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

    final l10n = context.l10n;
    final tabBarView = TabBarView(
      controller: _tabController,
      children: [
        _buildManageWorkersTab(),
        _buildAuditTrailTab(),
      ],
    );

    // Embedded inside the owner dashboard tab (IndexedStack): the outer
    // DashboardScreenTemplate already renders the header + bottom nav, so
    // this screen must not stack a second AppBar (same pattern as
    // OwnerHistoryScreen). The Register/Audit TabBar renders in-body on the
    // brand navy block instead.
    return AppShell(
      title: l10n.employeeScreenTitle,
      showBackButton: false,
      isEmbeddedInTab: true,
      useSafeArea: false,
      body: Column(
        children: [
          Material(
            color: AppColors.primary,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.secondary,
              labelColor: AppColors.onPrimary,
              unselectedLabelColor: AppColors.onPrimary.withValues(alpha: 0.7),
              tabs: [
                Tab(
                    icon: const Icon(Icons.people_outline),
                    text: l10n.employeeScreenTitle),
                Tab(
                  icon: const Icon(Icons.receipt_long_outlined),
                  text: l10n.auditTrailTabLabel,
                ),
              ],
            ),
          ),
          Expanded(child: tabBarView),
        ],
      ),
    );
  }

  Widget _buildManageWorkersTab() {
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    final query = _searchController.text.trim().toLowerCase();
    final filteredEmployees = ownerProvider.employees.where((emp) {
      final username = (emp['username']?.toString() ?? '').toLowerCase();
      final email = (emp['email']?.toString() ?? '').toLowerCase();
      final isActive = emp['is_active'] == true;

      final matchesQuery =
          query.isEmpty || username.contains(query) || email.contains(query);

      if (!matchesQuery) return false;

      if (_statusFilter == 'active') return isActive;
      if (_statusFilter == 'frozen') return !isActive;
      return true;
    }).toList();

    final activeCount =
        ownerProvider.employees.where((e) => e['is_active'] == true).length;
    final frozenCount =
        ownerProvider.employees.where((e) => e['is_active'] != true).length;

    return RefreshIndicator(
      onRefresh: _refreshEmployees,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Registered Employees Roster Section (Stitch Reference) - Focal Card (audit E23)
            ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              topAccentColor: Theme.of(context).colorScheme.primary,
              variant: ThemedCardVariant.elevated,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ThemedPanel(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.badge_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.registeredEmployees,
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              context.l10n.employeeManageSubtitle,
                              style: AppTypography.bodyMd.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
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

                  // Search and Filter Bar
                  ThemedTextField(
                    key: const Key('employee_search_field'),
                    controller: _searchController,
                    hintText: context.l10n.employeeSearchHint,
                    prefixIcon: Icon(Icons.search,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PillFilterBar<String>(
                    padding: EdgeInsets.zero,
                    items: [
                      PillFilterItem(
                        label: l10n.filterAll,
                        value: "all",
                        count: ownerProvider.employees.length,
                      ),
                      PillFilterItem(
                        label: l10n.statusActive,
                        value: "active",
                        count: activeCount,
                      ),
                      PillFilterItem(
                        label: l10n.employeeFrozenStatus,
                        value: "frozen",
                        count: frozenCount,
                      ),
                    ],
                    selectedValue: _statusFilter,
                    onSelected: (val) => setState(() => _statusFilter = val),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Loading / Error / Empty States
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
                      onRetry: _refreshData,
                    )
                  else if (ownerProvider.employees.isEmpty)
                    ThemedEmptyState(
                      key: const Key('employees_empty_state'),
                      icon: Icons.badge_outlined,
                      title: l10n.noEmployeesRegistered,
                      description: l10n.employeeRegisterIntro,
                      actionText: l10n.addWorkerAction,
                      onActionPressed: () {
                        if (_registerFormKey.currentContext != null) {
                          Scrollable.ensureVisible(
                            _registerFormKey.currentContext!,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                    )
                  else if (filteredEmployees.isEmpty)
                    ThemedCard(
                      borderRadius: AppRadius.md,
                      padding: AppSpacing.lg,
                      child: ThemedEmptyState(
                        key: const Key('filtered_empty_employees_state'),
                        icon: Icons.search_off_outlined,
                        title: l10n.noWorkersMatchFilter,
                        description: l10n.adjustFiltersDesc,
                        actionText: l10n.clearFiltersBtn,
                        onActionPressed: () {
                          setState(() {
                            _searchController.clear();
                            _statusFilter = 'all';
                          });
                        },
                      ),
                    )
                  else
                    ListView.separated(
                      key: const Key('employees_list_view'),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredEmployees.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        return _buildEmployeeCard(filteredEmployees[index]);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 2. Register Employee Form
            _buildRegisterEmployeeForm(l10n, auth, ownerProvider),
            const SizedBox(height: AppSpacing.lg),

            // 3. Freeze/Unfreeze Worker Form
            _buildFreezeUnfreezeForm(l10n, auth, ownerProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> emp) {
    final empId = emp['id']?.toString() ?? '';
    final username = emp['username']?.toString() ?? '';
    final email = emp['email']?.toString() ?? '';
    final isActive = emp['is_active'] == true;
    final displayId = empId.length > 8
        ? AppTypography.uppercaseLabel(empId.substring(0, 8))
        : AppTypography.uppercaseLabel(empId);

    return ThemedPanel(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
        key: Key('employee_item_$empId'),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            EntityAvatar(
              name: username.isNotEmpty
                  ? username
                  : AppLocalizations.of(context)!.roleEmployeeLabel,
              radius: 22,
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
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    email,
                    style: AppTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    context.l10n.workerIdBadge(displayId),
                    style: AppTypography.caption.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
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
        ));
  }

  Widget _buildRegisterEmployeeForm(
    AppLocalizations l10n,
    AuthProvider auth,
    OwnerProvider ownerProvider,
  ) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      topAccentColor: Theme.of(context).colorScheme.secondary,
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
              prefixIcon: Icon(Icons.person_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  return l10n.usernameRequired;
                }
                final trimmed = value.trim();
                if (trimmed.runes.length < 3) {
                  return l10n.usernameTooShort;
                }
                if (trimmed.runes.length > 30) {
                  return l10n.usernameTooLong;
                }
                final usernameRegex = RegExp(r'^[a-zA-Z0-9_\s\u0600-\u06FF]+$');
                if (!usernameRegex.hasMatch(trimmed)) {
                  return l10n.usernameInvalidChars;
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
              prefixIcon: Icon(Icons.email_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.emailRequired;
                }
                final emailRegex =
                    RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                if (!emailRegex.hasMatch(value.trim())) {
                  return l10n.invalidEmailFormat;
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
              prefixIcon: Icon(Icons.lock_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.passwordRequired;
                }
                if (value.length < 6) {
                  return l10n.passwordTooShort;
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
                          final res = await ownerProvider.registerEmployee(
                            email: _regEmailController.text.trim(),
                            username: _regUsernameController.text.trim(),
                            password: _regPasswordController.text,
                            ownerId: auth.user!.id,
                          );

                          if (mounted) {
                            _regUsernameController.clear();
                            _regEmailController.clear();
                            _regPasswordController.clear();
                            ThemedSnackBar.showSuccess(
                              context,
                              l10n.employeeRegisteredSuccess(
                                res['username'] ?? '',
                                res['user_id'] ?? '',
                              ),
                              key: const Key('employee_registered_snackbar'),
                            );
                            _refreshEmployees();
                          }
                        } catch (e) {
                          debugPrint('Error registering worker: $e');
                          if (mounted) {
                            ThemedSnackBar.showError(
                              context,
                              friendlyErrorMessage(e),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isRegSubmitting = false);
                          }
                        }
                      }
                    },
              text: l10n.registerEmployeeBtn,
              isLoading: _isRegSubmitting,
              icon: Icons.person_add_alt_1_outlined,
              trailingIcon: Icons.arrow_forward,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreezeUnfreezeForm(
    AppLocalizations l10n,
    AuthProvider auth,
    OwnerProvider ownerProvider,
  ) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      topAccentColor: Theme.of(context).colorScheme.error,
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: const Key('freeze_worker_expansion_tile'),
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: AppSpacing.md),
          title: Row(
            children: [
              ThemedPanel(
                color:
                    Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                width: 36,
                height: 36,
                child: Icon(
                  Icons.lock_person_outlined,
                  color: Theme.of(context).colorScheme.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.freezeUnfreezeWorker,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.freezeWorkerSubtitle,
                      style: AppTypography.labelMd.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          children: [
            const Divider(
              height: AppSpacing.lg,
              color: AppColors.outlineVariant,
            ),
            Form(
              key: _toggleFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThemedTextField(
                    key: const Key('toggle_employee_email_input'),
                    controller: _togEmailController,
                    keyboardType: TextInputType.emailAddress,
                    labelText: l10n.employeeEmailLabel,
                    hintText: l10n.employeeEmailHint,
                    prefixIcon: Icon(Icons.email_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.employeeEmailRequired;
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
                              l10n.targetStatusLabel,
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _togSetActive
                                  ? l10n.employeeSetActiveStatus
                                  : l10n.employeeSetFrozenStatus,
                              style: AppTypography.bodyMd.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                    key: const Key('toggle_owner_password_input'),
                    controller: _togPasswordController,
                    obscureText: true,
                    isPasswordField: true,
                    labelText: l10n.confirmOwnerPassword,
                    hintText: context.l10n.secureVerificationNote,
                    prefixIcon: Icon(Icons.vpn_key_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.ownerPasswordRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    key: const Key('employee_toggle_submit_button'),
                    onPressed: _isTogSubmitting
                        ? null
                        : () async {
                            if (_toggleFormKey.currentState!.validate()) {
                              final isFreezing = !_togSetActive;
                              final targetEmail =
                                  _togEmailController.text.trim();
                              final confirmed = await ConfirmActionDialog.show(
                                context,
                                title: isFreezing
                                    ? l10n.freezeWorkerConfirmTitle
                                    : l10n.unfreezeWorkerConfirmTitle,
                                message: isFreezing
                                    ? l10n
                                        .freezeWorkerConfirmMessage(targetEmail)
                                    : l10n.unfreezeWorkerConfirmMessage(
                                        targetEmail),
                                confirmLabel: isFreezing
                                    ? l10n.freezeWorkerBtn
                                    : l10n.unfreezeWorkerBtn,
                                cancelLabel: l10n.cancel,
                                isDestructive: isFreezing,
                              );

                              if (confirmed != true || !mounted) return;

                              setState(() => _isTogSubmitting = true);
                              try {
                                final res = await ownerProvider.toggleEmployee(
                                  employeeEmail: targetEmail,
                                  ownerEmail: auth.user!.email,
                                  ownerPassword: _togPasswordController.text,
                                  setActive: _togSetActive,
                                );

                                if (mounted) {
                                  _togPasswordController.clear();
                                  ThemedSnackBar.showSuccess(
                                    context,
                                    res['message'] ??
                                        l10n.workerStatusChangedSuccessMsg,
                                    key: const Key(
                                        'employee_status_updated_snackbar'),
                                  );
                                  _refreshEmployees();
                                }
                              } catch (e) {
                                debugPrint('Error toggling worker status: $e');
                                if (mounted) {
                                  ThemedSnackBar.showError(
                                    context,
                                    friendlyErrorMessage(e),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _isTogSubmitting = false);
                                }
                              }
                            }
                          },
                    text: _togSetActive
                        ? l10n.unfreezeWorkerBtn
                        : l10n.freezeWorkerBtn,
                    isDestructive: !_togSetActive,
                    isLoading: _isTogSubmitting,
                    icon: _togSetActive
                        ? Icons.check_circle_outline
                        : Icons.block_flipped,
                  ),
                ],
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

    if (ownerProvider.isLoading && ownerProvider.auditLogEntries.isEmpty) {
      return ThemedLoadingIndicator(message: l10n.loadingAuditTrail);
    }

    final hasError = ownerProvider.error != null;
    final entries = ownerProvider.auditLogEntries;

    return RefreshIndicator(
      onRefresh: _refreshAuditLog,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: entries.isEmpty ? 1 : entries.length + (hasError ? 1 : 0),
        itemBuilder: (context, index) {
          if (hasError && (entries.isEmpty || index == 0)) {
            final banner = Padding(
              padding:
                  EdgeInsets.only(bottom: entries.isEmpty ? 0 : AppSpacing.md),
              child: ThemedErrorBanner(
                key: const Key('audit_log_error_banner'),
                message: ownerProvider.error!,
                onRetry: _refreshAuditLog,
              ),
            );
            return banner;
          }

          final entryIndex =
              (hasError && entries.isNotEmpty) ? index - 1 : index;

          if (entries.isEmpty) {
            return ThemedCard(
              borderRadius: AppRadius.md,
              padding: AppSpacing.lg,
              child: ThemedEmptyState(
                icon: Icons.receipt_long_outlined,
                title: l10n.noAuditEventsTitle,
                description: l10n.noAuditEventsDesc,
                actionText: l10n.refreshAuditLogBtn,
                onActionPressed: _refreshAuditLog,
              ),
            );
          }

          final entry = entries[entryIndex];
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
                        AppTypography.uppercaseLabel(action.toString()),
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: AppTypography.labelMd.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (clientIp.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.clientIpLine(clientIp),
                      style: AppTypography.labelMd.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
