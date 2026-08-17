import 'package:flutter/material.dart';
import '../core/theme.dart';

class PrimaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDestructive;
  final bool isFullWidth;
  final double? height;
  final IconData? icon;
  final int maxLines;
  final DateTime Function()? nowProvider;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDestructive = false,
    this.isFullWidth = true,
    this.height = 52,
    this.icon,
    this.maxLines = 2,
    this.nowProvider,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  DateTime? _lastTapTime;
  bool _isPressed = false;

  void _handleTap() {
    if (widget.onPressed == null) return;
    final now =
        widget.nowProvider != null ? widget.nowProvider!() : DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < AppMotion.debounceGuard) {
      return;
    }
    _lastTapTime = now;
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor =
        widget.isDestructive ? AppColors.error : AppColors.secondary;
    final Color textColor =
        widget.isDestructive ? AppColors.onPrimary : AppColors.onSecondary;

    final Widget buttonChild = widget.isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(textColor),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize:
                widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20, color: textColor),
                const SizedBox(width: AppSpacing.base),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    widget.text,
                    overflow: TextOverflow.ellipsis,
                    maxLines: widget.maxLines,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLg.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );

    final bool isEnabled = !widget.isLoading && widget.onPressed != null;

    return Listener(
      onPointerDown: (_) {
        if (isEnabled) {
          setState(() => _isPressed = true);
        }
      },
      onPointerUp: (_) {
        if (_isPressed) {
          setState(() => _isPressed = false);
        }
      },
      onPointerCancel: (_) {
        if (_isPressed) {
          setState(() => _isPressed = false);
        }
      },
      child: AnimatedScale(
        scale: (_isPressed && isEnabled) ? 0.96 : 1.0,
        duration: AppMotion.durationFast,
        curve: AppMotion.curveStateChange,
        child: SizedBox(
          width: widget.isFullWidth ? double.infinity : null,
          height: widget.height,
          child: ElevatedButton(
            onPressed: isEnabled ? _handleTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: textColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.defaultBorder,
              ),
              padding: EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
                horizontal: widget.isFullWidth ? AppSpacing.md : AppSpacing.lg,
              ),
            ),
            child: buttonChild,
          ),
        ),
      ),
    );
  }
}
