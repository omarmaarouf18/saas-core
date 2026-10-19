import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';

import '../core/theme.dart';
import '../widgets/themed_panel.dart';

/// UX-17: neutral launch splash shown while AuthProvider is restoring the
/// stored session. Keeps the app from flashing the login screen (and its
/// auth-only chrome) before the session verdict exists; MyApp routes to
/// Home/Login the moment `isLoading` clears. Theme-aware (no raw colors) and
/// text-free apart from the localized brand wordmark.
class AuthSplashScreen extends StatelessWidget {
  const AuthSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('auth_splash_screen'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThemedPanel(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.md),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storefront,
                    color: AppColors.secondary,
                    size: AppIconSize.md,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'QD',
                    style: AppTypography.titleMd.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              context.l10n.otpFooterBrand,
              style: AppTypography.labelMd.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
