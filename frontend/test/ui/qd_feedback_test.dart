import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_avatar.dart';
import 'package:frontend/ui/components/qd_banner.dart';
import 'package:frontend/ui/components/qd_bottom_sheet.dart';
import 'package:frontend/ui/components/qd_button.dart';
import 'package:frontend/ui/components/qd_states.dart';
import 'package:frontend/ui/tokens.dart';

import 'qd_harness.dart';

void main() {
  group('QdAvatarInitial', () {
    test('first character, upper-cased for Latin', () {
      expect(QdAvatarInitial.initialOf('عمر'), 'ع');
      expect(QdAvatarInitial.initialOf('  mona'), 'M');
      expect(QdAvatarInitial.initialOf('   '), '');
    });

    testWidgets('navy with gold letter; blank name shows an icon',
        (tester) async {
      await tester.pumpWidget(qdApp(const Row(children: [
        QdAvatarInitial(name: 'مندوب'),
        QdAvatarInitial(name: '', emphasis: false, size: 36),
      ])));
      expect(tester.widget<Text>(find.text('م')).style?.color,
          QdColors.light.onNavy);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });
  });

  group('QdSectionHeader', () {
    for (final locale in bothLocales) {
      testWidgets('title and action link [$locale]', (tester) async {
        var taps = 0;
        await tester.pumpWidget(qdApp(
            QdSectionHeader(
                title: 'Team now', actionLabel: 'All', onAction: () => taps++),
            locale: locale));
        await tester.tap(find.text('All'));
        expect(taps, 1);
        expect(
            tester
                .getSize(find.ancestor(
                    of: find.text('All'), matching: find.byType(InkWell)))
                .height,
            greaterThanOrEqualTo(48));
      });
    }
  });

  group('QdEmptyState / QdErrorState', () {
    testWidgets('empty state shows title, body, action', (tester) async {
      var taps = 0;
      await tester.pumpWidget(qdApp(QdEmptyState(
        icon: Icons.support_agent,
        title: 'No tickets',
        body: 'Need help? Open a ticket.',
        actionLabel: 'New ticket',
        onAction: () => taps++,
      )));
      expect(find.text('No tickets'), findsOneWidget);
      await tester.tap(find.text('New ticket'));
      expect(taps, 1);
    });

    for (final locale in bothLocales) {
      testWidgets('error state retries with default copy [$locale]',
          (tester) async {
        var retries = 0;
        await tester.pumpWidget(
            qdApp(QdErrorState(onRetry: () => retries++), locale: locale));
        final retry = locale == en ? 'Retry' : 'حاول تاني';
        expect(find.text(locale == en ? 'Something went wrong' : 'حصلت مشكلة'),
            findsOneWidget);
        await tester.tap(find.text(retry));
        expect(retries, 1);
      });
    }

    testWidgets('retrying disables the button', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
          qdApp(QdErrorState(onRetry: () => retries++, retrying: true)));
      await tester.tap(find.byType(QdButton));
      expect(retries, 0);
    });
  });

  group('QdBanner', () {
    for (final (tone, bg) in [
      (QdBannerTone.info, QdColors.light.fillMuted),
      (QdBannerTone.warning, QdColors.light.warningBg),
      (QdBannerTone.danger, QdColors.light.dangerBg),
    ]) {
      testWidgets('$tone fill, navy text, action', (tester) async {
        var taps = 0;
        await tester.pumpWidget(qdApp(QdBanner(
          tone: tone,
          message: 'Your documents are under review.',
          actionLabel: 'Finish upload',
          onAction: () => taps++,
        )));
        final box = tester.widget<Container>(find
            .descendant(
                of: find.byType(QdBanner), matching: find.byType(Container))
            .first);
        expect((box.decoration! as BoxDecoration).color, bg);
        expect(
            tester
                .widget<Text>(find.text('Your documents are under review.'))
                .style
                ?.color,
            QdColors.light.textPrimary);
        await tester.tap(find.text('Finish upload'));
        expect(taps, 1);
      });
    }
  });

  group('QdBottomSheet', () {
    for (final locale in bothLocales) {
      testWidgets('show: handle, title, content, one primary action [$locale]',
          (tester) async {
        var saved = 0;
        await tester.pumpWidget(qdApp(
          Builder(
            builder: (context) => QdButton.secondary(
              label: 'Open',
              onPressed: () => QdBottomSheet.show<void>(
                context,
                title: 'Add courier',
                subtitle: 'They get an email to set a password',
                primaryLabel: 'Add',
                onPrimary: () => saved++,
                child: const Text('form here'),
              ),
            ),
          ),
          locale: locale,
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Add courier'), findsOneWidget);
        expect(find.text('form here'), findsOneWidget);
        // The sheet has exactly one primary button.
        final primaries = tester
            .widgetList<QdButton>(find.descendant(
                of: find.byType(QdBottomSheet),
                matching: find.byType(QdButton)))
            .where((b) => b.variant == QdButtonVariant.primary);
        expect(primaries.length, 1);
        await tester.tap(find.text('Add'));
        expect(saved, 1);
      });
    }
  });
}
