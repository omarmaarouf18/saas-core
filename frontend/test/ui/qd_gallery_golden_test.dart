import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/gallery/qd_gallery_screen.dart';
import 'package:frontend/ui/qd_theme.dart';
import 'package:frontend/ui/tokens.dart';

import 'qd_harness.dart';

// Golden snapshots of every redesign A gallery section at 360x800, light,
// AR-RTL and EN-LTR (FE-DS). Unlike test/golden_screens_test.dart (Ahem),
// these load the bundled IBM Plex Sans Arabic so Arabic shaping and RTL
// layout are reviewable. Icons render as test-font boxes (MaterialIcons is
// not loaded, same as the screen goldens).
//
// Regenerate after an intentional change, with the CI Flutter version
// (.github/workflows/ci.yml `flutter-version:`):
//   flutter test --update-goldens test/ui/qd_gallery_golden_test.dart

final DateTime _fixedNow = DateTime(2026, 10, 19, 12);

Future<void> _loadPlex() async {
  final loader = FontLoader(kQdFontFamily);
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes =
        File('assets/fonts/IBMPlexSansArabic-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Widget _sectionApp(QdGallerySection section, Locale locale) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: qdLightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              QdSpace.gutter, QdSpace.x6, QdSpace.gutter, QdSpace.x6),
          child: QdGallerySectionView(section),
        ),
      ),
    );

void main() {
  setUpAll(_loadPlex);

  final sections = qdGallerySections(now: () => _fixedNow);

  for (final section in sections) {
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN qd gallery ${section.id} $dir', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_sectionApp(section, locale));
        // Advance fake time so the loading spinner shows an arc, not a dot.
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              'goldens/qd_gallery_${section.id}_${dir}_360x800.png'),
        );
        // Stop the countdown timers before the test ends.
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final locale in bothLocales) {
    for (final dark in [false, true]) {
      testWidgets('gallery screen builds every section [$locale, dark: $dark]',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QdGalleryScreen(now: () => _fixedNow),
        ));
        if (dark) {
          await tester.tap(find.byTooltip('Dark'));
          await tester.pump();
        }
        for (final s in sections) {
          await tester.scrollUntilVisible(find.text(s.title), 300,
              scrollable: find.byType(Scrollable).first);
          expect(find.text(s.title), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
