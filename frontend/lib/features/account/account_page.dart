import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../../ui/qd_ui.dart';
import 'account_nav.dart';
import 'my_details_page.dart';
import 'saved_addresses_page.dart';
import 'security_page.dart';

/// Customer account (A-Settings): the Account tab of the customer shell.
///
/// Behaviour kept from SettingsScreen + MyAccountScreen (customer path):
/// the profile is re-fetched on open with a retryable error banner, the
/// suspension banner (with the server reason) when suspended, my details,
/// saved addresses, 2FA (security), language (phone / English / Arabic),
/// theme (light / dark / phone), support tickets, notifications and sign
/// out.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  String? _loadError;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    setState(() => _loadError = null);
    await auth.fetchUserProfile();
    if (!mounted) return;
    setState(() => _loadError = auth.error);
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await AccountNavScope.of(context).signOut(context);
    if (mounted) setState(() => _signingOut = false);
  }

  Future<void> _pickLanguage() async {
    final l10n = context.l10n;
    final locale = context.read<LocaleProvider>();
    final current = locale.locale?.languageCode;
    await _showChoices<String?>(
      title: l10n.acctLanguage,
      selected: current,
      choices: [
        (null, l10n.acctPhoneSetting),
        ('ar', l10n.acctLangArabic),
        ('en', l10n.acctLangEnglish),
      ],
      onPick: (code) => locale.setLocale(code == null ? null : Locale(code)),
    );
  }

  Future<void> _pickTheme() async {
    final l10n = context.l10n;
    final theme = context.read<ThemeProvider>();
    await _showChoices<ThemeMode>(
      title: l10n.acctTheme,
      selected: theme.themeMode,
      choices: [
        (ThemeMode.light, l10n.acctThemeLight),
        (ThemeMode.dark, l10n.acctThemeDark),
        (ThemeMode.system, l10n.acctPhoneSetting),
      ],
      onPick: theme.setThemeMode,
    );
  }

  Future<void> _showChoices<T>({
    required String title,
    required T selected,
    required List<(T, String)> choices,
    required void Function(T) onPick,
  }) {
    return QdBottomSheet.show<void>(
      context,
      title: title,
      // The sheet lives in the navigator overlay, outside the shell theme.
      child: QdThemeScope(child: Builder(builder: (sheetContext) {
        final c = QdColors.of(sheetContext);
        return QdListGroup(children: [
          for (final (value, label) in choices)
            QdListTile(
              key: Key('choice_$label'),
              title: label,
              badge: value == selected
                  ? Icon(Icons.check, size: QdSize.icon, color: c.textPrimary)
                  : null,
              onTap: () {
                onPick(value);
                Navigator.of(sheetContext).pop();
              },
            ),
        ]);
      })),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final nav = AccountNavScope.of(context);
    final localeCode = context.watch<LocaleProvider>().locale?.languageCode;
    final themeMode = context.watch<ThemeProvider>().themeMode;

    final languageValue = switch (localeCode) {
      'ar' => l10n.acctLangArabic,
      'en' => l10n.acctLangEnglish,
      _ => l10n.acctPhoneSetting,
    };
    final themeValue = switch (themeMode) {
      ThemeMode.light => l10n.acctThemeLight,
      ThemeMode.dark => l10n.acctThemeDark,
      ThemeMode.system => l10n.acctPhoneSetting,
    };

    return Scaffold(
      key: const Key('account_page'),
      backgroundColor: c.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const Key('account_list'),
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, 28, QdSpace.gutter, QdSpace.x4),
            children: [
              if (user != null) _Header(user: user),
              if (_loadError != null) ...[
                const SizedBox(height: QdSpace.x3),
                QdBanner(
                  key: const Key('account_load_error'),
                  tone: QdBannerTone.warning,
                  message: l10n.acctLoadError,
                  actionLabel: l10n.retry,
                  onAction: _load,
                ),
              ],
              if (user?.isSuspended == true) ...[
                const SizedBox(height: QdSpace.x3),
                SuspendedBanner(user: user!),
              ],
              const SizedBox(height: QdSpace.x5),
              QdSectionHeader(title: l10n.acctSectionAccount, small: true),
              const SizedBox(height: 6),
              QdListGroup(children: [
                QdListTile(
                  key: const Key('account_details'),
                  icon: Icons.person_outline,
                  title: l10n.acctMyDetails,
                  chevron: true,
                  onTap: () =>
                      nav.push<void>(context, (_) => const MyDetailsPage()),
                ),
                QdListTile(
                  key: const Key('account_addresses'),
                  icon: Icons.location_on_outlined,
                  title: l10n.acctSavedAddresses,
                  value: '${user?.frequentAddresses?.length ?? 0}',
                  chevron: true,
                  onTap: () => nav.push<void>(
                      context, (_) => const SavedAddressesPage()),
                ),
                QdListTile(
                  key: const Key('account_security'),
                  icon: Icons.lock_outline,
                  title: l10n.acctSecurity,
                  // A subtitle, not a trailing value: the mockup's value
                  // does not fit next to the title at 360 dp.
                  subtitle: (user?.twoFactorEnabled ?? true)
                      ? l10n.acctTwoFactorOn
                      : l10n.acctTwoFactorOff,
                  chevron: true,
                  onTap: () =>
                      nav.push<void>(context, (_) => const SecurityPage()),
                ),
                QdListTile(
                  key: const Key('account_wallet'),
                  icon: Icons.account_balance_wallet_outlined,
                  title: l10n.acctWallet,
                  enabled: false,
                  badge:
                      QdStatusChip(label: l10n.acctSoon, tone: QdTone.neutral),
                ),
              ]),
              const SizedBox(height: 18),
              QdSectionHeader(title: l10n.acctSectionApp, small: true),
              const SizedBox(height: 6),
              QdListGroup(children: [
                QdListTile(
                  key: const Key('account_language'),
                  icon: Icons.language,
                  title: l10n.acctLanguage,
                  value: languageValue,
                  chevron: true,
                  onTap: _pickLanguage,
                ),
                QdListTile(
                  key: const Key('account_theme'),
                  icon: Icons.dark_mode_outlined,
                  title: l10n.acctTheme,
                  value: themeValue,
                  chevron: true,
                  onTap: _pickTheme,
                ),
                QdListTile(
                  key: const Key('account_notifications'),
                  icon: Icons.notifications_outlined,
                  title: l10n.acctNotifications,
                  chevron: true,
                  onTap: () => nav.openNotifications(context),
                ),
              ]),
              const SizedBox(height: 18),
              QdSectionHeader(title: l10n.acctSectionSupport, small: true),
              const SizedBox(height: 6),
              QdListGroup(children: [
                QdListTile(
                  key: const Key('account_support'),
                  icon: Icons.help_outline,
                  title: l10n.acctSupport,
                  chevron: true,
                  onTap: () => nav.openSupport(context),
                ),
              ]),
              const SizedBox(height: QdSpace.x3),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: QdButton.destructive(
                  key: const Key('account_sign_out'),
                  label: l10n.acctLogout,
                  loading: _signingOut,
                  onPressed: _signOut,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final name = user.username.isNotEmpty ? user.username : user.email;
    return Row(
      children: [
        QdAvatarInitial(name: name, size: 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QdText.header.copyWith(color: c.textPrimary)),
              Text(
                user.email,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QdText.secondary.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        QdButton.text(
          key: const Key('account_edit'),
          label: l10n.acctEdit,
          small: true,
          onPressed: () => AccountNavScope.of(context)
              .push<void>(context, (_) => const MyDetailsPage()),
        ),
      ],
    );
  }
}

/// Danger banner shown while the account is suspended (GAP-05), with the
/// server's reason when it gave one.
class SuspendedBanner extends StatelessWidget {
  const SuspendedBanner({super.key, required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reason = user.suspensionReason;
    return QdBanner(
      key: const Key('account_suspended'),
      tone: QdBannerTone.danger,
      icon: Icons.block,
      title: l10n.acctSuspendedTitle,
      message: reason != null && reason.isNotEmpty
          ? reason
          : l10n.acctSuspendedDefault,
    );
  }
}
