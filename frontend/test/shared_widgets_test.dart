import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/widgets/confirm_action_dialog.dart';
import 'package:frontend/widgets/entity_avatar.dart';
import 'package:frontend/widgets/info_list_tile.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';
import 'package:frontend/widgets/stat_card.dart';
import 'package:frontend/widgets/status_badge.dart';
import 'package:frontend/widgets/themed_card.dart';
import 'package:frontend/widgets/themed_empty_state.dart';
import 'package:frontend/widgets/themed_error_banner.dart';
import 'package:frontend/widgets/themed_success_banner.dart';

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
}
