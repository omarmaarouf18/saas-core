import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';

enum ThemedBannerType {
  error,
  success,
  warning,
  info,
}

/// Unified, design-system compliant inline banner component.
class ThemedBanner extends StatefulWidget {
  final ThemedBannerType type;
  final String message;
  final String? title;
  final IconData? icon;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final DateTime Function()? nowProvider;

  const ThemedBanner({
    super.key,
    required this.type,
    required this.message,
    this.title,
    this.icon,
    this.onDismiss,
    this.onRetry,
    this.retryLabel,
    this.nowProvider,
  });

  @override
  State<ThemedBanner> createState() => _ThemedBannerState();
}

class _ThemedBannerState extends State<ThemedBanner> {
  DateTime? _lastRetryTapTime;

  void _handleRetry() {
    if (widget.onRetry == null) return;
    // Tap-debounce guard (QA audit A4): banner retries are raw TextButtons
    // reachable while their parent screen has no busy state; rapid re-taps
    // must not re-fire refetches or state-changing submit retries.
    final now =
        widget.nowProvider != null ? widget.nowProvider!() : DateTime.now();
    if (_lastRetryTapTime != null &&
        now.difference(_lastRetryTapTime!) < AppMotion.debounceGuard) {
      return;
    }
    _lastRetryTapTime = now;
    widget.onRetry!();
  }

  Color _accentColor() {
    switch (widget.type) {
      case ThemedBannerType.error:
        return AppColors.error;
      case ThemedBannerType.success:
        return context.semanticColors.success;
      case ThemedBannerType.warning:
        return context.semanticColors.warning;
      case ThemedBannerType.info:
        return AppColors.primary;
    }
  }

  Color _backgroundColor() {
    switch (widget.type) {
      case ThemedBannerType.error:
        return AppColors.error.withValues(alpha: 0.1);
      case ThemedBannerType.success:
        return context.semanticColors.success.withValues(alpha: 0.1);
      case ThemedBannerType.warning:
        return context.semanticColors.warning.withValues(alpha: 0.12);
      case ThemedBannerType.info:
        return AppColors.primary.withValues(alpha: 0.08);
    }
  }

  Color _borderColor() {
    switch (widget.type) {
      case ThemedBannerType.error:
        return AppColors.error.withValues(alpha: 0.3);
      case ThemedBannerType.success:
        return context.semanticColors.success.withValues(alpha: 0.3);
      case ThemedBannerType.warning:
        return context.semanticColors.warning.withValues(alpha: 0.4);
      case ThemedBannerType.info:
        return AppColors.primary.withValues(alpha: 0.25);
    }
  }

  IconData _defaultIcon() {
    switch (widget.type) {
      case ThemedBannerType.error:
        return Icons.error_outline;
      case ThemedBannerType.success:
        return Icons.check_circle_outline;
      case ThemedBannerType.warning:
        return Icons.warning_amber_rounded;
      case ThemedBannerType.info:
        return Icons.info_outline;
    }
  }

  String? _defaultTitle() {
    switch (widget.type) {
      case ThemedBannerType.error:
        return AppLocalizations.of(context)?.defaultErrorTitle ??
            "Error occurred";
      case ThemedBannerType.success:
      case ThemedBannerType.warning:
      case ThemedBannerType.info:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor();
    final effectiveIcon = widget.icon ?? _defaultIcon();
    final effectiveTitle = widget.title ?? _defaultTitle();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _backgroundColor(),
        borderRadius: AppRadius.defaultBorder,
        border: Border.all(
          color: _borderColor(),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            effectiveIcon,
            size: AppIconSize.md,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (effectiveTitle != null && effectiveTitle.isNotEmpty) ...[
                  Text(
                    effectiveTitle,
                    style: AppTypography.labelLg.copyWith(
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  widget.message,
                  style: AppTypography.bodyMd.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(width: AppSpacing.md),
            TextButton(
              onPressed: _handleRetry,
              style: TextButton.styleFrom(
                foregroundColor: accent,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                widget.retryLabel ?? context.l10n.retry,
                style: AppTypography.labelLg.copyWith(
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
          ],
          if (widget.onDismiss != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            IconButton(
              onPressed: widget.onDismiss,
              icon: const Icon(Icons.close, size: 18),
              color: accent,
              tooltip: context.l10n.tooltipClose,
            ),
          ],
        ],
      ),
    );
  }
}

/// Convenience class for inline warning notifications.
class ThemedWarningBanner extends StatelessWidget {
  final String message;
  final String? title;
  final IconData? icon;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  const ThemedWarningBanner({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ThemedBanner(
      type: ThemedBannerType.warning,
      message: message,
      title: title,
      icon: icon,
      onDismiss: onDismiss,
      onRetry: onRetry,
    );
  }
}

/// Convenience class for inline informational notifications.
class ThemedInfoBanner extends StatelessWidget {
  final String message;
  final String? title;
  final IconData? icon;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  const ThemedInfoBanner({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ThemedBanner(
      type: ThemedBannerType.info,
      message: message,
      title: title,
      icon: icon,
      onDismiss: onDismiss,
      onRetry: onRetry,
    );
  }
}
