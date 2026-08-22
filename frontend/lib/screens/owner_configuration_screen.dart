import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';

typedef ImagePickerCallback = Future<String?> Function(BuildContext context);

class OwnerConfigurationScreen extends StatefulWidget {
  final ImagePickerCallback? onPickImage;
  const OwnerConfigurationScreen({super.key, this.onPickImage});

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
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isInitialized = false;
  Map<String, dynamic>? _existingService;

  Future<void> _pickImage() async {
    if (widget.onPickImage != null) {
      final path = await widget.onPickImage!(context);
      if (path != null && mounted) {
        setState(() {
          _photoUrlController.text = path;
        });
      }
      return;
    }
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile != null && mounted) {
        setState(() {
          _photoUrlController.text = xfile.path;
        });
      }
    } catch (_) {}
  }

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
        final rawLat = match['latitude'];
        final rawLon = match['longitude'];
        _latitude = (rawLat as num?)?.toDouble() ?? 30.0444;
        _longitude = (rawLon as num?)?.toDouble() ?? 31.2357;
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

  void _openLocationPickerDialog(BuildContext context) {
    final l10n = context.l10n;
    LatLng tempLocation = (_latitude != null && _longitude != null)
        ? LatLng(_latitude!, _longitude!)
        : LocationPickerMap.cairoDefault;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final screenSize = MediaQuery.of(dialogCtx).size;
        final dialogWidth = math.min(500.0, screenSize.width * 0.9);
        final dialogHeight = math.min(550.0, screenSize.height * 0.8);

        return Dialog(
          key: const Key('location_picker_dialog'),
          insetPadding: const EdgeInsets.all(AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.customerMarketplaceChooseMap,
                          style: AppTypography.titleMd.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.tooltipClose,
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: LocationPickerMap(
                        initialLocation: tempLocation,
                        onLocationSelected: (newLocation) {
                          tempLocation = newLocation;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    key: const Key('confirm_location_button'),
                    text: "Confirm Location",
                    onPressed: () {
                      setState(() {
                        _latitude = tempLocation.latitude;
                        _longitude = tempLocation.longitude;
                      });
                      Navigator.of(dialogCtx).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitForm() async {
    final l10n = context.l10n;
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_latitude == null || _longitude == null) {
      setState(() {
        _errorMessage = l10n.ownerConfigLocationReq;
      });
      return;
    }

    final radius = double.tryParse(_radiusController.text.trim());
    if (radius == null || radius <= 0) {
      setState(() {
        _errorMessage = l10n.ownerConfigRadiusReq;
      });
      return;
    }

    final basePrice = double.tryParse(_basePriceController.text.trim());
    if (basePrice == null || basePrice < 0) {
      setState(() {
        _errorMessage = l10n.ownerConfigBasePriceReq;
      });
      return;
    }

    final pricePerKm = double.tryParse(_pricePerKmController.text.trim());
    if (pricePerKm == null || pricePerKm < 0) {
      setState(() {
        _errorMessage = l10n.ownerConfigPricePerKmReq;
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
          latitude: _latitude,
          longitude: _longitude,
        );
      } else {
        await ownerProvider.createService(
          name: _nameController.text.trim(),
          category: _selectedCategory,
          tenantBasePrice: basePrice,
          tenantPricePerKM: pricePerKm,
          latitude: _latitude!,
          longitude: _longitude!,
          ownerId: user.id,
        );
      }

      if (mounted) {
        ThemedSnackBar.showSuccess(context, l10n.ownerConfigSuccessMsg);
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
    final l10n = context.l10n;

    return FormScreenTemplate(
      title: l10n.ownerConfigTitle,
      backgroundColor: AppColors.scaffoldBackground,
      padding: const EdgeInsets.all(AppSpacing.lg),
      body: !_isInitialized
          ? Center(child: ThemedLoadingIndicator(message: l10n.loading))
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ThemedSectionHeader(
                    title: l10n.ownerConfigHeader,
                    subtitle: l10n.ownerConfigHeaderSub,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_errorMessage != null) ...[
                    ThemedErrorBanner(
                      key: const Key('owner_config_error_banner'),
                      message: _errorMessage!,
                      onRetry: _submitForm,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Section 1: Business Identity Card (Stitch Reference)
                  _buildBusinessIdentityCard(l10n),
                  const SizedBox(height: AppSpacing.lg),

                  // Section 2: Location & Operations Card (Stitch Reference)
                  _buildLocationOperationsCard(l10n),
                  const SizedBox(height: AppSpacing.lg),

                  // Section 3: Pricing Structure Card (Stitch Reference)
                  _buildPricingStructureCard(l10n),
                  const SizedBox(height: AppSpacing.xl),

                  // Section 4: Primary Save Action Button
                  _buildSaveButton(l10n),
                ],
              ),
            ),
    );
  }

  Widget _buildBusinessIdentityCard(AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  width: 36,
                  height: 36,
                  child: const Center(
                    child: Icon(
                      Icons.storefront_outlined,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                  )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.sectionBusinessIdentity,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      context.l10n.sectionBusinessIdentitySub,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(
            height: AppSpacing.lg,
            color: AppColors.outlineVariant,
          ),
          // Logo Upload / Picker Area
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: AppColors.outlineVariant,
                  ),
                  width: 64,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  child: _photoUrlController.text.isNotEmpty
                      ? (_photoUrlController.text.startsWith('http')
                          ? Image.network(
                              _photoUrlController.text,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.business_outlined,
                                color: AppColors.primary,
                                size: 32,
                              ),
                            )
                          : const Icon(
                              Icons.image_outlined,
                              color: AppColors.primary,
                              size: 32,
                            ))
                      : const Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.outline,
                          size: 32,
                        )),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _photoUrlController.text.isNotEmpty
                          ? _photoUrlController.text
                          : l10n.ownerConfigPhotoUrlHint,
                      key: const Key('owner_config_photo_url_field'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMd.copyWith(
                        color: _photoUrlController.text.isNotEmpty
                            ? AppColors.onSurface
                            : AppColors.outline,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SecondaryButton(
                      key: const Key('owner_config_pick_image_button'),
                      icon: Icons.upload_file_outlined,
                      text: l10n.tooltipPickImage,
                      isOutlined: true,
                      isFullWidth: false,
                      onPressed: _pickImage,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ThemedTextField(
            key: const Key('owner_config_name_field'),
            labelText: l10n.ownerConfigNameLabel,
            hintText: l10n.ownerConfigNameHint,
            controller: _nameController,
            validator: (v) =>
                v == null || v.trim().isEmpty ? l10n.ownerConfigNameReq : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.ownerConfigCategoryLabel,
            style: AppTypography.labelMd.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            key: const Key('owner_config_category_dropdown'),
            initialValue: serviceCategoryLabels.containsKey(_selectedCategory)
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
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.outlineVariant),
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
        ],
      ),
    );
  }

  Widget _buildLocationOperationsCard(AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  width: 36,
                  height: 36,
                  child: const Center(
                    child: Icon(
                      Icons.location_on_outlined,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                  )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.sectionLocationOperations,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      context.l10n.sectionLocationOperationsSub,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(
            height: AppSpacing.lg,
            color: AppColors.outlineVariant,
          ),
          ThemedTextField(
            key: const Key('owner_config_address_field'),
            labelText: l10n.ownerConfigAddressLabel,
            hintText: l10n.ownerConfigAddressHint,
            controller: _addressController,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.ownerConfigLocationLabel,
            style: AppTypography.labelLg.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ThemedPanel(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      (_latitude != null && _longitude != null)
                          ? "Lat: ${_latitude!.toStringAsFixed(4)}, Lon: ${_longitude!.toStringAsFixed(4)}"
                          : "No location selected",
                      key: const Key('owner_config_location_text'),
                      style: AppTypography.bodyMd.copyWith(
                        color: (_latitude != null && _longitude != null)
                            ? AppColors.onSurface
                            : AppColors.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SecondaryButton(
                    key: const Key('owner_config_location_picker_button'),
                    icon: Icons.map_outlined,
                    text: l10n.customerMarketplaceChooseMap,
                    isOutlined: true,
                    isFullWidth: false,
                    onPressed: () => _openLocationPickerDialog(context),
                  ),
                ],
              )),
          const SizedBox(height: AppSpacing.md),
          ThemedTextField(
            key: const Key('owner_config_working_hours_field'),
            labelText: l10n.ownerConfigHoursLabel,
            hintText: l10n.ownerConfigHoursHint,
            controller: _workingHoursController,
          ),
          const SizedBox(height: AppSpacing.md),
          ThemedTextField(
            key: const Key('owner_config_radius_field'),
            labelText: l10n.ownerConfigRadiusLabel,
            hintText: l10n.ownerConfigRadiusHint,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            controller: _radiusController,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final parsed = double.tryParse(v.trim());
              if (parsed == null || parsed <= 0) {
                return l10n.ownerConfigRadiusReq;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPricingStructureCard(AppLocalizations l10n) {
    final basePriceVal = double.tryParse(_basePriceController.text) ?? 0.0;
    final pricePerKmVal = double.tryParse(_pricePerKmController.text) ?? 0.0;
    final est10km = basePriceVal + (pricePerKmVal * 10);

    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  width: 36,
                  height: 36,
                  child: const Center(
                    child: Icon(
                      Icons.payments_outlined,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                  )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.sectionPricingStructure,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      context.l10n.sectionPricingStructureSub,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(
            height: AppSpacing.lg,
            color: AppColors.outlineVariant,
          ),
          Row(
            children: [
              Expanded(
                child: ThemedTextField(
                  key: const Key('owner_config_base_price_field'),
                  labelText: l10n.ownerConfigBasePriceLabel,
                  hintText: l10n.ownerConfigBasePriceHint,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  controller: _basePriceController,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.ownerConfigBasePriceReq;
                    }
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed < 0) {
                      return l10n.ownerConfigBasePriceReq;
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ThemedTextField(
                  key: const Key('owner_config_price_per_km_field'),
                  labelText: l10n.ownerConfigPricePerKmLabel,
                  hintText: l10n.ownerConfigPricePerKmHint,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  controller: _pricePerKmController,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.ownerConfigPricePerKmReq;
                    }
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed < 0) {
                      return l10n.ownerConfigPricePerKmReq;
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          if (est10km > 0) ...[
            const SizedBox(height: AppSpacing.md),
            ThemedPanel(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.estDelivery10kmLabel,
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      "\$${est10km.toStringAsFixed(2)}",
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton(AppLocalizations l10n) {
    return PrimaryButton(
      key: const Key('owner_config_save_button'),
      text: l10n.ownerConfigSaveButton,
      trailingIcon: Icons.arrow_forward,
      isLoading: _isSubmitting,
      onPressed: _submitForm,
    );
  }
}
