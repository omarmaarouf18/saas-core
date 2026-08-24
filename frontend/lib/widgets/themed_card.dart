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
  final VoidCallback? onTap;
  final Color? topAccentColor;
  final double topAccentHeight;

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
    this.onTap,
    this.topAccentColor,
    this.topAccentHeight = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          );
          break;
        case ThemedCardVariant.normal:
          resolvedBorder = Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
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

    final cardRadius = BorderRadius.circular(
      borderRadius ?? AppRadius.defaultValue,
    );

    Widget innerContent;
    if (topAccentColor != null) {
      innerContent = ClipRRect(
        borderRadius: cardRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: topAccentHeight,
              color: topAccentColor,
            ),
            Padding(
              padding: EdgeInsets.all(padding),
              child: child,
            ),
          ],
        ),
      );
    } else {
      innerContent = Padding(
        padding: EdgeInsets.all(padding),
        child: child,
      );
    }

    final cardContent = Container(
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: cardRadius,
        border: resolvedBorder,
        boxShadow: resolvedShadow,
      ),
      child: innerContent,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: cardRadius,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}
