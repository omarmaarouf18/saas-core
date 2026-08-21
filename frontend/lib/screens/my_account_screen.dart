import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/email_change_dialog.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _newAddressController = TextEditingController();

  List<String> _frequentAddresses = [];
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndPrepopulate();
    });
  }

  Future<void> _loadAndPrepopulate() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user != null) {
      await authProvider.fetchUserProfile();
    }

    if (mounted) {
      final user = authProvider.user;
      if (user != null) {
        _usernameController.text = user.username;
        _phoneController.text = user.phone ?? '';
        _frequentAddresses = List<String>.from(user.frequentAddresses ?? []);
      }

      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    _newAddressController.dispose();
    super.dispose();
  }

  void _addAddress() {
    final l10n = context.l10n;
    final text = _newAddressController.text.trim();
    if (text.isEmpty) return;

    if (_frequentAddresses.length >= 10) {
      setState(() {
        _errorMessage = l10n.myAccountMaxAddressesError;
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _frequentAddresses.add(text);
      _newAddressController.clear();
    });
  }

  void _removeAddress(int index) {
    setState(() {
      _errorMessage = null;
      if (index >= 0 && index < _frequentAddresses.length) {
        _frequentAddresses.removeAt(index);
      }
    });
  }

  Future<void> _submitForm() async {
    final l10n = context.l10n;
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_frequentAddresses.length > 10) {
      setState(() {
        _errorMessage = l10n.myAccountMaxAddressesError;
      });
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      _isSubmitting = true;
    });

    try {
      await authProvider.updateOwnProfile(
        username: _usernameController.text.trim(),
        phone: _phoneController.text.trim(),
        frequentAddresses: _frequentAddresses,
      );

      if (mounted) {
        ThemedSnackBar.showSuccess(context, l10n.myAccountSuccessMsg);
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = friendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final l10n = context.l10n;
    final user = authProvider.user;

    return FormScreenTemplate(
      title: l10n.myAccountTitle,
      backgroundColor: AppColors.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.marginMobile,
        vertical: AppSpacing.lg,
      ),
      body: !_isInitialized
          ? Center(child: ThemedLoadingIndicator(message: l10n.loading))
          : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Stitch Display Header
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.myAccountHeader,
                              style: AppTypography.headlineLgMobile.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              l10n.myAccountHeaderSub,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Error Banner
                        if (_errorMessage != null) ...[
                          ThemedErrorBanner(
                            key: const Key('my_account_error_banner'),
                            message: _errorMessage!,
                            onRetry: _submitForm,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],

                        // 2. Responsive Stitch Grid Structure (LayoutBuilder)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isDesktop = constraints.maxWidth > 768;
                            if (isDesktop) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left Column: Profile Form (flex 2)
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildProfileInfoCard(
                                          l10n: l10n,
                                          userEmail: user?.email ?? '',
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                        PrimaryButton(
                                          key: const Key(
                                              'my_account_save_button'),
                                          text: l10n.myAccountSaveButton,
                                          trailingIcon: Icons.arrow_forward,
                                          isLoading: _isSubmitting,
                                          onPressed: _submitForm,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.lg),
                                  // Right Column: Avatar Summary & Addresses (flex 1)
                                  Expanded(
                                    flex: 1,
                                    child: Column(
                                      children: [
                                        _buildUserOverviewCard(
                                          username: user?.username ?? '',
                                          role: user?.role ?? 'user',
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                        _buildFrequentAddressesCard(l10n: l10n),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }

                            // Mobile Layout (Stacked matching Stitch Mobile DOM)
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildProfileInfoCard(
                                  l10n: l10n,
                                  userEmail: user?.email ?? '',
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                _buildFrequentAddressesCard(l10n: l10n),
                                const SizedBox(height: AppSpacing.xl),
                                PrimaryButton(
                                  key: const Key('my_account_save_button'),
                                  text: l10n.myAccountSaveButton,
                                  trailingIcon: Icons.arrow_forward,
                                  isLoading: _isSubmitting,
                                  onPressed: _submitForm,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  // --- Profile Information Card (Stitch Left Card) ---
  Widget _buildProfileInfoCard({
    required AppLocalizations l10n,
    required String userEmail,
  }) {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      padding: AppSpacing.lg,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Profile Information',
                style: AppTypography.titleMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: AppSpacing.md),

          // 1. Email (Read-Only with Lock & Change Dialog Action)
          ThemedTextField(
            key: const Key('my_account_email_field'),
            labelText: l10n.myAccountEmailLabel,
            hintText: l10n.myAccountEmailHint,
            controller: TextEditingController(text: userEmail),
            enabled: false,
            prefixIcon: const Icon(
              Icons.lock_outline,
              size: 18,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.myAccountEmailNote,
            style: AppTypography.caption.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            key: const Key('change_email_button'),
            text: l10n.changeEmailButton,
            icon: Icons.email_outlined,
            isOutlined: true,
            isFullWidth: false,
            onPressed: () => _showEmailChangeDialog(context),
          ),
          const SizedBox(height: AppSpacing.md),

          // 2. Username (Editable)
          ThemedTextField(
            key: const Key('my_account_username_field'),
            labelText: l10n.myAccountUsernameLabel,
            hintText: l10n.myAccountUsernameHint,
            controller: _usernameController,
            validator: (v) => v == null || v.trim().isEmpty
                ? l10n.myAccountUsernameReq
                : null,
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Phone (Editable)
          ThemedTextField(
            key: const Key('my_account_phone_field'),
            labelText: l10n.myAccountPhoneLabel,
            hintText: l10n.myAccountPhoneHint,
            keyboardType: TextInputType.phone,
            controller: _phoneController,
          ),
        ],
      ),
    );
  }

  // --- User Overview Card (Stitch Desktop Right Card 1) ---
  Widget _buildUserOverviewCard({
    required String username,
    required String role,
  }) {
    final String initial =
        username.isNotEmpty ? username.substring(0, 1).toUpperCase() : 'U';

    return ThemedCard(
      borderRadius: AppRadius.lg,
      padding: AppSpacing.lg,
      color: AppColors.surface,
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.primaryContainer,
            child: Text(
              initial,
              style: AppTypography.headlineLg.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            username.isNotEmpty ? username : 'User Profile',
            style: AppTypography.titleMd.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              role.toUpperCase(),
              style: AppTypography.labelSm.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.success,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Frequent Addresses Card (Stitch Right Card 2) ---
  Widget _buildFrequentAddressesCard({required AppLocalizations l10n}) {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      padding: AppSpacing.lg,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    "${l10n.myAccountAddressesHeader} (${_frequentAddresses.length}/10)",
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.myAccountAddressesSub,
            style: AppTypography.caption.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: AppSpacing.md),

          // Add address input row
          Row(
            children: [
              Expanded(
                child: ThemedTextField(
                  key: const Key('my_account_new_address_field'),
                  labelText: l10n.myAccountNewAddressLabel,
                  hintText: l10n.myAccountNewAddressHint,
                  controller: _newAddressController,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              PrimaryButton(
                key: const Key('my_account_add_address_button'),
                text: l10n.myAccountAddButton,
                isFullWidth: false,
                onPressed: _addAddress,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // List of added addresses
          if (_frequentAddresses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                l10n.myAccountNoAddresses,
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _frequentAddresses.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppColors.outlineVariant),
              itemBuilder: (context, index) {
                final address = _frequentAddresses[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    key: Key('my_account_address_item_$index'),
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 20,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          address,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('my_account_remove_address_$index'),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.error,
                          size: 20,
                        ),
                        onPressed: () => _removeAddress(index),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showEmailChangeDialog(BuildContext context) async {
    await EmailChangeDialog.show(context);
  }
}
