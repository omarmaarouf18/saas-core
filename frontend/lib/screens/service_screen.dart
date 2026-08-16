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
import '../widgets/themed_error_banner.dart';
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
            : Column(
                children: [
                  if (!isKycApproved)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: ThemedErrorBanner(
                        message:
                            "KYC Approval Pending: You cannot publish new services until your profile is approved by an administrator.",
                        onRetry: _loadServices,
                      ),
                    ),
                  Expanded(
                    child: myServices.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: AppSpacing.xxxl),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg),
                                child: ThemedCard(
                                  borderRadius: AppRadius.md,
                                  padding: AppSpacing.lg,
                                  child: ThemedEmptyState(
                                    icon: Icons.design_services_outlined,
                                    title: l10n.noServicesConfigured,
                                    description: l10n.noServicesDescription,
                                    actionText: "Create Service",
                                    onActionPressed: () =>
                                        CreateServiceDialog.show(
                                      context,
                                      ownerId: user.id,
                                    ),
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
                                            padding: const EdgeInsetsDirectional
                                                .symmetric(
                                              horizontal: AppSpacing.baseSm,
                                              vertical: AppSpacing.xs,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppRadius.radiusLgXl),
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
                                        "📍 Service Location",
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
