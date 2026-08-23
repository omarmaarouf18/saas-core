import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../core/theme.dart';
import 'themed_banner.dart';

export 'themed_banner.dart'
    show ThemedBanner, ThemedBannerType, ThemedWarningBanner, ThemedInfoBanner;

/// Reusable inline success banner container following the design system tokens.
class ThemedSuccessBanner extends StatelessWidget {
  final String message;
  final String? title;
  final VoidCallback? onDismiss;

  const ThemedSuccessBanner({
    super.key,
    required this.message,
    this.title,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return ThemedBanner(
      type: ThemedBannerType.success,
      message: message,
      title: title,
      onDismiss: onDismiss,
    );
  }
}

/// Helper class providing standardized, token-driven success and error SnackBars.
class ThemedSnackBar {
  static void showSuccess(BuildContext context, String message, {Key? key}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: key,
        duration: AppMotion.snackBarDisplay,
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.defaultBorder,
        ),
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: AppIconSize.md,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMd.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
    Key? key,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: key,
        duration: AppMotion.snackBarDisplay,
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.defaultBorder,
        ),
        action: onRetry != null
            ? SnackBarAction(
                label: AppTypography.uppercaseLabel(appL10n(context).retry),
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
        content: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.white,
              size: AppIconSize.md,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMd.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showWarning(BuildContext context, String message, {Key? key}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: key,
        duration: AppMotion.snackBarDisplay,
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.defaultBorder,
        ),
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: AppIconSize.md,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMd.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showInfo(BuildContext context, String message, {Key? key}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: key,
        duration: AppMotion.snackBarDisplay,
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.defaultBorder,
        ),
        content: Row(
          children: [
            const Icon(
              Icons.info_outline,
              color: Colors.white,
              size: AppIconSize.md,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMd.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
