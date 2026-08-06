import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/logout_helper.dart';
import '../widgets/create_ticket_dialog.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_section_header.dart';
import 'my_account_screen.dart';
import 'owner_configuration_screen.dart';

class SettingsScreen extends StatelessWidget {
  final bool isEmbeddedInTab;
  const SettingsScreen({super.key, this.isEmbeddedInTab = false});

  Widget _buildComingSoonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceDim,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Text(
        "Coming Soon",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: isEmbeddedInTab
          ? null
          : AppBar(
              title: const Text("Settings"),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Appearance Section
            const ThemedSectionHeader(
              title: "Appearance",
              subtitle: "Customize application look and feel",
            ),
            const SizedBox(height: AppSpacing.sm),
            ThemedCard(
              padding: AppSpacing.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Theme Mode",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<ThemeMode>(
                    key: const Key('theme_mode_selector'),
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(
                          "Light",
                          key: Key('theme_light_button'),
                        ),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(
                          "Dark",
                          key: Key('theme_dark_button'),
                        ),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(
                          "System",
                          key: Key('theme_system_button'),
                        ),
                        icon: Icon(Icons.brightness_auto_outlined),
                      ),
                    ],
                    selected: {themeProvider.themeMode},
                    onSelectionChanged: (Set<ThemeMode> selection) {
                      if (selection.isNotEmpty) {
                        themeProvider.setThemeMode(selection.first);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 2. Preferences (Language) Section
            const ThemedSectionHeader(
              title: "Preferences",
              subtitle: "App display and regional options",
            ),
            const SizedBox(height: AppSpacing.sm),
            ThemedCard(
              padding: 0,
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  key: const Key('language_setting_row'),
                  leading: const Icon(Icons.language_outlined,
                      color: AppColors.primary),
                  title: const Text("Language"),
                  subtitle: const Text("English (Default)"),
                  trailing: _buildComingSoonBadge(),
                  onTap: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Language selection is coming soon"),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 3. Role-Specific Section (Owner Configuration or My Account)
            if (user?.role == 'owner') ...[
              const ThemedSectionHeader(
                title: "Owner Configuration",
                subtitle: "Business management settings",
              ),
              const SizedBox(height: AppSpacing.sm),
              ThemedCard(
                padding: 0,
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    key: const Key('owner_config_setting_row'),
                    leading: const Icon(Icons.business_outlined,
                        color: AppColors.primary),
                    title: const Text("Owner Configuration"),
                    subtitle: const Text("Tenant rules & service options"),
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
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ] else if (user?.role == 'user') ...[
              const ThemedSectionHeader(
                title: "Account",
                subtitle: "Profile and user details",
              ),
              const SizedBox(height: AppSpacing.sm),
              ThemedCard(
                padding: 0,
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    key: const Key('my_account_setting_row'),
                    leading: const Icon(Icons.person_outlined,
                        color: AppColors.primary),
                    title: const Text("My Account"),
                    subtitle: const Text("Account details & preferences"),
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
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // 4. Support Section
            const ThemedSectionHeader(
              title: "Support & Help",
              subtitle: "Get assistance or submit issues",
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
                  title: const Text("Customer Service"),
                  subtitle:
                      const Text("Contact support & submit complaint tickets"),
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

            // 5. Logout Section
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                key: const Key('settings_logout_button'),
                icon: const Icon(Icons.logout, size: 20),
                label: const Text(
                  "LOG OUT",
                  style: TextStyle(
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
