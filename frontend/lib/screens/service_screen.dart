import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/app_shell.dart';
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
        return Icons.storefront_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final owner = Provider.of<OwnerProvider>(context);
    final user = auth.user;
    final l10n = AppLocalizations.of(context)!;

    if (user == null) {
      return AppShell(
        body: Center(
          child: Text(l10n.unauthenticatedMsg),
        ),
      );
    }

    final isKycApproved = user.kycStatus == "approved";
    final myServices =
        owner.services.where((s) => s['tenant_id'] == user.id).toList();

    return AppShell(
      title: l10n.ownerConfigTitle,
      backgroundColor: AppColors.scaffoldBackground,
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
                    // Header Section
                    _buildHeader(),
                    const SizedBox(height: AppSpacing.lg),

                    // KYC Verification Guard Banner
                    if (!isKycApproved) ...[
                      _buildKycBanner(),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Services List / Empty State
                    if (myServices.isEmpty)
                      _buildEmptyState(user, l10n)
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: myServices.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, index) {
                          return _buildServiceCard(
                            myServices[index],
                            isKycApproved: isKycApproved,
                            userId: user.id,
                            l10n: l10n,
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

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.serviceMgmtHeader,
          style: AppTypography.headlineLgMobile.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          context.l10n.serviceMgmtSubtitle,
          style: AppTypography.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildKycBanner() {
    return ThemedPanel(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
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
                    context.l10n.verificationRequiredHeader,
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    context.l10n.kycRequiredDesc,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ));
  }

  Widget _buildEmptyState(dynamic user, AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: ThemedEmptyState(
        icon: Icons.design_services_outlined,
        title: l10n.noServicesConfigured,
        description: l10n.noServicesDescription,
        actionText: l10n.createServiceAction,
        onActionPressed: () => CreateServiceDialog.show(
          context,
          ownerId: user.id,
        ),
      ),
    );
  }

  Widget _buildServiceCard(
    Map<String, dynamic> svc, {
    required bool isKycApproved,
    required String userId,
    required AppLocalizations l10n,
  }) {
    final category = svc['category']?.toString();
    final categoryLabel = serviceCategoryLabels[category] ??
        category ??
        l10n.serviceFallbackLabel;
    final basePrice = (svc['tenant_base_price'] as num?)?.toDouble() ?? 0.0;
    final pricePerKm = (svc['tenant_price_per_km'] as num?)?.toDouble() ?? 0.0;
    final lat = (svc['latitude'] as num?)?.toDouble();
    final lon = (svc['longitude'] as num?)?.toDouble();
    final name = svc['name']?.toString() ?? l10n.userProfileTitle;

    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Category Icon, Name, Active status dot
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  width: 42,
                  height: 42,
                  child: Center(
                    child: Icon(
                      _getCategoryIcon(category),
                      color: AppColors.secondary,
                      size: 22,
                    ),
                  )),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        const ThemedPanel(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            width: 8,
                            height: 8),
                        const SizedBox(width: AppSpacing.baseSm),
                        Text(
                          AppTypography.uppercaseLabel(categoryLabel),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
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

          // Rates Box (Base Rate + Per KM)
          ThemedPanel(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.baseRateBadge,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        "\$${basePrice.toStringAsFixed(2)}",
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    height: 28,
                    width: 1,
                    color: AppColors.outlineVariant.withValues(alpha: 0.4),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.perKmBadge,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        "\$${pricePerKm.toStringAsFixed(2)}",
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              )),

          // Location coordinates if present
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
                  context.l10n.serviceLocationLine(
                      lat.toStringAsFixed(4), lon.toStringAsFixed(4)),
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
  }
}
