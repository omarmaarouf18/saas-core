import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/logout_helper.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/themed_panel.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_success_banner.dart';
import '../widgets/themed_text_field.dart';
import 'customer_tickets_screen.dart';
import 'kyc_document_upload_screen.dart';
import 'my_account_screen.dart';
import 'notifications_screen.dart';
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
    final theme = Theme.of(context);

    final currentLangVal = localeProvider?.locale == null
        ? 'auto'
        : localeProvider!.locale!.languageCode;

    final bool showKycRow = user != null &&
        (user.role == 'owner' || user.role == 'employee') &&
        user.kycStatus != 'approved';
    final bool isKycRejected = user?.kycStatus == 'rejected';
    final bool isKycPending = user?.kycStatus == 'pending_super_admin_approval';

    String kycSubtitle = l10n.settingsKycSubtitleDefault;
    Color kycIconColor = theme.colorScheme.primary;
    if (isKycRejected) {
      kycSubtitle = l10n.settingsKycSubtitleRejected;
      kycIconColor = AppColors.error;
    } else if (isKycPending) {
      kycSubtitle = l10n.settingsKycSubtitlePending;
      kycIconColor = context.semanticColors.warning;
    }

    return FormScreenTemplate(
      title: l10n.settingsTitle,
      isEmbeddedInTab: isEmbeddedInTab,
      backgroundColor: theme.scaffoldBackgroundColor,
      showBackButton: isEmbeddedInTab ? false : null,
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: l10n.notificationsTitle,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              ),
            );
          },
        ),
      ],
      padding: const EdgeInsets.all(AppSpacing.lg),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top User Profile Card (Stitch DOM)
          if (user != null) ...[
            ThemedCard(
              padding: AppSpacing.md,
              child: Row(
                children: [
                  EntityAvatar(
                    name: user.username.isNotEmpty
                        ? user.username
                        : (user.email.isNotEmpty ? user.email : 'User'),
                    radius: 28,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.username.isNotEmpty
                              ? user.username
                              : l10n.quickDeliveryUserFallback,
                          style: AppTypography.titleMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          user.email,
                          style: AppTypography.labelMd.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ThemedPanel(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: AppRadius.smBorder,
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      child: Text(
                        AppTypography.uppercaseLabel(user.role),
                        style: AppTypography.labelSm.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

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
                  style: AppTypography.titleMd.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
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
                        style: AppTypography.labelLg.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      icon: const Icon(
                        Icons.light_mode_outlined,
                        size: AppIconSize.sm,
                      ),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(
                        l10n.themeDark,
                        key: const Key('theme_dark_button'),
                        style: AppTypography.labelLg.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      icon: const Icon(
                        Icons.dark_mode_outlined,
                        size: AppIconSize.sm,
                      ),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(
                        l10n.themeSystem,
                        key: const Key('theme_system_button'),
                        style: AppTypography.labelLg.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      icon: const Icon(
                        Icons.brightness_auto_outlined,
                        size: AppIconSize.sm,
                      ),
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
                  style: AppTypography.titleMd.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
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
                        style: AppTypography.labelLg.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      icon: const Icon(
                        Icons.brightness_auto_outlined,
                        size: AppIconSize.sm,
                      ),
                    ),
                    ButtonSegment(
                      value: 'en',
                      label: Text(
                        l10n.langEnglish,
                        key: const Key('lang_en_button'),
                        style: AppTypography.labelLg.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ButtonSegment(
                      value: 'ar',
                      label: Text(
                        l10n.langArabic,
                        key: const Key('lang_ar_button'),
                        style: AppTypography.labelLg.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
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
                      leading: Icon(
                        Icons.business_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        l10n.settingsOwnerConfig,
                        style: AppTypography.bodyLg.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        l10n.settingsOwnerConfigSub,
                        style: AppTypography.bodySm.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.outline,
                      ),
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
                      leading: Icon(
                        Icons.person_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        l10n.settingsMyAccount,
                        style: AppTypography.bodyLg.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        l10n.settingsMyAccountSub,
                        style: AppTypography.bodySm.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.outline,
                      ),
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
                      title: Text(
                        l10n.settingsKycRowTitle,
                        style: AppTypography.bodyLg.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        kycSubtitle,
                        style: AppTypography.bodySm.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.outline,
                      ),
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

          // 3. Security Section (A3)
          ThemedSectionHeader(
            title: l10n.settingsSecurity,
            subtitle: l10n.settingsSecuritySub,
          ),
          const SizedBox(height: AppSpacing.sm),
          ThemedCard(
            padding: AppSpacing.md,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsTwoFactorAuth,
                        style: AppTypography.bodyLg.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        l10n.settingsTwoFactorAuthSub,
                        style: AppTypography.bodySm.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: const Key('settings_two_factor_switch'),
                  value: user?.twoFactorEnabled ?? true,
                  onChanged: (bool newVal) async {
                    if (!newVal) {
                      final confirmed = await ConfirmActionDialog.show(
                        context,
                        title: l10n.disableTwoFactorConfirmTitle,
                        message: l10n.disableTwoFactorConfirmBody,
                        confirmLabel: l10n.disableTwoFactorConfirmAction,
                        cancelLabel: l10n.cancel,
                        isDestructive: true,
                      );
                      if (confirmed != true) return;

                      if (!context.mounted) return;
                      final disabled =
                          await _DisableTwoFactorPasswordDialog.show(
                        context,
                        auth,
                      );
                      if (disabled == true && context.mounted) {
                        ThemedSnackBar.showSuccess(
                          context,
                          l10n.twoFactorDisabledSuccess,
                        );
                      }
                      return;
                    }

                    try {
                      await auth.toggleTwoFactor(true);
                      if (context.mounted) {
                        ThemedSnackBar.showSuccess(
                          context,
                          l10n.twoFactorEnabledSuccess,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ThemedSnackBar.showError(
                          context,
                          friendlyErrorMessage(e),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 4. Support Section
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
                key: const Key('support_tickets_setting_row'),
                leading: Icon(
                  Icons.confirmation_number_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  l10n.settingsSupportTickets,
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  l10n.settingsSupportTicketsSub,
                  style: AppTypography.bodySm.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.outline,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CustomerTicketsScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // 4. Logout Section
          PrimaryButton(
            key: const Key('settings_logout_button'),
            text: l10n.settingsLogout,
            icon: Icons.logout,
            isDestructive: true,
            onPressed: () async {
              await logoutAndClearProviders(context);
            },
          ),
        ],
      ),
    );
  }
}

class _DisableTwoFactorPasswordDialog extends StatefulWidget {
  final AuthProvider auth;

  const _DisableTwoFactorPasswordDialog({required this.auth});

  static Future<bool?> show(BuildContext context, AuthProvider auth) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DisableTwoFactorPasswordDialog(auth: auth),
    );
  }

  @override
  State<_DisableTwoFactorPasswordDialog> createState() =>
      _DisableTwoFactorPasswordDialogState();
}

class _DisableTwoFactorPasswordDialogState
    extends State<_DisableTwoFactorPasswordDialog> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.clear();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    final password = _passwordController.text;
    setState(() => _isLoading = true);

    try {
      await widget.auth.toggleTwoFactor(false, password: password);
      // Immediately clear the password to avoid retention in memory
      _passwordController.clear();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        // Audit S5: read the stored failure instead of always blaming the
        // password — a 429 lockout surfaces the server lockout text (with
        // wait time) and offers no retry (retries extend the lockout);
        // other non-401 failures surface the stored server/connectivity
        // copy; only a true 401 keeps the generic wrong-password string.
        final auth = widget.auth;
        setState(() {
          _errorMessage = auth.lastErrorStatusCode == 401
              ? context.l10n.disableTwoFactorPasswordError
              : (auth.error ?? context.l10n.disableTwoFactorPasswordError);
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
      backgroundColor: theme.colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.lock_outline_rounded,
              color: context.semanticColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.disableTwoFactorPasswordTitle,
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.disableTwoFactorPasswordBody,
                style: AppTypography.bodyMd.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                // Audit S5: lockout copy gets its own key so tests (and any
                // future retry logic) can tell it from a wrong-password
                // failure — mirroring the reset-code lockout banner.
                ThemedErrorBanner(
                  key: Key(widget.auth.lastErrorStatusCode == 429
                      ? 'disable_2fa_lockout_banner'
                      : 'disable_2fa_password_error'),
                  message: _errorMessage!,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              ThemedTextField(
                key: const Key('disable_2fa_password_field'),
                controller: _passwordController,
                labelText: l10n.loginPasswordLabel,
                isPasswordField: true,
                enabled: !_isLoading,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return l10n.loginPasswordReq;
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        SecondaryButton(
          key: const Key('disable_2fa_cancel_btn'),
          text: l10n.cancel,
          isFullWidth: false,
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          key: const Key('disable_2fa_confirm_btn'),
          text: l10n.disableTwoFactorConfirmAction,
          isFullWidth: false,
          isDestructive: true,
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
    );
  }
}
