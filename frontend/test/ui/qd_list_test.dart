import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_avatar.dart';
import 'package:frontend/ui/components/qd_card.dart';
import 'package:frontend/ui/components/qd_list.dart';
import 'package:frontend/ui/components/qd_status_chip.dart';
import 'package:frontend/ui/tokens.dart';

import 'qd_harness.dart';

void main() {
  testWidgets('QdCard: border, no shadow, tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
        qdApp(QdCard(onTap: () => taps++, child: const Text('Order'))));
    await tester.tap(find.text('Order'));
    expect(taps, 1);
    final m = tester.widget<Material>(find
        .descendant(of: find.byType(QdCard), matching: find.byType(Material))
        .first);
    expect(m.elevation, 0);
    final shape = m.shape! as RoundedRectangleBorder;
    expect(shape.side.color, QdColors.light.border);
    expect(shape.borderRadius, BorderRadius.circular(QdRadius.card));
  });

  testWidgets('QdCard subtle uses the subtle fill', (tester) async {
    await tester.pumpWidget(
        qdApp(const QdCard(subtle: true, child: Text('Current order'))));
    final m = tester.widget<Material>(find
        .descendant(of: find.byType(QdCard), matching: find.byType(Material))
        .first);
    expect(m.color, QdColors.light.fillSubtle);
  });

  for (final locale in bothLocales) {
    testWidgets('group: dividers inset to the title column [$locale]',
        (tester) async {
      await tester.pumpWidget(qdApp(
        const QdListGroup(children: [
          QdListTile(
              icon: Icons.place_outlined,
              title: 'Saved addresses',
              chevron: true),
          QdListTile(
              icon: Icons.lock_outline, title: 'Security', value: '2FA on'),
          QdListTile(
            leading: QdAvatarInitial(name: 'Mona', size: 40, emphasis: false),
            title: 'Mona',
            subtitle: 'On a job',
            badge: QdStatusChip(label: 'Busy', tone: QdTone.warning),
          ),
          QdListTile(title: 'Last row'),
        ]),
        locale: locale,
      ));
      final dividers = find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxHeight == 1);
      expect(dividers, findsNWidgets(3));
      // The divider's own Padding is its nearest Padding ancestor.
      final insets = [
        for (final d in tester.widgetList(dividers))
          (tester
                  .widget<Padding>(find
                      .ancestor(
                          of: find.byWidget(d), matching: find.byType(Padding))
                      .first)
                  .padding as EdgeInsetsDirectional)
              .start,
      ];
      expect(insets, [14 + 20 + 12, 14 + 20 + 12, 16 + 40 + 12]);
      for (final tile in tester.widgetList(find.byType(QdListTile))) {
        expect(tester.getSize(find.byWidget(tile)).height,
            greaterThanOrEqualTo(48));
      }
    });
  }

  testWidgets('tile trailing: value, chevron, badge', (tester) async {
    await tester.pumpWidget(qdApp(
      const QdListGroup(children: [
        QdListTile(title: 'Language', value: 'العربية', chevron: true),
        QdListTile(
            title: 'Wallet',
            enabled: false,
            badge: QdStatusChip(label: 'Coming soon', tone: QdTone.neutral)),
      ]),
      locale: en,
    ));
    expect(find.text('العربية'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Wallet')).style?.color,
        QdColors.light.textSecondary);
  });

  testWidgets('switch row toggles from the row and the switch', (tester) async {
    var value = true;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => qdApp(QdListGroup(children: [
        QdListTile(
          icon: Icons.notifications_none,
          title: 'Notifications',
          switchValue: value,
          onSwitchChanged: (v) => setState(() => value = v),
        ),
      ])),
    ));
    await tester.tap(find.text('Notifications'));
    await tester.pump();
    expect(value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(value, isTrue);
  });

  testWidgets('tap row; disabled row ignores taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(qdApp(QdListGroup(children: [
      QdListTile(title: 'Support', chevron: true, onTap: () => taps++),
      QdListTile(title: 'Wallet', enabled: false, onTap: () => taps++),
    ])));
    await tester.tap(find.text('Support'));
    await tester.tap(find.text('Wallet'));
    expect(taps, 1);
  });
}
