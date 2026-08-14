import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';

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
    final theme = Theme.of(context);
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
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    titleText,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitleText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildVersionRow(
                          context,
                          label: isArabic ? 'الإصدار الحالي' : 'Installed Version',
                          value: curVer,
                          isHighlight: false,
                        ),
                        const Divider(height: 20),
                        _buildVersionRow(
                          context,
                          label: isArabic ? 'الحد الأدنى المطلوب' : 'Minimum Required',
                          value: minVer,
                          isHighlight: true,
                        ),
                        if (latVer != minVer) ...[
                          const Divider(height: 20),
                          _buildVersionRow(
                            context,
                            label: isArabic ? 'أحدث إصدار متاء' : 'Latest Available',
                            value: latVer,
                            isHighlight: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      key: const Key('update_now_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: onUpdatePressed ?? () {
                        // Action callback or URL launch
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        isArabic ? 'تحديث الآن' : 'Update Now',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    url,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
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
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isHighlight
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isHighlight
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
