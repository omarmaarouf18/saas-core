import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/logout_helper.dart';
import '../widgets/create_ticket_dialog.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
import 'kyc_document_upload_screen.dart';
import 'my_account_screen.dart';
import 'owner_configuration_screen.dart';

class SettingsScreen extends StatelessWidget {
  final bool isEmbeddedInTab;
  const SettingsScreen({super.key, this.isEmbeddedInTab = false});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider?>(context);
    final l10n = context.l10n;
    final user = auth.user;

    final currentLangVal = localeProvider?.locale == null
        ? 'auto'
        : localeProvider!.locale!.languageCode;

    final bool showKycRow = user != null && user.kycStatus != 'approved';
    final bool isKycRejected = user?.kycStatus == 'rejected';
    final bool isKycPending = user?.kycStatus == 'pending_super_admin_approval';

    String kycSubtitle = "Verify your account identity and documents";
    Color kycIconColor = AppColors.primary;
    if (isKycRejected) {
      kycSubtitle = "Verification Rejected - Action Required";
      kycIconColor = AppColors.error;
    } else if (isKycPending) {
      kycSubtitle = "Verification Pending Approval";
      kycIconColor = AppColors.warning;
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: isEmbeddedInTab
          ? null
          : AppBar(
              title: Text(l10n.settingsTitle),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Consolidated Appearance & Preferences Section
            ThemedSectionHeader(
              title: l10n.settingsPreferences,
              subtitle: l10n.settingsPreferencesSub,
            ),
            const SizedBox(height: AppSpacing.sm),
            ThemedCard(
              padding: AppSpacing.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsThemeMode,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<ThemeMode>(
                    key: const Key('theme_mode_selector'),
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(
                          l10n.themeLight,
                          key: const Key('theme_light_button'),
                        ),
                        icon: const Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(
                          l10n.themeDark,
                          key: const Key('theme_dark_button'),
                        ),
                        icon: const Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(
                          l10n.themeSystem,
                          key: const Key('theme_system_button'),
                        ),
                        icon: const Icon(Icons.brightness_auto_outlined),
                      ),
                    ],
                    selected: {themeProvider.themeMode},
                    onSelectionChanged: (Set<ThemeMode> selection) {
                      if (selection.isNotEmpty) {
                        themeProvider.setThemeMode(selection.first);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.settingsLanguage,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<String>(
                    key: const Key('language_selector'),
                    segments: [
                      ButtonSegment(
                        value: 'auto',
                        label: Text(
                          l10n.langAuto,
                          key: const Key('lang_auto_button'),
                        ),
                        icon: const Icon(Icons.brightness_auto_outlined),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text(
                          l10n.langEnglish,
                          key: const Key('lang_en_button'),
                        ),
                      ),
                      ButtonSegment(
                        value: 'ar',
                        label: Text(
                          l10n.langArabic,
                          key: const Key('lang_ar_button'),
                        ),
                      ),
                    ],
                    selected: {currentLangVal},
                    onSelectionChanged: (Set<String> selection) {
                      if (selection.isNotEmpty) {
                        final val = selection.first;
                        if (val == 'en') {
                          localeProvider?.setLocale(const Locale('en'));
                        } else if (val == 'ar') {
                          localeProvider?.setLocale(const Locale('ar'));
                        } else {
                          localeProvider?.setLocale(null);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 2. Account Section (Owner Config / My Account & Relocated KYC Entry Point)
            ThemedSectionHeader(
              title: l10n.settingsAccountSection,
              subtitle: l10n.settingsAccountSectionSub,
            ),
            const SizedBox(height: AppSpacing.sm),
            ThemedCard(
              padding: 0,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    if (user?.role == 'owner') ...[
                      ListTile(
                        key: const Key('owner_config_setting_row'),
                        leading: const Icon(Icons.business_outlined,
                            color: AppColors.primary),
                        title: Text(l10n.settingsOwnerConfig),
                        subtitle: Text(l10n.settingsOwnerConfigSub),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.outline),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const OwnerConfigurationScreen(),
                            ),
                          );
                        },
                      ),
                      if (showKycRow) const Divider(height: 1),
                    ] else if (user?.role == 'user') ...[
                      ListTile(
                        key: const Key('my_account_setting_row'),
                        leading: const Icon(Icons.person_outlined,
                            color: AppColors.primary),
                        title: Text(l10n.settingsMyAccount),
                        subtitle: Text(l10n.settingsMyAccountSub),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.outline),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const MyAccountScreen(),
                            ),
                          );
                        },
                      ),
                      if (showKycRow) const Divider(height: 1),
                    ],
                    if (showKycRow)
                      ListTile(
                        key: const Key('kyc_verification_setting_row'),
                        leading: Icon(
                          Icons.verified_user_outlined,
                          color: kycIconColor,
                        ),
                        title: const Text("Identity Verification (KYC)"),
                        subtitle: Text(kycSubtitle),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.outline),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const KycDocumentUploadScreen(),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 3. Support Section
            ThemedSectionHeader(
              title: l10n.settingsSupport,
              subtitle: l10n.settingsSupportSub,
            ),
            const SizedBox(height: AppSpacing.sm),
            ThemedCard(
              padding: 0,
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  key: const Key('customer_service_setting_row'),
                  leading: const Icon(Icons.support_agent_outlined,
                      color: AppColors.primary),
                  title: Text(l10n.settingsCustomerService),
                  subtitle: Text(l10n.settingsCustomerServiceSub),
                  trailing:
                      const Icon(Icons.chevron_right, color: AppColors.outline),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const CreateTicketDialog(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // 4. Logout Section
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                key: const Key('settings_logout_button'),
                icon: const Icon(Icons.logout, size: 20),
                label: Text(
                  l10n.settingsLogout,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.defaultValue),
                  ),
                ),
                onPressed: () async {
                  await logoutAndClearProviders(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
