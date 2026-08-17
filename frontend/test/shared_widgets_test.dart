import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/widgets/confirm_action_dialog.dart';
import 'package:frontend/widgets/create_ticket_dialog.dart';
import 'package:frontend/widgets/entity_avatar.dart';
import 'package:frontend/widgets/info_list_tile.dart';
import 'package:frontend/widgets/otp_pin_input.dart';
import 'package:frontend/widgets/pill_filter_bar.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/rating_summary_card.dart';
import 'package:frontend/widgets/route_timeline.dart';
import 'package:frontend/widgets/secondary_button.dart';
import 'package:frontend/widgets/stat_card.dart';
import 'package:frontend/widgets/status_badge.dart';
import 'package:frontend/widgets/themed_card.dart';
import 'package:frontend/widgets/themed_empty_state.dart';
import 'package:frontend/widgets/themed_error_banner.dart';
import 'package:frontend/widgets/themed_success_banner.dart';
import 'package:frontend/widgets/themed_text_field.dart';
import 'package:provider/provider.dart';

void main() {
  group('StatusBadge Widget Tests', () {
    testWidgets('Renders all 6 JobStatus values distinctly', (tester) async {
      final statuses = [
        'pending',
        'awaiting_price_response',
        'active',
        'completed',
        'cancelled',
        'escrow_reconciliation_required',
      ];

      for (final status in statuses) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatusBadge(status: status),
            ),
          ),
        );

        final context = tester.element(find.byType(StatusBadge));
        final config = StatusBadge.getConfig(context, status);
        expect(find.text(config.label.toUpperCase()), findsOneWidget);
        expect(find.byIcon(config.icon), findsOneWidget);
      }
    });

    testWidgets('Renders compact mode and handles unknown status gracefully',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              status: 'custom_unknown_status',
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('CUSTOM UNKNOWN STATUS'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });

  group('EntityAvatar Widget Tests', () {
    testWidgets('Renders initials for multi-word and single-word names',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                EntityAvatar(name: 'John Doe'),
                EntityAvatar(name: 'Alice'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('JD'), findsOneWidget);
      expect(find.text('AL'), findsOneWidget);
    });

    testWidgets('Handles missing/null name gracefully with fallback icon',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EntityAvatar(
              name: null,
              defaultIcon: Icons.directions_car,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.directions_car), findsOneWidget);
    });

    testWidgets('Triggers onTap when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntityAvatar(
              name: 'Test User',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(EntityAvatar));
      expect(tapped, isTrue);
    });

    testWidgets('Enforces 600ms tap debounce guard', (tester) async {
      int tapCount = 0;
      DateTime simulatedTime = DateTime(2026, 8, 16, 12, 0, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntityAvatar(
              name: 'Debounce User',
              nowProvider: () => simulatedTime,
              onTap: () => tapCount++,
            ),
          ),
        ),
      );

      // First tap -> executes
      await tester.tap(find.byType(EntityAvatar));
      await tester.pump();
      expect(tapCount, 1);

      // Rapid second tap at +200ms -> debounced
      simulatedTime = simulatedTime.add(const Duration(milliseconds: 200));
      await tester.tap(find.byType(EntityAvatar));
      await tester.pump();
      expect(tapCount, 1);

      // Third tap at +700ms -> allowed
      simulatedTime = simulatedTime.add(const Duration(milliseconds: 500));
      await tester.tap(find.byType(EntityAvatar));
      await tester.pump();
      expect(tapCount, 2);
    });
  });

  group('InfoListTile Widget Tests', () {
    testWidgets('Renders title, subtitle, leading icon, and trailing widget',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InfoListTile(
              title: 'Test Notification',
              subtitle: 'Shipment dispatched',
              leadingIcon: Icons.notifications,
              trailing: Text('Now'),
            ),
          ),
        ),
      );

      expect(find.text('Test Notification'), findsOneWidget);
      expect(find.text('Shipment dispatched'), findsOneWidget);
      expect(find.byIcon(Icons.notifications), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
    });

    testWidgets('Triggers onTap when tile is tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InfoListTile(
              title: 'Clickable Tile',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Clickable Tile'));
      expect(tapped, isTrue);
    });
  });

  group('StatCard Widget Tests', () {
    testWidgets('Renders label, value, icon, and trend', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              label: 'Total Revenue',
              value: '1,250.00 Credits',
              icon: Icons.account_balance_wallet,
              trend: '+12% this week',
              isPositiveTrend: true,
            ),
          ),
        ),
      );

      expect(find.text('Total Revenue'), findsOneWidget);
      expect(find.text('1,250.00 Credits'), findsOneWidget);
      expect(find.byIcon(Icons.account_balance_wallet), findsOneWidget);
      expect(find.text('+12% this week'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });

    testWidgets('Triggers onTap when card is tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatCard(
              label: 'Tappable Stat',
              value: '42',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tappable Stat'));
      expect(tapped, isTrue);
    });
  });

  group('ConfirmActionDialog Widget Tests', () {
    testWidgets('Renders non-destructive dialog and returns true on confirm',
        (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ConfirmActionDialog.show(
                    context,
                    title: 'Approve Action',
                    message: 'Are you sure you want to approve this item?',
                    confirmLabel: 'Approve',
                    cancelLabel: 'Dismiss',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Approve Action'), findsOneWidget);
      expect(find.text('Are you sure you want to approve this item?'),
          findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('Renders destructive dialog and returns false on cancel',
        (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ConfirmActionDialog.show(
                    context,
                    title: 'Delete Item',
                    message: 'This action cannot be undone.',
                    confirmLabel: 'Delete',
                    isDestructive: true,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Item'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('PrimaryButton & SecondaryButton Tests', () {
    testWidgets(
        'PrimaryButton and SecondaryButton use bodyLg (16px) typography scale',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PrimaryButton(text: 'Primary Test', onPressed: () {}),
                SecondaryButton(text: 'Secondary Test', onPressed: () {}),
              ],
            ),
          ),
        ),
      );

      final primaryText = tester.widget<Text>(find.text('Primary Test'));
      final secondaryText = tester.widget<Text>(find.text('Secondary Test'));

      expect(primaryText.style?.fontSize, equals(16));
      expect(secondaryText.style?.fontSize, equals(16));
    });

    testWidgets(
        'PrimaryButton renders with Amber Gold secondary fill and Navy text, and respects isDestructive',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PrimaryButton(text: 'Standard Action', onPressed: () {}),
                PrimaryButton(
                  text: 'Destructive Action',
                  isDestructive: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final standardElevatedButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Standard Action'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(
        standardElevatedButton.style?.backgroundColor?.resolve({}),
        equals(AppColors.secondary),
      );
      final standardText = tester.widget<Text>(find.text('Standard Action'));
      expect(standardText.style?.color, equals(AppColors.onSecondary));

      final destructiveElevatedButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Destructive Action'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(
        destructiveElevatedButton.style?.backgroundColor?.resolve({}),
        equals(AppColors.error),
      );
      final destructiveText =
          tester.widget<Text>(find.text('Destructive Action'));
      expect(destructiveText.style?.color, equals(AppColors.onPrimary));
    });

    testWidgets('PrimaryButton ignores rapid double taps within 600ms',
        (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              text: 'Submit',
              onPressed: () => tapCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(tapCount, equals(1));
    });

    testWidgets('PrimaryButton accepts subsequent tap after 600ms duration',
        (tester) async {
      int tapCount = 0;
      var currentTime = DateTime(2026, 8, 7, 10, 0, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              text: 'Submit',
              onPressed: () => tapCount++,
              nowProvider: () => currentTime,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(tapCount, equals(1));

      currentTime = currentTime.add(const Duration(milliseconds: 650));

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(tapCount, equals(2));
    });

    testWidgets('SecondaryButton ignores rapid double taps within 600ms',
        (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecondaryButton(
              text: 'Cancel',
              onPressed: () => tapCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SecondaryButton));
      await tester.tap(find.byType(SecondaryButton));
      await tester.pump();

      expect(tapCount, equals(1));
    });

    testWidgets('SecondaryButton accepts subsequent tap after 600ms duration',
        (tester) async {
      int tapCount = 0;
      var currentTime = DateTime(2026, 8, 7, 10, 0, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecondaryButton(
              text: 'Cancel',
              onPressed: () => tapCount++,
              nowProvider: () => currentTime,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SecondaryButton));
      await tester.pump();
      expect(tapCount, equals(1));

      currentTime = currentTime.add(const Duration(milliseconds: 650));

      await tester.tap(find.byType(SecondaryButton));
      await tester.pump();
      expect(tapCount, equals(2));
    });

    testWidgets(
        'PrimaryButton displays AnimatedScale tap feedback on press down',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              text: 'Submit',
              onPressed: () {},
            ),
          ),
        ),
      );

      final animatedScaleFinder = find.byType(AnimatedScale);
      expect(animatedScaleFinder, findsOneWidget);

      final initialScaleWidget =
          tester.widget<AnimatedScale>(animatedScaleFinder);
      expect(initialScaleWidget.scale, equals(1.0));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(PrimaryButton)));
      await tester.pump();

      final pressedScaleWidget =
          tester.widget<AnimatedScale>(animatedScaleFinder);
      expect(pressedScaleWidget.scale, equals(0.96));

      await gesture.up();
      await tester.pumpAndSettle();

      final releasedScaleWidget =
          tester.widget<AnimatedScale>(animatedScaleFinder);
      expect(releasedScaleWidget.scale, equals(1.0));
    });

    testWidgets(
        'SecondaryButton displays AnimatedScale tap feedback on press down',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecondaryButton(
              text: 'Cancel',
              onPressed: () {},
            ),
          ),
        ),
      );

      final animatedScaleFinder = find.byType(AnimatedScale);
      expect(animatedScaleFinder, findsOneWidget);

      final initialScaleWidget =
          tester.widget<AnimatedScale>(animatedScaleFinder);
      expect(initialScaleWidget.scale, equals(1.0));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(SecondaryButton)));
      await tester.pump();

      final pressedScaleWidget =
          tester.widget<AnimatedScale>(animatedScaleFinder);
      expect(pressedScaleWidget.scale, equals(0.96));

      await gesture.up();
      await tester.pumpAndSettle();

      final releasedScaleWidget =
          tester.widget<AnimatedScale>(animatedScaleFinder);
      expect(releasedScaleWidget.scale, equals(1.0));
    });
  });

  group('Phase 3 State Widgets Tests', () {
    testWidgets(
        'ThemedEmptyState renders icon, title, description, and primary action button',
        (tester) async {
      bool actionPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThemedEmptyState(
              icon: Icons.inbox,
              title: 'No Items Found',
              description: 'Your item list is currently empty.',
              actionText: 'Browse Catalog',
              onActionPressed: () => actionPressed = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.text('No Items Found'), findsOneWidget);
      expect(find.text('Your item list is currently empty.'), findsOneWidget);
      expect(find.text('Browse Catalog'), findsOneWidget);

      await tester.tap(find.text('Browse Catalog'));
      expect(actionPressed, isTrue);
    });

    testWidgets(
        'ThemedErrorBanner renders error message and invokes inline onRetry callback',
        (tester) async {
      bool retryTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThemedErrorBanner(
              message: 'Failed to fetch network response',
              onRetry: () => retryTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('Error occurred'), findsOneWidget);
      expect(find.text('Failed to fetch network response'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retryTriggered, isTrue);
    });

    testWidgets(
        'ThemedSuccessBanner renders title and message with success styling',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThemedSuccessBanner(
              title: 'Operation Successful',
              message: 'Your profile has been updated.',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.text('Operation Successful'), findsOneWidget);
      expect(find.text('Your profile has been updated.'), findsOneWidget);
    });

    testWidgets('ThemedSnackBar.showSuccess displays floating success toast',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ThemedSnackBar.showSuccess(
                  context,
                  'Payment processed successfully',
                ),
                child: const Text('Show Success Toast'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Success Toast'));
      await tester.pumpAndSettle();

      expect(find.text('Payment processed successfully'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('ThemedSnackBar.showWarning displays floating warning toast',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ThemedSnackBar.showWarning(
                  context,
                  'Caution: Unsaved changes will be lost',
                ),
                child: const Text('Show Warning Toast'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Warning Toast'));
      await tester.pumpAndSettle();

      expect(
          find.text('Caution: Unsaved changes will be lost'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('ThemedSnackBar.showInfo displays floating info toast',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ThemedSnackBar.showInfo(
                  context,
                  'New updates are available in your area',
                ),
                child: const Text('Show Info Toast'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Info Toast'));
      await tester.pumpAndSettle();

      expect(
          find.text('New updates are available in your area'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets(
        'ThemedWarningBanner renders warning message, icon, and dismiss button',
        (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThemedWarningBanner(
              title: 'Pending Activation',
              message: 'Please complete payment to activate subscription.',
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.text('Pending Activation'), findsOneWidget);
      expect(find.text('Please complete payment to activate subscription.'),
          findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    testWidgets('ThemedInfoBanner renders info message and custom retry action',
        (tester) async {
      bool retryClicked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThemedInfoBanner(
              title: 'Courier En Route',
              message: 'Courier is currently 2.5 km away from pickup.',
              onRetry: () => retryClicked = true,
            ),
          ),
        ),
      );

      expect(find.text('Courier En Route'), findsOneWidget);
      expect(find.text('Courier is currently 2.5 km away from pickup.'),
          findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retryClicked, isTrue);
    });
  });

  group('ThemedCard Variant Widget Tests', () {
    testWidgets(
        'ThemedCard defaults to normal variant with standard border and shadow',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThemedCard(
              child: Text('Normal Card Content'),
            ),
          ),
        ),
      );

      expect(find.text('Normal Card Content'), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.width, 1.0);
      expect(decoration.boxShadow, isNotNull);
    });

    testWidgets(
        'ThemedCard highlighted variant renders 2px secondary border and level 2 shadow',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThemedCard(
              variant: ThemedCardVariant.highlighted,
              child: Text('Highlighted Tier Card'),
            ),
          ),
        ),
      );

      expect(find.text('Highlighted Tier Card'), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.width, 2.0);
      expect(border.top.color, AppColors.secondary);
    });

    testWidgets(
        'ThemedCard elevated variant renders level 3 shadow for floating overlays',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThemedCard(
              variant: ThemedCardVariant.elevated,
              child: Text('Elevated Overlay Card'),
            ),
          ),
        ),
      );

      expect(find.text('Elevated Overlay Card'), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.boxShadow, isNotNull);
    });
  });

  group('Button isFullWidth Parameter Widget Tests', () {
    testWidgets(
        'PrimaryButton defaults to full width and supports isFullWidth: false for in-row layout',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PrimaryButton(
                  key: const Key('full_width_primary'),
                  text: 'Full Width Action',
                  onPressed: () {},
                ),
                PrimaryButton(
                  key: const Key('compact_primary'),
                  text: 'Compact Action',
                  isFullWidth: false,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final fullWidthSizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byKey(const Key('full_width_primary')),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(fullWidthSizedBox.width, double.infinity);

      final compactSizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byKey(const Key('compact_primary')),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(compactSizedBox.width, isNull);
    });

    testWidgets(
        'SecondaryButton defaults to full width and supports isFullWidth: false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SecondaryButton(
                  key: const Key('full_width_secondary'),
                  text: 'Full Width Secondary',
                  onPressed: () {},
                ),
                SecondaryButton(
                  key: const Key('compact_secondary'),
                  text: 'Compact Secondary',
                  isFullWidth: false,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final fullWidthSizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byKey(const Key('full_width_secondary')),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(fullWidthSizedBox.width, double.infinity);

      final compactSizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byKey(const Key('compact_secondary')),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(compactSizedBox.width, isNull);
    });
  });

  group('RatingSummaryCard Widget Tests', () {
    testWidgets('Renders score, stars, and tokenized typography',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingSummaryCard(
              averageRating: 4.5,
              ratingCount: 128,
            ),
          ),
        ),
      );

      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('Verified Service Score'), findsOneWidget);
      expect(find.text('Based on 128 ratings'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_half), findsOneWidget);
    });
  });

  group('StatCard Widget Tests', () {
    testWidgets('Renders label, value, icon, and positive trend',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              label: 'Total Revenue',
              value: '\$12,450',
              icon: Icons.attach_money,
              trend: '+15.4%',
              isPositiveTrend: true,
            ),
          ),
        ),
      );

      expect(find.text('Total Revenue'), findsOneWidget);
      expect(find.text('\$12,450'), findsOneWidget);
      expect(find.text('+15.4%'), findsOneWidget);
      expect(find.byIcon(Icons.attach_money), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });
  });

  group('CreateTicketDialog Widget Tests', () {
    testWidgets(
        'Renders overflow-free at narrow 360dp mobile viewport and uses compact action buttons',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final apiClient = ApiClient();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider(apiClient)),
            ChangeNotifierProvider(create: (_) => ChatProvider(apiClient)),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CreateTicketDialog(contextId: 'test-job-12345'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open Complaint Ticket'), findsOneWidget);
      expect(find.text('Reference ID: #test-job'), findsOneWidget);
      expect(find.byType(ThemedTextField), findsNWidgets(2));
      expect(find.byKey(const Key('submit_ticket_button')), findsOneWidget);
      expect(find.byType(SecondaryButton), findsOneWidget);

      // Verify no RenderFlex overflow
      expect(tester.takeException(), isNull);
    });
  });

  group('OtpPinInput Widget Tests', () {
    testWidgets(
        'Renders 6 discrete input boxes and auto-advances on digit entry',
        (tester) async {
      String currentCode = '';
      String? completedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpPinInput(
              length: 6,
              onChanged: (val) => currentCode = val,
              onCompleted: (val) => completedCode = val,
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsNWidgets(6));

      // Enter digits into each box
      for (int i = 0; i < 6; i++) {
        await tester.enterText(find.byKey(Key('otp_box_$i')), '${i + 1}');
        await tester.pump();
      }

      expect(currentCode, equals('123456'));
      expect(completedCode, equals('123456'));
    });

    testWidgets('Populates boxes from external controller dynamically',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpPinInput(
              length: 6,
              controller: controller,
            ),
          ),
        ),
      );

      controller.text = '654321';
      await tester.pump();

      for (int i = 0; i < 6; i++) {
        final tf = tester.widget<TextField>(find.byKey(Key('otp_box_$i')));
        expect(tf.controller?.text, equals('${6 - i}'));
      }
    });
  });

  group('PillFilterBar Widget Tests', () {
    testWidgets('Renders filter chips and triggers onSelected callback',
        (tester) async {
      String selected = 'all';

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: PillFilterBar<String>(
                  items: const [
                    PillFilterItem(label: 'All', value: 'all'),
                    PillFilterItem(
                      label: 'Active',
                      value: 'active',
                      count: 3,
                    ),
                    PillFilterItem(label: 'Completed', value: 'completed'),
                  ],
                  selectedValue: selected,
                  onSelected: (val) {
                    setState(() => selected = val);
                  },
                ),
              ),
            );
          },
        ),
      );

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();

      expect(selected, equals('active'));
    });
  });

  group('RouteTimeline Widget Tests', () {
    testWidgets('Renders pickup, dropoff, and metrics row cleanly',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RouteTimeline(
              pickupAddress: '731 Logistics Center Pkwy',
              pickupDetail: 'Dock 4 • Bay 12',
              dropoffAddress: '192 Retail District Blvd',
              dropoffDetail: 'Back Entrance',
              distanceText: '4.2 km',
              timeText: '18 mins',
              cargoText: '2 Pallets',
            ),
          ),
        ),
      );

      expect(find.text('731 Logistics Center Pkwy'), findsOneWidget);
      expect(find.text('Dock 4 • Bay 12'), findsOneWidget);
      expect(find.text('192 Retail District Blvd'), findsOneWidget);
      expect(find.text('Back Entrance'), findsOneWidget);
      expect(find.text('4.2 km'), findsOneWidget);
      expect(find.text('18 mins'), findsOneWidget);
      expect(find.text('2 Pallets'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
