import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
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
    final ownerProvider = Provider.of<OwnerProvider>(context);
    final currentTier = ownerProvider.subscriptionTier;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Plans'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Plan Header Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR CURRENT PLAN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer.withOpacity(0.7),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          currentTier.toUpperCase().replaceAll('_', ' '),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        Icon(
                          currentTier == 'free'
                              ? Icons.star_border
                              : Icons.stars,
                          color: colorScheme.secondary,
                          size: 32,
                        ),
                      ],
                    ),
                    if (currentTier == 'pending_payment') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: colorScheme.onErrorContainer, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pending activation. Please contact support to complete payment.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onErrorContainer,
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
            ),
            const SizedBox(height: 24),

            Text(
              'Available Plans',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),

            // Plan 1: Free Tier Card
            _buildPlanCard(
              title: 'Free Basic Plan',
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
              colorScheme: colorScheme,
              theme: theme,
            ),
            const SizedBox(height: 20),

            // Plan 2: Professional Paid Tier Card
            _buildPlanCard(
              title: 'Professional Paid Plan',
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
              colorScheme: colorScheme,
              theme: theme,
              highlighted: true,
            ),
            const SizedBox(height: 24),
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
    required ColorScheme colorScheme,
    required ThemeData theme,
    bool highlighted = false,
  }) {
    return Card(
      elevation: highlighted ? 6 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlighted
              ? colorScheme.secondary
              : colorScheme.outline.withOpacity(0.2),
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (highlighted) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.secondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'RECOMMENDED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: highlighted
                        ? colorScheme.secondary
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/ $billing',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 20,
                        color:
                            highlighted ? colorScheme.secondary : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: isCurrent
                    ? Colors.grey
                    : (highlighted
                        ? colorScheme.secondary
                        : colorScheme.primary),
                foregroundColor: isCurrent
                    ? Colors.white
                    : (highlighted
                        ? colorScheme.onSecondary
                        : colorScheme.onPrimary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
