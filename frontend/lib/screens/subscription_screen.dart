import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/app_shell.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_success_banner.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isSubmitting = false;

  Future<void> _changeSubscription(String tier) async {
    setState(() {
      _isSubmitting = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);

    try {
      final res = await ownerProvider.updateSubscription(
        tenantId: auth.token!,
        tier: tier,
      );

      if (mounted) {
        String msg = "Subscription updated successfully!";
        if (res.containsKey('message')) {
          msg = res['message'] as String;
        }
        ThemedSnackBar.showSuccess(context, msg);
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ThemedSnackBar.showError(
          context,
          l10n.ratingFailed(e.toString()),
          onRetry: () => _changeSubscription(tier),
        );
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
    final l10n = AppLocalizations.of(context)!;
    final ownerProvider = Provider.of<OwnerProvider>(context);
    final currentTier = ownerProvider.subscriptionTier;

    return AppShell(
      title: l10n.subscriptionPlansTitle,
      backgroundColor: AppColors.background,
      appBarBackgroundColor: AppColors.primary,
      appBarForegroundColor: AppColors.onPrimary,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.marginMobile,
          vertical: AppSpacing.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Centered Hero Header (Stitch Header)
                Center(
                  child: Column(
                    children: [
                      Text(
                        l10n.subscriptionPlansTitle,
                        style: AppTypography.headlineLgMobile.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        "Manage your operational tier. Upgrade to unlock live driver tracking, advanced pricing metrics, and priority enterprise support.",
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 2. Current Plan Status Header Card
                ThemedCard(
                  borderRadius: AppRadius.lg,
                  padding: AppSpacing.lg,
                  color: AppColors.primaryContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'YOUR CURRENT PLAN',
                            style: AppTypography.labelLg.copyWith(
                              color: AppColors.onPrimary.withValues(alpha: 0.7),
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ThemedPanel(
                              color: currentTier == 'free'
                                  ? AppColors.surfaceContainerHigh
                                      .withValues(alpha: 0.3)
                                  : AppColors.secondary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(AppRadius.xl),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    currentTier == 'free'
                                        ? Icons.star_border
                                        : Icons.stars,
                                    color: currentTier == 'free'
                                        ? AppColors.onPrimary
                                        : AppColors.secondary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    currentTier == 'free' ? 'BASIC' : 'PRO',
                                    style: AppTypography.labelSm.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: currentTier == 'free'
                                          ? AppColors.onPrimary
                                          : AppColors.secondary,
                                    ),
                                  ),
                                ],
                              )),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        AppTypography.uppercaseLabel(currentTier)
                            .replaceAll('_', ' '),
                        style: AppTypography.headlineLgMobile.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      if (currentTier == 'pending_payment') ...[
                        const SizedBox(height: AppSpacing.md),
                        const ThemedWarningBanner(
                          message:
                              'Pending activation. Please contact support to complete payment.',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 3. Section Title
                Text(
                  'Available Plans',
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // 4. Responsive Pricing Cards (Stitch 2-Card Grid)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 700;
                    if (isDesktop) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _buildStandardPlanCard(
                                l10n: l10n,
                                currentTier: currentTier,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(
                              child: _buildEnterprisePlanCard(
                                l10n: l10n,
                                currentTier: currentTier,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: [
                        _buildStandardPlanCard(
                          l10n: l10n,
                          currentTier: currentTier,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildEnterprisePlanCard(
                          l10n: l10n,
                          currentTier: currentTier,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Plan Card 1: Standard (Free Tier) ---
  Widget _buildStandardPlanCard({
    required AppLocalizations l10n,
    required String currentTier,
  }) {
    final bool isCurrent = currentTier == 'free';
    final bool isThisPlanLoading = _isSubmitting && !isCurrent;

    return ThemedCard(
      variant: ThemedCardVariant.normal,
      borderRadius: AppRadius.lg,
      padding: AppSpacing.lg,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.planFreeBasic,
                style: AppTypography.titleMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                "Essential tools for independent operators.",
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '\$0',
                    style: AppTypography.headlineLg.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '/ forever',
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1, color: AppColors.outlineVariant),
              const SizedBox(height: AppSpacing.md),
              _buildFeatureRow(
                icon: Icons.check_circle,
                iconColor: AppColors.primary,
                text: "Basic delivery matching",
                isEnabled: true,
              ),
              _buildFeatureRow(
                icon: Icons.check_circle,
                iconColor: AppColors.primary,
                text: "Standard routing optimization",
                isEnabled: true,
              ),
              _buildFeatureRow(
                icon: Icons.check_circle,
                iconColor: AppColors.primary,
                text: "Cash on Delivery (COD) bookings",
                isEnabled: true,
              ),
              _buildFeatureRow(
                icon: Icons.check_circle,
                iconColor: AppColors.primary,
                text: "Community support",
                isEnabled: true,
              ),
              _buildFeatureRow(
                icon: Icons.cancel_outlined,
                iconColor: AppColors.outlineVariant,
                text: "Live worker location tracking",
                isEnabled: false,
              ),
              _buildFeatureRow(
                icon: Icons.cancel_outlined,
                iconColor: AppColors.outlineVariant,
                text: "Priority dispatch routing",
                isEnabled: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            text: isCurrent ? 'Active Plan' : 'Downgrade to Free',
            isOutlined: true,
            onPressed: isCurrent || _isSubmitting
                ? null
                : () => _changeSubscription('free'),
            isLoading: isThisPlanLoading,
          ),
        ],
      ),
    );
  }

  // --- Plan Card 2: Enterprise Pro (Paid Tier) ---
  Widget _buildEnterprisePlanCard({
    required AppLocalizations l10n,
    required String currentTier,
  }) {
    final bool isCurrent =
        currentTier == 'paid' || currentTier == 'pending_payment';
    final bool isThisPlanLoading = _isSubmitting && !isCurrent;

    return Stack(
      children: [
        ThemedCard(
          variant: ThemedCardVariant.highlighted,
          borderRadius: AppRadius.lg,
          padding: AppSpacing.lg,
          color: AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.planProfessionalPaid,
                          style: AppTypography.titleMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(
                        Icons.stars,
                        color: AppColors.secondary,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    "Complete suite for fleet managers and growing businesses.",
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '\$19.99',
                        style: AppTypography.headlineLg.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '/ month',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1, color: AppColors.outlineVariant),
                  const SizedBox(height: AppSpacing.md),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: "Unlocks live worker location tracking",
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: "Priority dispatch routing",
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: "Access to advanced pricing metrics",
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: "Full employee management suite",
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: "Premium 24/7 dedicated support",
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Column(
                children: [
                  PrimaryButton(
                    text: currentTier == 'paid'
                        ? 'Active Plan'
                        : (currentTier == 'pending_payment'
                            ? 'Awaiting Payment'
                            : 'Upgrade to Professional'),
                    trailingIcon: Icons.arrow_forward,
                    onPressed: isCurrent || _isSubmitting
                        ? null
                        : () => _changeSubscription('paid'),
                    isLoading: isThisPlanLoading,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "Billed monthly. Cancel anytime.",
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ],
          ),
        ),
        // Positioned Top-Right "RECOMMENDED" Badge
        PositionedDirectional(
          top: 0,
          end: 0,
          child: ThemedPanel(
              color: AppColors.secondary,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.baseSm,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                'RECOMMENDED',
                style: AppTypography.labelMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSecondary,
                  letterSpacing: 0.5,
                ),
              )),
        ),
      ],
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required Color iconColor,
    required String text,
    required bool isEnabled,
    bool isHighlighted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: iconColor,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyMd.copyWith(
                color: isEnabled
                    ? (isHighlighted ? AppColors.primary : AppColors.onSurface)
                    : AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
