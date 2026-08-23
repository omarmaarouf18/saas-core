import 'package:flutter/material.dart';
import '../core/error_messages.dart';
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
    final l10n = context.l10n;

    try {
      final res = await ownerProvider.updateSubscription(
        tenantId: auth.token!,
        tier: tier,
      );

      if (mounted) {
        String msg = l10n.subscriptionUpdatedSuccessMsg;
        if (res.containsKey('message')) {
          msg = res['message'] as String;
        }
        ThemedSnackBar.showSuccess(context, msg);
      }
    } catch (e) {
      if (mounted) {
        ThemedSnackBar.showError(
          context,
          // A5: was l10n.ratingFailed(e.toString()) — copy-pasted rating key that
          // rendered a raw exception dump on a money flow.
          friendlyErrorMessage(e),
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
                        l10n.subscriptionManageDesc,
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
                            l10n.yourCurrentPlanBadge,
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
                                  const SizedBox(width: AppSpacing.xs),
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
                        ThemedWarningBanner(
                          message: l10n.pendingActivationNote,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 3. Section Title
                Text(
                  l10n.availablePlansHeader,
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
                l10n.freeTierDesc,
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
                text: l10n.subFreeFeatureMatching,
                isEnabled: true,
              ),
              _buildFeatureRow(
                icon: Icons.check_circle,
                iconColor: AppColors.primary,
                text: l10n.subFreeFeatureRouting,
                isEnabled: true,
              ),
              _buildFeatureRow(
                icon: Icons.check_circle,
                iconColor: AppColors.primary,
                text: l10n.subFreeFeatureCod,
                isEnabled: true,
              ),
              _buildFeatureRow(
                icon: Icons.check_circle,
                iconColor: AppColors.primary,
                text: l10n.subFreeFeatureSupport,
                isEnabled: true,
              ),
              _buildFeatureRow(
                icon: Icons.cancel_outlined,
                iconColor: AppColors.outlineVariant,
                text: l10n.subProFeatureTracking,
                isEnabled: false,
              ),
              _buildFeatureRow(
                icon: Icons.cancel_outlined,
                iconColor: AppColors.outlineVariant,
                text: l10n.subProFeatureDispatch,
                isEnabled: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            text: isCurrent ? l10n.activePlanLabel : l10n.downgradeToFreeBtn,
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
                    l10n.proTierDesc,
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
                    text: l10n.subProFeatureTrackingUnlock,
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: l10n.subProFeatureDispatch,
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: l10n.subProFeaturePricing,
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: l10n.subProEmployeeSuite,
                    isEnabled: true,
                    isHighlighted: true,
                  ),
                  _buildFeatureRow(
                    icon: Icons.check_circle,
                    iconColor: AppColors.secondary,
                    text: l10n.subProDedicatedSupport,
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
                        ? l10n.activePlanLabel
                        : (currentTier == 'pending_payment'
                            ? l10n.awaitingPaymentLabel
                            : l10n.upgradeToProfessionalBtn),
                    trailingIcon: Icons.arrow_forward,
                    onPressed: isCurrent || _isSubmitting
                        ? null
                        : () => _changeSubscription('paid'),
                    isLoading: isThisPlanLoading,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.billedMonthlyNote,
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
                l10n.recommendedBadge,
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
