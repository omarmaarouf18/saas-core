import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/dashboard_screen_template.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/info_list_tile.dart';
import '../widgets/list_screen_template.dart';
import '../widgets/otp_pin_input.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/rating_summary_card.dart';
import '../widgets/route_timeline.dart';
import '../widgets/secondary_button.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_panel.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_success_banner.dart';
import '../widgets/themed_text_field.dart';

/// Debug-only component library (Storybook-style) rendering every shared
/// widget in its principal states (loading / error / empty / success /
/// interactive). Reachable only in debug builds via the `/component-library`
/// route; excluded from release binaries.
class ComponentLibraryScreen extends StatelessWidget {
  const ComponentLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    assert(
      kDebugMode,
      'ComponentLibraryScreen is debug-only and must not be built in release',
    );
    return AppShell(
      title: 'Component Library',
      subtitle: 'Shared widget catalog — debug only',
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _section('Buttons'),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              PrimaryButton(text: 'Primary', onPressed: () {}),
              const PrimaryButton(text: 'Loading', isLoading: true),
              const PrimaryButton(text: 'Disabled'),
              SecondaryButton(text: 'Secondary', onPressed: () {}),
              PrimaryButton(
                text: 'Destructive',
                isDestructive: true,
                onPressed: () {},
              ),
            ],
          ),
          _section('Status Badges'),
          const Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusBadge(status: 'completed'),
              StatusBadge(status: 'active'),
              StatusBadge(status: 'pending'),
              StatusBadge(status: 'cancelled'),
              StatusBadge(status: 'escrow_reconciliation_required'),
            ],
          ),
          _section('Cards & Panels'),
          ThemedCard(
            child: Text('ThemedCard.normal',
                style: AppTypography.bodyMd
                    .copyWith(color: Theme.of(context).colorScheme.onSurface)),
          ),
          const SizedBox(height: AppSpacing.sm),
          const ThemedCard(
            variant: ThemedCardVariant.highlighted,
            child: Text('ThemedCard.highlighted'),
          ),
          const SizedBox(height: AppSpacing.sm),
          const ThemedPanel(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text('ThemedPanel tinted'),
          ),
          const SizedBox(height: AppSpacing.sm),
          const ThemedPanel(
            shape: BoxShape.circle,
            color: AppColors.secondary,
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: Icon(Icons.local_shipping, color: AppColors.onSecondary),
          ),
          _section('Text Fields'),
          const Column(
            children: [
              ThemedTextField(labelText: 'Label field'),
              SizedBox(height: AppSpacing.md),
              ThemedTextField(hintText: 'Hint only field'),
              SizedBox(height: AppSpacing.md),
              ThemedTextField(
                labelText: 'Password',
                isPasswordField: true,
                obscureText: true,
              ),
            ],
          ),
          _section('Loading States'),
          const ThemedLoadingIndicator(message: 'Loading content…'),
          const SizedBox(height: AppSpacing.md),
          const SkeletonLoader(width: double.infinity, height: 72),
          const SizedBox(height: AppSpacing.md),
          const MarketplaceCardSkeleton(),
          const SizedBox(height: AppSpacing.md),
          const WalletScreenSkeleton(),
          _section('Error / Empty / Success States'),
          const ThemedErrorBanner(
            message: 'Something went wrong while fetching data.',
          ),
          const SizedBox(height: AppSpacing.sm),
          ThemedErrorBanner(
            message: 'Network unreachable.',
            onRetry: () {},
          ),
          const SizedBox(height: AppSpacing.sm),
          const ThemedSuccessBanner(message: 'Changes saved successfully.'),
          const SizedBox(height: AppSpacing.sm),
          ThemedEmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing here yet',
            description: 'Items you create will appear in this list.',
            actionText: 'Create item',
            onActionPressed: () {},
          ),
          _section('Pill Filter Bar'),
          PillFilterBar<String>(
            items: const [
              PillFilterItem(label: 'All', value: 'all', count: 12),
              PillFilterItem(label: 'Active', value: 'active', count: 3),
              PillFilterItem(label: 'Done', value: 'done', count: 9),
            ],
            selectedValue: 'all',
            onSelected: (_) {},
          ),
          _section('OTP PIN Input'),
          OtpPinInput(
            controller: TextEditingController(),
            onChanged: (_) {},
          ),
          _section('Avatars, Stats & Lists'),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              EntityAvatar(name: 'Omar Maarouf', radius: 24),
              EntityAvatar(name: 'Sara', radius: 24),
              EntityAvatar(name: 'K Y', radius: 24),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const StatCard(
            label: 'Stat Card',
            value: '\$1,234.56',
            icon: Icons.account_balance_wallet,
          ),
          const SizedBox(height: AppSpacing.md),
          const InfoListTile(
            leadingIcon: Icons.info_outline,
            title: 'Info List Tile',
            subtitle: 'Supporting detail text',
          ),
          _section('Route Timeline'),
          const RouteTimeline(
            pickupAddress: 'Pickup — Downtown Hub',
            dropoffAddress: 'Dropoff — Nasr City',
          ),
          _section('Rating Summary'),
          const RatingSummaryCard(averageRating: 4.5, ratingCount: 128),
          _section('Templates'),
          SizedBox(
            height: 220,
            child: ListScreenTemplate<String>(
              title: 'ListScreenTemplate',
              showBackButton: false,
              items: const ['Alpha', 'Beta', 'Gamma'],
              itemBuilder: (_, item, __) => ListTile(title: Text(item)),
              emptyTitle: 'Empty list template',
            ),
          ),
          SizedBox(
            height: 220,
            child: FormScreenTemplate(
              title: 'FormScreenTemplate',
              showBackButton: false,
              formKey: GlobalKey<FormState>(),
              submitButtonText: 'Submit',
              children: const [
                ThemedTextField(labelText: 'Example input'),
              ],
            ),
          ),
          SizedBox(
            height: 260,
            child: DashboardScreenTemplate(
              title: 'DashboardTemplate',
              currentIndex: 0,
              onDestinationSelected: (_) {},
              tabs: const [Center(child: Text('Dashboard tab body'))],
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(
                    icon: Icon(Icons.settings), label: 'Settings'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: ThemedSectionHeader(title: title),
    );
  }
}
