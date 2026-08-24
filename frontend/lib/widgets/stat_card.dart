import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'themed_card.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final String? trend;
  final bool? isPositiveTrend;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.trend,
    this.isPositiveTrend,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        iconColor ?? Theme.of(context).colorScheme.primary;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                icon,
                color: effectiveIconColor,
                size: AppIconSize.md,
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          value,
          style: AppTypography.headlineLgMobile.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (trend != null && trend!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPositiveTrend != null)
                Icon(
                  isPositiveTrend! ? Icons.trending_up : Icons.trending_down,
                  size: AppIconSize.xs,
                  color: isPositiveTrend!
                      ? context.semanticColors.success
                      : AppColors.error,
                ),
              if (isPositiveTrend != null) const SizedBox(width: AppSpacing.xs),
              Text(
                trend!,
                style: AppTypography.labelMd.copyWith(
                  color: isPositiveTrend == null
                      ? AppColors.outline
                      : (isPositiveTrend!
                          ? context.semanticColors.success
                          : AppColors.error),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return ThemedCard(
      borderRadius: AppRadius.md,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: AppRadius.mdBorder,
              child: content,
            )
          : content,
    );
  }
}
