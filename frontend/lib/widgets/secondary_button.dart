import 'package:flutter/material.dart';
import '../core/theme.dart';

class SecondaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final bool isDestructive;
  final bool isFullWidth;
  final double? height;
  final IconData? icon;
  final int maxLines;
  final DateTime Function()? nowProvider;

  const SecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.isDestructive = false,
    this.isFullWidth = true,
    this.height = 52,
    this.icon,
    this.maxLines = 2,
    this.nowProvider,
  });

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> {
  DateTime? _lastTapTime;
  bool _isPressed = false;
  bool _busy = false;

  Future<void> _handleTap() async {
    if (widget.onPressed == null || _busy) return;
    final now =
        widget.nowProvider != null ? widget.nowProvider!() : DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < AppMotion.debounceGuard) {
      return;
    }
    _lastTapTime = now;
    // VoidCallback's static return type is `void`; dispatching through a
    // dynamic binding lets us observe whether the closure actually returned
    // a Future (i.e. is async) without widening the public widget API.
    final dynamic result = (widget.onPressed as dynamic)();
    // In-flight double-submit guard (QA audit A4): when the handler is
    // asynchronous, ignore further taps until it completes. The timestamp
    // debounce above only blocks taps within 600ms; network calls routinely
    // outlive that window, so a second "nothing happened" tap must be
    // blocked by completion tracking instead.
    if (result is Future) {
      _busy = true;
      try {
        await result;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Brightness-aware roles: in dark mode the scheme resolves to the
    // high-contrast variants (gold accent / light red) — the static
    // light-tuned constants are invisible on dark surfaces.
    final scheme = Theme.of(context).colorScheme;
    final Color buttonColor = widget.isDestructive
        ? scheme.error
        : (widget.isOutlined ? scheme.primary : AppColors.onSecondary);

    final Widget buttonChild = widget.isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(buttonColor),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize:
                widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 20,
                  color: buttonColor,
                ),
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
                      color: buttonColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );

    final style = widget.isOutlined
        ? OutlinedButton.styleFrom(
            foregroundColor: buttonColor,
            side: BorderSide(color: buttonColor, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.defaultBorder,
            ),
            padding: EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: widget.isFullWidth ? AppSpacing.md : AppSpacing.lg,
            ),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: widget.isDestructive
                ? scheme.error.withValues(alpha: 0.12)
                : AppColors.secondary,
            foregroundColor: buttonColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.defaultBorder,
            ),
            padding: EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: widget.isFullWidth ? AppSpacing.md : AppSpacing.lg,
            ),
          );

    final bool isEnabled =
        !widget.isLoading && !_busy && widget.onPressed != null;
    final VoidCallback? effectiveOnPressed = isEnabled ? _handleTap : null;

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
        ),
      ),
    );
  }
}
