import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../core/theme.dart';
import 'themed_card.dart';

class RatingSummaryCard extends StatelessWidget {
  final double averageRating;
  final int ratingCount;

  const RatingSummaryCard({
    super.key,
    required this.averageRating,
    required this.ratingCount,
  });

  @override
  Widget build(BuildContext context) {
    // Generate stars list
    List<Widget> stars = [];
    int fullStars = averageRating.floor();
    bool hasHalfStar = (averageRating - fullStars) >= 0.25 &&
        (averageRating - fullStars) < 0.75;
    if ((averageRating - fullStars) >= 0.75) {
      fullStars++;
    }

    for (int i = 1; i <= 5; i++) {
      if (i <= fullStars) {
        stars.add(const Icon(Icons.star,
            color: AppColors.secondary, size: AppIconSize.md));
      } else if (i == fullStars + 1 && hasHalfStar) {
        stars.add(const Icon(Icons.star_half,
            color: AppColors.secondary, size: AppIconSize.md));
      } else {
        stars.add(const Icon(Icons.star_border,
            color: AppColors.outlineVariant, size: AppIconSize.md));
      }
    }

    return ThemedCard(
      hasShadow: false,
      color: AppColors.surfaceContainerLow,
      borderRadius: AppRadius.md,
      padding: AppSpacing.md,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                averageRating.toStringAsFixed(1),
                style: AppTypography.headlineLg.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: stars),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    AppLocalizations.of(context)?.verifiedServiceScoreLabel ??
                        'Verified Service Score',
                    style: AppTypography.labelMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.baseSm),
          Divider(
            height: 1,
            color: AppColors.outlineVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: AppSpacing.baseSm),
          Text(
            AppLocalizations.of(context)?.basedOnRatingsLine("$ratingCount") ??
                'Based on $ratingCount ratings',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
