import 'package:flutter/material.dart';
import '../core/theme.dart';

class ThemedCard extends StatelessWidget {
  final Widget child;
  final double? borderRadius;
  final double padding;
  final bool hasShadow;
  final Color? color;
  final BorderSide? borderSide;

  const ThemedCard({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding = AppSpacing.md,
    this.hasShadow = true,
    this.color,
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(
          borderRadius ?? AppRadius.defaultValue,
        ),
        border: borderSide != null
            ? Border.fromBorderSide(borderSide!)
            : Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
        boxShadow: hasShadow ? [AppShadows.level1] : null,
      ),
      child: child,
    );
  }
}
