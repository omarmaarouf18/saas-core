import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../l10n/l10n.dart';
import '../providers/owner_provider.dart';
import 'primary_button.dart';
import 'secondary_button.dart';
import 'themed_success_banner.dart';
import 'themed_text_field.dart';

class CreateServiceDialog extends StatefulWidget {
  final String ownerId;

  const CreateServiceDialog({super.key, required this.ownerId});

  static Future<void> show(BuildContext context, {required String ownerId}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CreateServiceDialog(ownerId: ownerId),
    );
  }

  @override
  State<CreateServiceDialog> createState() => _CreateServiceDialogState();
}

class _CreateServiceDialogState extends State<CreateServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _basePriceController = TextEditingController();
  final _pricePerKMController = TextEditingController();
  final _latController =
      TextEditingController(text: "30.0444"); // Cairo default
  final _lonController = TextEditingController(text: "31.2357");

  String _selectedCategory = 'delivery';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _basePriceController.dispose();
    _pricePerKMController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(500.0, screenSize.width * 0.92);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
      ),
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "Create New Service",
                          style: AppTypography.titleMd.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('close_create_service_dialog'),
                        icon: const Icon(Icons.close),
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ThemedTextField(
                    key: const Key('service_name_field'),
                    controller: _nameController,
                    labelText: l10n.serviceNameLabel,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? "Name is required"
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    key: const Key('service_category_dropdown'),
                    initialValue: _selectedCategory,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.categoryLabel,
                      labelStyle: AppTypography.labelLg.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.defaultBorder,
                        borderSide: const BorderSide(
                          color: AppColors.outlineVariant,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadius.defaultBorder,
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    items: serviceCategoryLabels.entries.map((entry) {
                      return DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedCategory = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ThemedTextField(
                    key: const Key('service_base_price_field'),
                    controller: _basePriceController,
                    labelText: l10n.basePriceLabel,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Base price is required";
                      }
                      final val = double.tryParse(value);
                      if (val == null || val < 0) {
                        return "Invalid price";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ThemedTextField(
                    key: const Key('service_price_per_km_field'),
                    controller: _pricePerKMController,
                    labelText: l10n.ratePerKmLabel,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Rate is required";
                      }
                      final val = double.tryParse(value);
                      if (val == null || val < 0) {
                        return "Invalid rate";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ThemedTextField(
                    key: const Key('service_latitude_field'),
                    controller: _latController,
                    labelText: l10n.latitudeLabel,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Required";
                      }
                      final val = double.tryParse(value);
                      if (val == null || val < -90.0 || val > 90.0) {
                        return "Must be between -90 and 90";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ThemedTextField(
                    key: const Key('service_longitude_field'),
                    controller: _lonController,
                    labelText: l10n.longitudeLabel,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Required";
                      }
                      final val = double.tryParse(value);
                      if (val == null || val < -180.0 || val > 180.0) {
                        return "Must be between -180 and 180";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          text: "Cancel",
                          isOutlined: true,
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: PrimaryButton(
                          key: const Key('service_create_button'),
                          text: "Create",
                          trailingIcon: Icons.arrow_forward,
                          isLoading: _isSubmitting,
                          onPressed: () async {
                            if (_formKey.currentState?.validate() ?? false) {
                              setState(() => _isSubmitting = true);
                              final provider = Provider.of<OwnerProvider>(
                                  context,
                                  listen: false);
                              try {
                                await provider.createService(
                                  name: _nameController.text.trim(),
                                  category: _selectedCategory,
                                  tenantBasePrice: double.parse(
                                      _basePriceController.text.trim()),
                                  tenantPricePerKM: double.parse(
                                      _pricePerKMController.text.trim()),
                                  latitude:
                                      double.parse(_latController.text.trim()),
                                  longitude:
                                      double.parse(_lonController.text.trim()),
                                  ownerId: widget.ownerId,
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ThemedSnackBar.showSuccess(
                                    context,
                                    l10n.serviceCreatedSuccess,
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  setState(() => _isSubmitting = false);
                                  ThemedSnackBar.showError(
                                    context,
                                    l10n.serviceCreateFailed(e.toString()),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
