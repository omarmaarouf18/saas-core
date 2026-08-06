import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_text_field.dart';

class OwnerConfigurationScreen extends StatefulWidget {
  const OwnerConfigurationScreen({super.key});

  @override
  State<OwnerConfigurationScreen> createState() =>
      _OwnerConfigurationScreenState();
}

class _OwnerConfigurationScreenState extends State<OwnerConfigurationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _workingHoursController = TextEditingController();
  final _radiusController = TextEditingController();
  final _basePriceController = TextEditingController();
  final _pricePerKmController = TextEditingController();
  final _photoUrlController = TextEditingController();

  String _selectedCategory = 'delivery';
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isInitialized = false;
  Map<String, dynamic>? _existingService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndPrepopulate();
    });
  }

  Future<void> _loadAndPrepopulate() async {
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (ownerProvider.services.isEmpty) {
      await ownerProvider.fetchServices();
    }

    if (mounted) {
      final services = ownerProvider.services;
      Map<String, dynamic>? match;
      for (final s in services) {
        if (s is Map &&
            (s['tenant_id'] == user?.id || s['owner_id'] == user?.id)) {
          match = Map<String, dynamic>.from(s);
          break;
        }
      }

      if (match != null) {
        _existingService = match;
        _nameController.text = match['name']?.toString() ?? '';
        _selectedCategory = match['category']?.toString() ?? 'delivery';
        _addressController.text = match['address']?.toString() ?? '';
        _workingHoursController.text = match['working_hours']?.toString() ?? '';
        _radiusController.text = match['coverage_radius_km']?.toString() ?? '';
        _basePriceController.text =
            match['tenant_base_price']?.toString() ?? '';
        _pricePerKmController.text =
            match['tenant_price_per_km']?.toString() ?? '';
        _photoUrlController.text = match['photo_url']?.toString() ?? '';
      }

      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _workingHoursController.dispose();
    _radiusController.dispose();
    _basePriceController.dispose();
    _pricePerKmController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final radius = double.tryParse(_radiusController.text.trim());
    if (radius == null || radius <= 0) {
      setState(() {
        _errorMessage = 'Coverage radius must be a positive number (> 0).';
      });
      return;
    }

    final basePrice = double.tryParse(_basePriceController.text.trim());
    if (basePrice == null || basePrice < 0) {
      setState(() {
        _errorMessage = 'Base price must be a non-negative number.';
      });
      return;
    }

    final pricePerKm = double.tryParse(_pricePerKmController.text.trim());
    if (pricePerKm == null || pricePerKm < 0) {
      setState(() {
        _errorMessage = 'Price per KM must be a non-negative number.';
      });
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    final user = authProvider.user;

    if (user == null) {
      setState(() {
        _errorMessage = 'User not authenticated.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final serviceId = _existingService?['id']?.toString() ??
          _existingService?['service_id']?.toString() ??
          '';

      if (serviceId.isNotEmpty) {
        await ownerProvider.updateOwnerServiceConfig(
          serviceId: serviceId,
          ownerId: user.id,
          name: _nameController.text.trim(),
          category: _selectedCategory,
          tenantBasePrice: basePrice,
          tenantPricePerKM: pricePerKm,
          photoUrl: _photoUrlController.text.trim(),
          address: _addressController.text.trim(),
          workingHours: _workingHoursController.text.trim(),
          coverageRadiusKm: radius,
        );
      } else {
        await ownerProvider.createService(
          name: _nameController.text.trim(),
          category: _selectedCategory,
          tenantBasePrice: basePrice,
          tenantPricePerKM: pricePerKm,
          latitude: 30.0444,
          longitude: 31.2357,
          ownerId: user.id,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Owner configuration updated successfully"),
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
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: const Text("Owner Configuration"),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: !_isInitialized
          ? const Center(
              child:
                  ThemedLoadingIndicator(message: "Loading configuration..."))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ThemedSectionHeader(
                      title: "Business Details",
                      subtitle:
                          "Configure public profile and operational rules",
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_errorMessage != null) ...[
                      ThemedErrorBanner(
                        key: const Key('owner_config_error_banner'),
                        message: _errorMessage!,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ThemedCard(
                      padding: AppSpacing.lg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ThemedTextField(
                            key: const Key('owner_config_name_field'),
                            labelText: "Business Name",
                            hintText: "Enter your business name",
                            controller: _nameController,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? "Business name is required."
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            "Service Category",
                            style: AppTypography.labelMd.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          DropdownButtonFormField<String>(
                            key: const Key('owner_config_category_dropdown'),
                            initialValue: serviceCategoryLabels
                                    .containsKey(_selectedCategory)
                                ? _selectedCategory
                                : 'delivery',
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                borderSide: const BorderSide(
                                    color: AppColors.outlineVariant),
                              ),
                            ),
                            items: serviceCategoryLabels.entries.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(e.value),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedCategory = val;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ThemedTextField(
                            key: const Key('owner_config_address_field'),
                            labelText: "Business Address",
                            hintText: "123 Main St, City, Country",
                            controller: _addressController,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ThemedTextField(
                            key: const Key('owner_config_working_hours_field'),
                            labelText: "Working Hours",
                            hintText: "e.g. 9:00 AM - 10:00 PM",
                            controller: _workingHoursController,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ThemedTextField(
                            key: const Key('owner_config_radius_field'),
                            labelText: "Coverage Radius (KM)",
                            hintText: "e.g. 25.0",
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            controller: _radiusController,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final parsed = double.tryParse(v.trim());
                              if (parsed == null || parsed <= 0) {
                                return "Enter a valid radius > 0.";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: ThemedTextField(
                                  key: const Key(
                                      'owner_config_base_price_field'),
                                  labelText: "Base Price (\$)",
                                  hintText: "10.00",
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  controller: _basePriceController,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return "Base price required.";
                                    }
                                    final parsed = double.tryParse(v.trim());
                                    if (parsed == null || parsed < 0) {
                                      return "Invalid price.";
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: ThemedTextField(
                                  key: const Key(
                                      'owner_config_price_per_km_field'),
                                  labelText: "Rate Per KM (\$)",
                                  hintText: "1.50",
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  controller: _pricePerKmController,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return "Rate per KM required.";
                                    }
                                    final parsed = double.tryParse(v.trim());
                                    if (parsed == null || parsed < 0) {
                                      return "Invalid rate.";
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ThemedTextField(
                            key: const Key('owner_config_photo_url_field'),
                            labelText: "Photo / Logo URL",
                            hintText: "https://example.com/logo.jpg",
                            controller: _photoUrlController,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          OutlinedButton.icon(
                            key: const Key('owner_config_pick_photo_button'),
                            onPressed: () {
                              _photoUrlController.text =
                                  "https://example.com/sample_logo.png";
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Sample photo URL selected."),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            icon: const Icon(Icons.photo_library_outlined,
                                size: 18),
                            label: const Text("Select Sample Photo URL"),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      key: const Key('owner_config_save_button'),
                      text: "SAVE CONFIGURATION",
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
