import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.ratingFailed(e.toString())),
            backgroundColor: AppColors.error,
          ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.subscriptionPlansTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Plan Header Card
            ThemedCard(
              borderRadius: AppRadius.lg,
              padding: AppSpacing.lg,
              color: AppColors.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR CURRENT PLAN',
                    style: AppTypography.labelLg.copyWith(
                      color: AppColors.onPrimary.withValues(alpha: 0.7),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currentTier.toUpperCase().replaceAll('_', ' '),
                        style: AppTypography.headlineLgMobile.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      Icon(
                        currentTier == 'free' ? Icons.star_border : Icons.stars,
                        color: AppColors.secondary,
                        size: 32,
                      ),
                    ],
                  ),
                  if (currentTier == 'pending_payment') ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.base),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(
                            child: Text(
                              'Pending activation. Please contact support to complete payment.',
                              style: AppTypography.bodyMd.copyWith(
                                fontSize: 12,
                                color: AppColors.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Text(
              'Available Plans',
              style: AppTypography.headlineLgMobile.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Plan 1: Free Tier Card
            _buildPlanCard(
              title: l10n.planFreeBasic,
              price: '\$0',
              billing: 'forever',
              features: [
                'Basic delivery matching',
                'Standard routing optimization',
                'Cash on Delivery (COD) bookings',
                'Community support',
              ],
              isCurrent: currentTier == 'free',
              onPressed: _isSubmitting || currentTier == 'free'
                  ? null
                  : () => _changeSubscription('free'),
              buttonText:
                  currentTier == 'free' ? 'Active Plan' : 'Downgrade to Free',
            ),
            const SizedBox(height: AppSpacing.lg),

            // Plan 2: Professional Paid Tier Card
            _buildPlanCard(
              title: l10n.planProfessionalPaid,
              price: '\$19.99',
              billing: 'per month',
              features: [
                'Unlocks live worker location tracking',
                'Priority dispatch routing',
                'Access to advanced pricing metrics',
                'Premium 24/7 dedicated support',
              ],
              isCurrent:
                  currentTier == 'paid' || currentTier == 'pending_payment',
              onPressed: _isSubmitting ||
                      currentTier == 'paid' ||
                      currentTier == 'pending_payment'
                  ? null
                  : () => _changeSubscription('paid'),
              buttonText: currentTier == 'paid'
                  ? 'Active Plan'
                  : (currentTier == 'pending_payment'
                      ? 'Awaiting Payment'
                      : 'Upgrade to Professional'),
              highlighted: true,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String price,
    required String billing,
    required List<String> features,
    required bool isCurrent,
    required VoidCallback? onPressed,
    required String buttonText,
    bool highlighted = false,
  }) {
    final bool isThisPlanLoading = _isSubmitting && !isCurrent;

    return ThemedCard(
      hasShadow: true,
      color: AppColors.surface,
      borderRadius: AppRadius.lg,
      padding: AppSpacing.lg,
      borderSide: BorderSide(
        color: highlighted
            ? AppColors.secondary
            : AppColors.outlineVariant.withValues(alpha: 0.3),
        width: highlighted ? 2 : 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.baseSm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Text(
                  'RECOMMENDED',
                  style: AppTypography.labelMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
          ],
          Text(
            title,
            style: AppTypography.titleMd.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price,
                style: AppTypography.displayLg.copyWith(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color:
                      highlighted ? AppColors.secondary : AppColors.onSurface,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '/ $billing',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
          Divider(
            height: AppSpacing.xl,
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.base),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color:
                          highlighted ? AppColors.secondary : AppColors.outline,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        f,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: AppSpacing.lg),
          highlighted
              ? SecondaryButton(
                  text: buttonText,
                  onPressed: onPressed,
                  isLoading: isThisPlanLoading,
                )
              : PrimaryButton(
                  text: buttonText,
                  onPressed: onPressed,
                  isLoading: isThisPlanLoading,
                ),
        ],
      ),
    );
  }
}
