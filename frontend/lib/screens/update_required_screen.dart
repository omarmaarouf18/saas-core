import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/locale_provider.dart';
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
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    final isArabic = localeProvider.locale?.languageCode == 'ar';

    final titleText = isArabic ? 'تحديث التطبيق مطلوب' : 'App Update Required';
    final subtitleText = isArabic
        ? 'يتوفر تحديث إجباري هام للتطبيق. يرجى التحديث لمتابعة استخدام خدمة Quick Delivery.'
        : 'A mandatory app update is available. Please update Quick Delivery to continue using the service.';

    final curVer = currentVersion ?? '1.0.0';
    final minVer = minimumVersion ?? '1.1.0';
    final latVer = latestVersion ?? minVer;
    final url = downloadUrl ??
        'https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk';

    return PopScope(
      canPop: false, // Non-dismissible
      child: AppShell(
        backgroundColor: AppColors.background,
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
                              color: AppColors.onSurface,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            subtitleText,
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // 3. What's New Feature List
                          _buildWhatsNewList(isArabic),
                          const SizedBox(height: AppSpacing.md),

                          // 4. Version Details Matrix Card
                          _buildVersionMatrix(
                            context,
                            curVer: curVer,
                            minVer: minVer,
                            latVer: latVer,
                            isArabic: isArabic,
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // 5. Warning Notice Callout Banner
                          _buildWarningBanner(isArabic),
                          const SizedBox(height: AppSpacing.lg),

                          // 6. Primary Action CTA & Target URL
                          _buildActionArea(isArabic, url),
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

  Widget _buildWhatsNewList(bool isArabic) {
    return ThemedPanel(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? "الجديد في التحديث:" : "What's new:",
              style: AppTypography.titleMd.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildFeatureItem(
              icon: Icons.security,
              text: isArabic
                  ? "بروتوكولات أمان معززة لتتبع الطلبات والخدمات."
                  : "Enhanced security protocols for order and delivery tracking.",
            ),
            const SizedBox(height: AppSpacing.xs),
            _buildFeatureItem(
              icon: Icons.speed,
              text: isArabic
                  ? "خوارزميات توجيه محسنة لتسليم أسرع."
                  : "Optimized routing algorithms for faster deliveries.",
            ),
            const SizedBox(height: AppSpacing.xs),
            _buildFeatureItem(
              icon: Icons.bug_report,
              text: isArabic
                  ? "إصلاحات هامة وتحسينات في استقرار التطبيق."
                  : "Critical bug fixes and stability improvements.",
            ),
          ],
        ));
  }

  Widget _buildVersionMatrix(
    BuildContext context, {
    required String curVer,
    required String minVer,
    required String latVer,
    required bool isArabic,
  }) {
    return ThemedPanel(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            _buildVersionRow(
              context,
              label: isArabic ? 'الإصدار الحالي' : 'Installed Version',
              value: curVer,
              isHighlight: false,
            ),
            const Divider(
              height: AppSpacing.md,
              color: AppColors.outlineVariant,
            ),
            _buildVersionRow(
              context,
              label: isArabic ? 'الحد الأدنى المطلوب' : 'Minimum Required',
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
                label: isArabic ? 'أحدث إصدار متاح' : 'Latest Available',
                value: latVer,
                isHighlight: false,
              ),
            ],
          ],
        ));
  }

  Widget _buildWarningBanner(bool isArabic) {
    return ThemedPanel(
        color: AppColors.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.3),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                isArabic
                    ? "لا يمكنك متابعة استخدام التطبيق حتى يتم تثبيت هذا التحديث."
                    : "You cannot continue using the app until this update is installed.",
                style: AppTypography.caption.copyWith(
                  color: AppColors.onErrorContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ));
  }

  Widget _buildActionArea(bool isArabic, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          key: const Key('update_now_button'),
          trailingIcon: Icons.arrow_forward,
          text: isArabic ? 'تحديث الآن' : 'Update Now',
          onPressed: onUpdatePressed ?? () {},
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          url,
          style: AppTypography.caption.copyWith(
            color: AppColors.outline,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFeatureItem({
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
              color: AppColors.onSurfaceVariant,
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
            color: AppColors.onSurfaceVariant,
          ),
        ),
        ThemedPanel(
            color: isHighlight
                ? AppColors.error.withValues(alpha: 0.12)
                : AppColors.surfaceContainerHighest,
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
                color: isHighlight ? AppColors.error : AppColors.onSurface,
              ),
            )),
      ],
    );
  }
}
