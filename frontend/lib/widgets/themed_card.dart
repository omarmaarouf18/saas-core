import 'package:flutter/material.dart';
import '../core/theme.dart';

enum ThemedCardVariant {
  normal,
  highlighted,
  elevated,
}

class ThemedCard extends StatelessWidget {
  final Widget child;
  final ThemedCardVariant variant;
  final double? borderRadius;
  final double padding;
  final bool hasShadow;
  final List<BoxShadow>? elevation;
  final Color? color;
  final BorderSide? borderSide;

  const ThemedCard({
    super.key,
    required this.child,
    this.variant = ThemedCardVariant.normal,
    this.borderRadius,
    this.padding = AppSpacing.md,
    this.hasShadow = true,
    this.elevation,
    this.color,
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    // Resolve border based on borderSide override or card variant
    final Border resolvedBorder;
    if (borderSide != null) {
      resolvedBorder = Border.fromBorderSide(borderSide!);
    } else {
      switch (variant) {
        case ThemedCardVariant.highlighted:
          resolvedBorder = Border.all(
            color: AppColors.secondary,
            width: 2,
          );
          break;
        case ThemedCardVariant.elevated:
          resolvedBorder = Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          );
          break;
        case ThemedCardVariant.normal:
          resolvedBorder = Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          );
          break;
      }
    }

    // Resolve shadow based on elevation override, variant, or hasShadow
    final List<BoxShadow>? resolvedShadow;
    if (elevation != null) {
      resolvedShadow = elevation;
    } else if (!hasShadow) {
      resolvedShadow = null;
    } else {
      switch (variant) {
        case ThemedCardVariant.highlighted:
          resolvedShadow = AppElevation.shadowLevel2List;
          break;
        case ThemedCardVariant.elevated:
          resolvedShadow = AppElevation.shadowLevel3List;
          break;
        case ThemedCardVariant.normal:
          resolvedShadow = AppElevation.shadowLevel1List;
          break;
      }
    }

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(
          borderRadius ?? AppRadius.defaultValue,
        ),
        border: resolvedBorder,
        boxShadow: resolvedShadow,
      ),
      child: child,
    );
  }
}
