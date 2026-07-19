import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        stars.add(Icon(Icons.star, color: colorScheme.secondary, size: 20));
      } else if (i == fullStars + 1 && hasHalfStar) {
        stars
            .add(Icon(Icons.star_half, color: colorScheme.secondary, size: 20));
      } else {
        stars.add(const Icon(Icons.star_border, color: Colors.grey, size: 20));
      }
    }

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                averageRating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: stars),
                  const SizedBox(height: 2),
                  Text(
                    'Verified Service Score',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: colorScheme.outline.withOpacity(0.2),
          ),
          const SizedBox(height: 10),
          Text(
            'Based on $ratingCount ratings',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
