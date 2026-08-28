import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'themed_card.dart';

class InfoListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final IconData? leadingIcon;
  final Color? leadingIconColor;
  final Color? leadingBackgroundColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double padding;
  final Color? backgroundColor;
  final bool hasShadow;
  final BorderSide? borderSide;

  const InfoListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.leadingIcon,
    this.leadingIconColor,
    this.leadingBackgroundColor,
    this.trailing,
    this.onTap,
    this.padding = AppSpacing.md,
    this.backgroundColor,
    this.hasShadow = false,
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    Widget? leadingWidget = leading;
    if (leadingWidget == null && leadingIcon != null) {
      final iconColor =
          leadingIconColor ?? Theme.of(context).colorScheme.primary;
      final bgColor =
          leadingBackgroundColor ?? iconColor.withValues(alpha: 0.1);
      leadingWidget = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppRadius.mdBorder,
        ),
        child: Icon(
          leadingIcon,
          color: iconColor,
          size: 20,
        ),
      );
    }

    final tileContent = Row(
      children: [
        if (leadingWidget != null) ...[
          leadingWidget,
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppTypography.titleMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (subtitleWidget != null) ...[
                const SizedBox(height: AppSpacing.xs),
                subtitleWidget!,
              ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: AppTypography.bodyMd.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );

    return ThemedCard(
      padding: padding,
      color: backgroundColor,
      hasShadow: hasShadow,
      borderSide: borderSide,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: AppRadius.defaultBorder,
              child: tileContent,
            )
          : tileContent,
    );
  }
}
