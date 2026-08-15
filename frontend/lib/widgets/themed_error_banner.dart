import 'package:flutter/material.dart';
import 'themed_banner.dart';

export 'themed_banner.dart'
    show ThemedBanner, ThemedBannerType, ThemedWarningBanner, ThemedInfoBanner;

class ThemedErrorBanner extends StatelessWidget {
  final String message;
  final String? title;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  const ThemedErrorBanner({
    super.key,
    required this.message,
    this.title,
    this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ThemedBanner(
      type: ThemedBannerType.error,
      message: message,
      title: title,
      onDismiss: onDismiss,
      onRetry: onRetry,
    );
  }
}
