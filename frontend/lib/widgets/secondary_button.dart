import 'package:flutter/material.dart';
import '../core/theme.dart';

class SecondaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final IconData? icon;
  final DateTime Function()? nowProvider;

  const SecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
    this.nowProvider,
  });

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> {
  DateTime? _lastTapTime;

  void _handleTap() {
    if (widget.onPressed == null) return;
    final now =
        widget.nowProvider != null ? widget.nowProvider!() : DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastTapTime = now;
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final Widget buttonChild = widget.isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.isOutlined ? AppColors.primary : AppColors.onSecondary,
              ),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 20,
                  color: widget.isOutlined
                      ? AppColors.primary
                      : AppColors.onSecondary,
                ),
                const SizedBox(width: AppSpacing.base),
              ],
              Flexible(
                child: Text(
                  widget.text,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMd.copyWith(
                    color: widget.isOutlined
                        ? AppColors.primary
                        : AppColors.onSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );

    final style = widget.isOutlined
        ? OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.defaultBorder,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.md,
            ),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: AppColors.onSecondary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.defaultBorder,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.md,
            ),
          );

    final VoidCallback? effectiveOnPressed =
        (widget.isLoading || widget.onPressed == null) ? null : _handleTap;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: widget.isOutlined
          ? OutlinedButton(
              onPressed: effectiveOnPressed,
              style: style,
              child: buttonChild,
            )
          : ElevatedButton(
              onPressed: effectiveOnPressed,
              style: style,
              child: buttonChild,
            ),
    );
  }
}
