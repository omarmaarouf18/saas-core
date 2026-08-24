import 'package:flutter/material.dart';
import '../core/theme.dart';

class RouteTimeline extends StatelessWidget {
  final String pickupAddress;
  final String? pickupDetail;
  final String dropoffAddress;
  final String? dropoffDetail;
  final String? distanceText;
  final String? timeText;
  final String? cargoText;
  final Widget? pickupTrailing;
  final Widget? dropoffTrailing;

  const RouteTimeline({
    super.key,
    required this.pickupAddress,
    this.pickupDetail,
    required this.dropoffAddress,
    this.dropoffDetail,
    this.distanceText,
    this.timeText,
    this.cargoText,
    this.pickupTrailing,
    this.dropoffTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 2-Point Vertical Connector
        Stack(
          children: [
            // Vertical Line
            PositionedDirectional(
              start: 11,
              top: 16,
              bottom: 16,
              child: Container(
                width: 2,
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pickup Node
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: AppSpacing.xxs),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pickupAddress,
                            style: AppTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          if (pickupDetail != null &&
                              pickupDetail!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              pickupDetail!,
                              style: AppTypography.labelSm.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (pickupTrailing != null) pickupTrailing!,
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Dropoff Node
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: AppSpacing.xxs),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: context.semanticColors.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dropoffAddress,
                            style: AppTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          if (dropoffDetail != null &&
                              dropoffDetail!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              dropoffDetail!,
                              style: AppTypography.labelSm.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (dropoffTrailing != null) dropoffTrailing!,
                  ],
                ),
              ],
            ),
          ],
        ),

        // Optional Metrics Row
        if (distanceText != null || timeText != null || cargoText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xs,
              horizontal: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (distanceText != null)
                  _buildMetricItem(
                    context: context,
                    icon: Icons.route,
                    label: distanceText!,
                  ),
                if (distanceText != null && timeText != null) _buildDivider(),
                if (timeText != null)
                  _buildMetricItem(
                    context: context,
                    icon: Icons.schedule,
                    label: timeText!,
                  ),
                if (timeText != null && cargoText != null) _buildDivider(),
                if (cargoText != null)
                  _buildMetricItem(
                    context: context,
                    icon: Icons.inventory_2_outlined,
                    label: cargoText!,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricItem(
      {required BuildContext context,
      required IconData icon,
      required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: AppIconSize.sm,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.labelSm.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 14,
      color: AppColors.outlineVariant.withValues(alpha: 0.5),
    );
  }
}
