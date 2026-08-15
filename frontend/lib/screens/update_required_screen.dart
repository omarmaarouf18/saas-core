import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/locale_provider.dart';
import '../widgets/primary_button.dart';
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
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    titleText,
                    style: AppTypography.headlineLgMobile.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    subtitleText,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ThemedCard(
                    padding: AppSpacing.md,
                    child: Column(
                      children: [
                        _buildVersionRow(
                          context,
                          label:
                              isArabic ? 'الإصدار الحالي' : 'Installed Version',
                          value: curVer,
                          isHighlight: false,
                        ),
                        const Divider(
                          height: AppSpacing.lg,
                          color: AppColors.outlineVariant,
                        ),
                        _buildVersionRow(
                          context,
                          label: isArabic
                              ? 'الحد الأدنى المطلوب'
                              : 'Minimum Required',
                          value: minVer,
                          isHighlight: true,
                        ),
                        if (latVer != minVer) ...[
                          const Divider(
                            height: AppSpacing.lg,
                            color: AppColors.outlineVariant,
                          ),
                          _buildVersionRow(
                            context,
                            label: isArabic
                                ? 'أحدث إصدار متاح'
                                : 'Latest Available',
                            value: latVer,
                            isHighlight: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    key: const Key('update_now_button'),
                    icon: Icons.download_rounded,
                    text: isArabic ? 'تحديث الآن' : 'Update Now',
                    onPressed: onUpdatePressed ?? () {},
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    url,
                    style: AppTypography.labelMd.copyWith(
                      color: AppColors.outline,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.baseSm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: isHighlight
                ? AppColors.error.withValues(alpha: 0.12)
                : AppColors.surfaceContainerHighest,
            borderRadius: AppRadius.defaultBorder,
            border: isHighlight
                ? Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Text(
            value,
            style: AppTypography.labelLg.copyWith(
              fontWeight: FontWeight.bold,
              color: isHighlight ? AppColors.error : AppColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
