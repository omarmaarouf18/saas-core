import 'package:flutter/material.dart';
import '../core/theme.dart';

class PrimaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final int maxLines;
  final DateTime Function()? nowProvider;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
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
    final Widget buttonChild = widget.isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20),
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
                    style: AppTypography.titleMd.copyWith(
                      color: AppColors.onPrimary,
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
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isEnabled ? _handleTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.defaultBorder,
              ),
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
                horizontal: AppSpacing.md,
              ),
            ),
            child: buttonChild,
          ),
        ),
      ),
    );
  }
}
