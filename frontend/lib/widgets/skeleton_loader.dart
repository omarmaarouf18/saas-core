import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Reusable shimmer-animated skeleton loader box for performance perception.
class SkeletonLoader extends StatefulWidget {
  final double? width;
  final double? height;
  final double? borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonLoader({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.margin,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.durationSlow,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shimmerValue = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              widget.borderRadius ?? AppRadius.sm,
            ),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + (3.0 * shimmerValue), -0.5),
              end: Alignment(-0.5 + (3.0 * shimmerValue), 0.5),
              colors: [
                AppColors.outlineVariant.withValues(alpha: 0.15),
                AppColors.outlineVariant.withValues(alpha: 0.35),
                AppColors.outlineVariant.withValues(alpha: 0.15),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton loader for Marketplace Service Cards
class MarketplaceCardSkeleton extends StatelessWidget {
  const MarketplaceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: const [AppElevation.shadowLevel1],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLoader(width: 40, height: 40, borderRadius: AppRadius.full),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(
                    width: 140, height: 18, borderRadius: AppRadius.xs),
                SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    SkeletonLoader(
                        width: 60, height: 14, borderRadius: AppRadius.xs),
                    SizedBox(width: AppSpacing.sm),
                    SkeletonLoader(
                        width: 80, height: 14, borderRadius: AppRadius.xs),
                  ],
                ),
                SizedBox(height: AppSpacing.base),
                SkeletonLoader(
                    width: 180, height: 14, borderRadius: AppRadius.xs),
                SizedBox(height: AppSpacing.xs),
                SkeletonLoader(
                    width: 100, height: 18, borderRadius: AppRadius.xs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton loader for Home Dashboard Metric Stats & Recent Jobs
class HomeDashboardSkeleton extends StatelessWidget {
  const HomeDashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Metric cards grid
        Row(
          children: [
            Expanded(
              child: Container(
                height: 100,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
                  boxShadow: const [AppElevation.shadowLevel1],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonLoader(width: 80, height: 14),
                    SkeletonLoader(width: 110, height: 24),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Container(
                height: 100,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
                  boxShadow: const [AppElevation.shadowLevel1],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonLoader(width: 80, height: 14),
                    SkeletonLoader(width: 110, height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        // Section Header Skeleton
        const SkeletonLoader(width: 160, height: 20),
        const SizedBox(height: AppSpacing.md),
        // Recent jobs list skeleton
        ...List.generate(
          3,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
              boxShadow: const [AppElevation.shadowLevel1],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(width: 130, height: 16),
                    SizedBox(height: AppSpacing.xs),
                    SkeletonLoader(width: 90, height: 12),
                  ],
                ),
                SkeletonLoader(
                    width: 60, height: 22, borderRadius: AppRadius.sm),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Skeleton loader for Employee Jobs Cards
class EmployeeJobCardSkeleton extends StatelessWidget {
  const EmployeeJobCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: const [AppElevation.shadowLevel2],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonLoader(width: 120, height: 18),
              SkeletonLoader(width: 70, height: 22, borderRadius: AppRadius.sm),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          SkeletonLoader(width: 160, height: 14),
          SizedBox(height: AppSpacing.xs),
          SkeletonLoader(width: 200, height: 14),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              SkeletonLoader(
                  width: 100, height: 36, borderRadius: AppRadius.sm),
              SizedBox(width: AppSpacing.md),
              SkeletonLoader(width: 80, height: 36, borderRadius: AppRadius.sm),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton loader for Wallet Overview & Transactions
class WalletScreenSkeleton extends StatelessWidget {
  const WalletScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wallet Balance Cards Row
        Row(
          children: [
            Expanded(
              child: Container(
                height: 110,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
                  boxShadow: const [AppElevation.shadowLevel1],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonLoader(width: 90, height: 14),
                    SkeletonLoader(width: 120, height: 24),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Container(
                height: 110,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
                  boxShadow: const [AppElevation.shadowLevel1],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonLoader(width: 90, height: 14),
                    SkeletonLoader(width: 120, height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        // Section Header Skeleton
        const SkeletonLoader(width: 140, height: 20),
        const SizedBox(height: AppSpacing.sm),
        // Payout / Ledger tiles skeleton list
        ...List.generate(
          3,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.base),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.defaultValue),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                SkeletonLoader(
                    width: 40, height: 40, borderRadius: AppRadius.md),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLoader(width: 120, height: 16),
                      SizedBox(height: AppSpacing.xs),
                      SkeletonLoader(width: 160, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
