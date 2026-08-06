import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_text_field.dart';

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadServices();
    });
  }

  Future<void> _loadServices() async {
    await Provider.of<OwnerProvider>(context, listen: false).fetchServices();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final owner = Provider.of<OwnerProvider>(context);
    final user = auth.user;

    if (user == null) {
      final l10n = AppLocalizations.of(context)!;
      return Scaffold(
        body: Center(
          child: Text(l10n.unauthenticatedMsg),
        ),
      );
    }

    final isKycApproved = user.kycStatus == "approved";
    // Filter services belonging to this tenant/owner
    final myServices =
        owner.services.where((s) => s['tenant_id'] == user.id).toList();

    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(l10n.ownerConfigTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _loadServices,
        child: owner.isLoading && myServices.isEmpty
            ? const ThemedLoadingIndicator(message: "Loading services...")
            : Column(
                children: [
                  if (!isKycApproved)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: ThemedErrorBanner(
                        message:
                            "KYC Approval Pending: You cannot publish new services until your profile is approved by an administrator.",
                      ),
                    ),
                  Expanded(
                    child: myServices.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 100),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg),
                                child: ThemedCard(
                                  borderRadius: AppRadius.md,
                                  padding: AppSpacing.lg,
                                  child: ThemedEmptyState(
                                    icon: Icons.design_services_outlined,
                                    title: "No Services Configured",
                                    description:
                                        "No services configured yet.\nTap the + button to create a service.",
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: myServices.length,
                            itemBuilder: (context, index) {
                              final svc = myServices[index];
                              final categoryLabel =
                                  serviceCategoryLabels[svc['category']] ??
                                      svc['category'];
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: ThemedCard(
                                  borderRadius: AppRadius.md,
                                  padding: AppSpacing.md,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              svc['name'] ?? '',
                                              style: AppTypography.titleMd
                                                  .copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              categoryLabel,
                                              style: AppTypography.labelMd
                                                  .copyWith(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(
                                        height: AppSpacing.lg,
                                        color: AppColors.outlineVariant,
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "Base Price: \$${(svc['tenant_base_price'] as num?)?.toStringAsFixed(2) ?? '0.00'}",
                                            style:
                                                AppTypography.bodyMd.copyWith(
                                              color: AppColors.onSurface,
                                            ),
                                          ),
                                          Text(
                                            "Rate per KM: \$${(svc['tenant_price_per_km'] as num?)?.toStringAsFixed(2) ?? '0.00'}",
                                            style:
                                                AppTypography.bodyMd.copyWith(
                                              color: AppColors.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        "Coordinates: (${(svc['latitude'] as num?)?.toStringAsFixed(4) ?? '0.0000'}, ${(svc['longitude'] as num?)?.toStringAsFixed(4) ?? '0.0000'})",
                                        style: AppTypography.labelMd.copyWith(
                                          color: AppColors.outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isKycApproved
            ? () => _showCreateServiceDialog(context, user.id)
            : null,
        backgroundColor:
            isKycApproved ? AppColors.secondary : AppColors.outline,
        foregroundColor:
            isKycApproved ? AppColors.onSecondary : AppColors.surface,
        tooltip: isKycApproved ? "Add Service" : "KYC Pending",
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateServiceDialog(BuildContext context, String ownerId) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final basePriceController = TextEditingController();
    final pricePerKMController = TextEditingController();
    final latController =
        TextEditingController(text: "30.0444"); // Cairo default
    final lonController = TextEditingController(text: "31.2357");

    String selectedCategory = 'delivery';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              title: Text(
                "Create New Service",
                style: AppTypography.titleMd.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemedTextField(
                        controller: nameController,
                        labelText: "Service Name",
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? "Name is required"
                                : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                        decoration: InputDecoration(
                          labelText: "Category",
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
                            setDialogState(() {
                              selectedCategory = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ThemedTextField(
                        controller: basePriceController,
                        labelText: "Base Price (\$)",
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
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
                        controller: pricePerKMController,
                        labelText: "Rate per KM (\$)",
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
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
                        controller: latController,
                        labelText: "Latitude",
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
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
                        controller: lonController,
                        labelText: "Longitude",
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
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
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: "Cancel",
                        isOutlined: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: PrimaryButton(
                        text: "Create",
                        onPressed: () async {
                          if (formKey.currentState?.validate() ?? false) {
                            final provider = Provider.of<OwnerProvider>(context,
                                listen: false);
                            try {
                              await provider.createService(
                                name: nameController.text.trim(),
                                category: selectedCategory,
                                tenantBasePrice:
                                    double.parse(basePriceController.text),
                                tenantPricePerKM:
                                    double.parse(pricePerKMController.text),
                                latitude: double.parse(latController.text),
                                longitude: double.parse(lonController.text),
                                ownerId: ownerId,
                              );
                              if (context.mounted) {
                                final l10n = AppLocalizations.of(context)!;
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.serviceCreatedSuccess),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                final l10n = AppLocalizations.of(context)!;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        l10n.serviceCreateFailed(e.toString())),
                                    backgroundColor: AppColors.error,
                                  ),
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
            );
          },
        );
      },
    );
  }
}
