import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/error_messages.dart';
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                          l10n.createNewServiceTitle,
                          style: AppTypography.titleMd.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('close_create_service_dialog'),
                        icon: const Icon(Icons.close),
                        tooltip: context.l10n.tooltipClose,
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
                        ? l10n.nameRequiredError
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    key: const Key('service_category_dropdown'),
                    initialValue: _selectedCategory,
                    style: AppTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.categoryLabel,
                      labelStyle: AppTypography.labelLg.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.defaultBorder,
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadius.defaultBorder,
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
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
                        return l10n.basePriceRequired;
                      }
                      final val = double.tryParse(value);
                      if (val == null || val < 0) {
                        return l10n.invalidPriceValue;
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
                        return l10n.rateRequired;
                      }
                      final val = double.tryParse(value);
                      if (val == null || val < 0) {
                        return l10n.invalidRateValue;
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
                        return l10n.fieldRequiredGeneric;
                      }
                      final val = double.tryParse(value);
                      if (val == null || val < -90.0 || val > 90.0) {
                        return l10n.latRangeMessage;
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
                        return l10n.fieldRequiredGeneric;
                      }
                      final val = double.tryParse(value);
                      if (val == null || val < -180.0 || val > 180.0) {
                        return l10n.lonRangeMessage;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          text: l10n.cancel,
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
                          text: l10n.createActionLabel,
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
                                    l10n.serviceCreateFailed(
                                        friendlyErrorMessage(e)),
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
