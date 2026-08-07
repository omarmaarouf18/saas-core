import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/confirm_action_dialog.dart';
import 'package:frontend/widgets/entity_avatar.dart';
import 'package:frontend/widgets/info_list_tile.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';
import 'package:frontend/widgets/stat_card.dart';
import 'package:frontend/widgets/status_badge.dart';

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

        final config = StatusBadge.getConfig(status);
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

  group('PrimaryButton & SecondaryButton Debounce Tests', () {
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
  });
}
