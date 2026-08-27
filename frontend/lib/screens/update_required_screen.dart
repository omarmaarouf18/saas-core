import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../widgets/themed_panel.dart';
import '../widgets/primary_button.dart';
import '../widgets/app_shell.dart';
import '../widgets/themed_card.dart';

class UpdateRequiredScreen extends StatelessWidget {
  final String? currentVersion;
  final String? minimumVersion;
  final String? latestVersion;
  final String? downloadUrl;
  final VoidCallback? onUpdatePressed;

  const UpdateRequiredScreen({
    super.key,
    this.currentVersion,
    this.minimumVersion,
    this.latestVersion,
    this.downloadUrl,
    this.onUpdatePressed,
  });

  @override
  Widget build(BuildContext context) {
    // A8: route all copy through generated l10n — the previous manual
    // `isArabic ? … : …` ternaries bypassed context.l10n and duplicated ARB
    // content inline.
    final l10n = context.l10n;
    final titleText = l10n.appUpdateRequiredTitle;
    final subtitleText = l10n.mandatoryUpdateBody;

    final curVer = currentVersion ?? '1.0.0';
    final minVer = minimumVersion ?? '1.1.0';
    final latVer = latestVersion ?? minVer;
    final url = downloadUrl ??
        'https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk';

    return PopScope(
      canPop: false, // Non-dismissible
      child: AppShell(
        showBackButton: false,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.marginMobile,
              vertical: AppSpacing.md,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ThemedCard(
                padding: 0,
                borderRadius: AppRadius.lg,
                elevation: AppElevation.shadowLevel2List,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Decorative Dark Gradient Header with Pulse Rings & Icon
                    _buildHeroHeader(),

                    // 2. Main Content Body
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Headline & Operational Subtitle
                          Text(
                            titleText,
                            style: AppTypography.headlineLgMobile.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            subtitleText,
                            style: AppTypography.bodyMd.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // 3. What's New Feature List
                          _buildWhatsNewList(context, l10n),
                          const SizedBox(height: AppSpacing.md),

                          // 4. Version Details Matrix Card
                          _buildVersionMatrix(
                            context,
                            l10n: l10n,
                            curVer: curVer,
                            minVer: minVer,
                            latVer: latVer,
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // 5. Warning Notice Callout Banner
                          _buildWarningBanner(context, l10n),
                          const SizedBox(height: AppSpacing.lg),

                          // 6. Primary Action CTA & Target URL
                          _buildActionArea(context, l10n, url),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return ThemedPanel(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryContainer,
            AppColors.primary,
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
        ),
        height: 140,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Concentric Decorative Outer Rings
            ThemedPanel(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  width: 2,
                ),
                width: 120,
                height: 120),
            ThemedPanel(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.25),
                  width: 2,
                ),
                width: 86,
                height: 86),
            // Central Amber Gold Circular Icon Container
            const ThemedPanel(
                color: AppColors.secondary,
                shape: BoxShape.circle,
                width: 60,
                height: 60,
                child: Center(
                  child: Icon(
                    Icons.system_update,
                    size: 30,
                    color: AppColors.primary,
                  ),
                )),
          ],
        ));
  }

  Widget _buildWhatsNewList(BuildContext context, AppLocalizations l10n) {
    return ThemedPanel(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.whatsNewTitle,
              style: AppTypography.titleMd.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildFeatureItem(
              context,
              icon: Icons.security,
              text: l10n.whatsNewSecurityItem,
            ),
            const SizedBox(height: AppSpacing.xs),
            _buildFeatureItem(
              context,
              icon: Icons.speed,
              text: l10n.whatsNewRoutingItem,
            ),
            const SizedBox(height: AppSpacing.xs),
            _buildFeatureItem(
              context,
              icon: Icons.bug_report,
              text: l10n.whatsNewBugFixesItem,
            ),
          ],
        ));
  }

  Widget _buildVersionMatrix(
    BuildContext context, {
    required AppLocalizations l10n,
    required String curVer,
    required String minVer,
    required String latVer,
  }) {
    return ThemedPanel(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            _buildVersionRow(
              context,
              label: l10n.installedVersionLabel,
              value: curVer,
              isHighlight: false,
            ),
            const Divider(
              height: AppSpacing.md,
              color: AppColors.outlineVariant,
            ),
            _buildVersionRow(
              context,
              label: l10n.minimumRequiredLabel,
              value: minVer,
              isHighlight: true,
            ),
            if (latVer != minVer) ...[
              const Divider(
                height: AppSpacing.md,
                color: AppColors.outlineVariant,
              ),
              _buildVersionRow(
                context,
                label: l10n.latestAvailableLabel,
                value: latVer,
                isHighlight: false,
              ),
            ],
          ],
        ));
  }

  Widget _buildWarningBanner(BuildContext context, AppLocalizations l10n) {
    return ThemedPanel(
        color:
            Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                l10n.updateCannotContinueBody,
                style: AppTypography.caption.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ));
  }

  Widget _buildActionArea(
      BuildContext context, AppLocalizations l10n, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          key: const Key('update_now_button'),
          trailingIcon: Icons.arrow_forward,
          text: l10n.updateNowBtn,
          onPressed: onUpdatePressed ?? () {},
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          url,
          style: AppTypography.caption.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFeatureItem(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: AppColors.secondary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySm.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVersionRow(
    BuildContext context, {
    required String label,
    required String value,
    required bool isHighlight,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodySm.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        ThemedPanel(
            color: isHighlight
                ? AppColors.error.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: isHighlight
                ? Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.baseSm,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              value,
              style: AppTypography.labelLg.copyWith(
                fontWeight: FontWeight.bold,
                color: isHighlight
                    ? AppColors.error
                    : Theme.of(context).colorScheme.onSurface,
              ),
            )),
      ],
    );
  }
}
