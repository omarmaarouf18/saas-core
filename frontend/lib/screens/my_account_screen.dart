import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_text_field.dart';

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
    final text = _newAddressController.text.trim();
    if (text.isEmpty) return;

    if (_frequentAddresses.length >= 10) {
      setState(() {
        _errorMessage = 'Cannot add more than 10 frequent addresses.';
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
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_frequentAddresses.length > 10) {
      setState(() {
        _errorMessage = 'Cannot add more than 10 frequent addresses.';
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile updated successfully"),
            duration: Duration(seconds: 2),
            backgroundColor: AppColors.success,
          ),
        );
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
    final user = authProvider.user;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: const Text("My Account"),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: !_isInitialized
          ? const Center(
              child:
                  ThemedLoadingIndicator(message: "Loading account details..."))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ThemedSectionHeader(
                      title: "Account Details",
                      subtitle: "Manage personal details and saved addresses",
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_errorMessage != null) ...[
                      ThemedErrorBanner(
                        key: const Key('my_account_error_banner'),
                        message: _errorMessage!,
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
                            labelText: "Email Address (Read-Only)",
                            hintText: "Your email address",
                            controller:
                                TextEditingController(text: user?.email ?? ''),
                            enabled: false,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            "Email address cannot be changed.",
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // 2. Username (Editable)
                          ThemedTextField(
                            key: const Key('my_account_username_field'),
                            labelText: "Username",
                            hintText: "Enter username",
                            controller: _usernameController,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? "Username is required."
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // 3. Phone (Editable)
                          ThemedTextField(
                            key: const Key('my_account_phone_field'),
                            labelText: "Phone Number",
                            hintText: "+201012345678",
                            keyboardType: TextInputType.phone,
                            controller: _phoneController,
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          // 4. Frequent Addresses List Editor
                          Text(
                            "Frequent Addresses (${_frequentAddresses.length}/10)",
                            style: AppTypography.labelMd.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            "Save quick locations for faster booking (max 10).",
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
                                  labelText: "New Address",
                                  hintText: "e.g. 123 Nile St, Cairo",
                                  controller: _newAddressController,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              ElevatedButton(
                                key: const Key('my_account_add_address_button'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.md,
                                  ),
                                ),
                                onPressed: _addAddress,
                                child: const Text("ADD"),
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
                                "No saved addresses yet.",
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
                      text: "SAVE PROFILE",
                      isLoading: _isSubmitting,
                      onPressed: _submitForm,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
