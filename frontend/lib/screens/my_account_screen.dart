import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/email_change_dialog.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
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

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(l10n.myAccountTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: !_isInitialized
          ? Center(child: ThemedLoadingIndicator(message: l10n.loading))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ThemedSectionHeader(
                      title: l10n.myAccountHeader,
                      subtitle: l10n.myAccountHeaderSub,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_errorMessage != null) ...[
                      ThemedErrorBanner(
                        key: const Key('my_account_error_banner'),
                        message: _errorMessage!,
                        onRetry: _submitForm,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ThemedCard(
                      padding: AppSpacing.lg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Email (Read-Only)
                          ThemedTextField(
                            key: const Key('my_account_email_field'),
                            labelText: l10n.myAccountEmailLabel,
                            hintText: l10n.myAccountEmailHint,
                            controller:
                                TextEditingController(text: user?.email ?? ''),
                            enabled: false,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            l10n.myAccountEmailNote,
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SecondaryButton(
                              key: const Key('change_email_button'),
                              text: l10n.changeEmailButton,
                              icon: Icons.email_outlined,
                              isOutlined: true,
                              isFullWidth: false,
                              onPressed: () => _showEmailChangeDialog(context),
                            ),
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
                          const SizedBox(height: AppSpacing.lg),

                          // 4. Frequent Addresses List Editor
                          Text(
                            "${l10n.myAccountAddressesHeader} (${_frequentAddresses.length}/10)",
                            style: AppTypography.labelMd.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            l10n.myAccountAddressesSub,
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),

                          // Add address input row
                          Row(
                            children: [
                              Expanded(
                                child: ThemedTextField(
                                  key:
                                      const Key('my_account_new_address_field'),
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
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs),
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
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final address = _frequentAddresses[index];
                                return ListTile(
                                  key: Key('my_account_address_item_$index'),
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                      Icons.location_on_outlined,
                                      size: 20,
                                      color: AppColors.primary),
                                  title: Text(
                                    address,
                                    style: AppTypography.bodyMd,
                                  ),
                                  trailing: IconButton(
                                    key:
                                        Key('my_account_remove_address_$index'),
                                    icon: const Icon(Icons.delete_outline,
                                        color: AppColors.error, size: 20),
                                    onPressed: () => _removeAddress(index),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      key: const Key('my_account_save_button'),
                      text: l10n.myAccountSaveButton,
                      isLoading: _isSubmitting,
                      onPressed: _submitForm,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _showEmailChangeDialog(BuildContext context) async {
    await EmailChangeDialog.show(context);
  }
}
