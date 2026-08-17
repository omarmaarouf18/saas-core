import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/create_service_dialog.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_loading_indicator.dart';

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

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'delivery':
        return Icons.local_shipping_outlined;
      case 'transport':
        return Icons.directions_car_outlined;
      case 'shipping':
        return Icons.inventory_2_outlined;
      default:
        return Icons.store_outlined;
    }
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
            ? ThemedLoadingIndicator(message: l10n.loadingServices)
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Title & Description
                    Text(
                      "Service Management",
                      style: AppTypography.headlineLgMobile.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      "Configure and monitor active logistics services.",
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    if (!isKycApproved) ...[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color:
                                AppColors.outlineVariant.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              color: AppColors.outline,
                              size: 22,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Verification Required",
                                    style: AppTypography.titleMd.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    "Please complete KYC verification to create new services or modify existing ones.",
                                    style: AppTypography.bodyMd.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    if (myServices.isEmpty)
                      ThemedCard(
                        borderRadius: AppRadius.md,
                        padding: AppSpacing.lg,
                        child: ThemedEmptyState(
                          icon: Icons.design_services_outlined,
                          title: l10n.noServicesConfigured,
                          description: l10n.noServicesDescription,
                          actionText: "Create Service",
                          onActionPressed: () => CreateServiceDialog.show(
                            context,
                            ownerId: user.id,
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: myServices.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, index) {
                          final svc = myServices[index];
                          final category = svc['category']?.toString();
                          final categoryLabel =
                              serviceCategoryLabels[category] ?? category ?? '';
                          final basePrice =
                              (svc['tenant_base_price'] as num?)?.toDouble() ??
                                  0.0;
                          final pricePerKm =
                              (svc['tenant_price_per_km'] as num?)
                                      ?.toDouble() ??
                                  0.0;
                          final lat = (svc['latitude'] as num?)?.toDouble();
                          final lon = (svc['longitude'] as num?)?.toDouble();

                          return ThemedCard(
                            borderRadius: AppRadius.md,
                            padding: AppSpacing.md,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryContainer,
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          _getCategoryIcon(category),
                                          color: AppColors.secondary,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            svc['name'] ?? '',
                                            style:
                                                AppTypography.titleMd.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsetsDirectional
                                                .symmetric(
                                              horizontal: AppSpacing.baseSm,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.secondary
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppRadius.full),
                                            ),
                                            child: Text(
                                              categoryLabel,
                                              style: AppTypography.caption
                                                  .copyWith(
                                                color: AppColors
                                                    .onSecondaryContainer,
                                                fontWeight: FontWeight.bold,
                                              ),
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
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerLow,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "BASE PRICE",
                                            style:
                                                AppTypography.caption.copyWith(
                                              color: AppColors.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "\$${basePrice.toStringAsFixed(2)}",
                                            style:
                                                AppTypography.titleMd.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        height: 28,
                                        width: 1,
                                        color: AppColors.outlineVariant
                                            .withValues(alpha: 0.4),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "RATE PER KM",
                                            style:
                                                AppTypography.caption.copyWith(
                                              color: AppColors.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "\$${pricePerKm.toStringAsFixed(2)}",
                                            style:
                                                AppTypography.titleMd.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (lat != null && lon != null) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on_outlined,
                                        color: AppColors.outline,
                                        size: 16,
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Text(
                                        "Location: (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})",
                                        style: AppTypography.labelMd.copyWith(
                                          color: AppColors.outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add_service_fab'),
        onPressed: isKycApproved
            ? () => CreateServiceDialog.show(context, ownerId: user.id)
            : null,
        backgroundColor:
            isKycApproved ? AppColors.secondary : AppColors.outline,
        foregroundColor:
            isKycApproved ? AppColors.onSecondary : AppColors.surface,
        tooltip: isKycApproved ? l10n.addService : l10n.kycPending,
        child: const Icon(Icons.add),
      ),
    );
  }
}
