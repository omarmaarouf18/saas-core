import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/widgets/app_shell.dart';

Widget _buildTestApp({
  required Widget child,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: quickDeliveryTheme,
    darkTheme: quickDeliveryDarkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: child,
  );
}

void main() {
  group('AppShell Chrome Option C Auto-Inference', () {
    testWidgets(
        'auto-infers transparent chrome when showBackButton is false (tab root)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        child: const AppShell(
          title: 'Tab Root Screen',
          showBackButton: false,
          body: SizedBox.expand(),
        ),
      ));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, equals(Colors.transparent));
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(appBar.foregroundColor, equals(theme.colorScheme.onSurface));
      expect(appBar.bottom, isNull);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets(
        'auto-infers surfaceElevated chrome when showBackButton is true (detail screen)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        child: const AppShell(
          title: 'Detail Screen',
          showBackButton: true,
          body: SizedBox.expand(),
        ),
      ));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(appBar.backgroundColor, equals(theme.colorScheme.surface));
      expect(appBar.foregroundColor, equals(theme.colorScheme.onSurface));
      expect(appBar.bottom, isNotNull);
      expect(appBar.bottom!.preferredSize.height, equals(1.0));

      final backButton = find.byType(IconButton);
      expect(backButton, findsOneWidget);
    });

    testWidgets(
        'auto-infers surfaceElevated when pushed onto navigation stack (canPop is true)',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: quickDeliveryTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AppShell(
                        title: 'Pushed Detail Screen',
                        body: SizedBox.expand(),
                      ),
                    ),
                  );
                },
                child: const Text('Open Detail'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Tap to push detail screen
      await tester.tap(find.text('Open Detail'));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(appBar.backgroundColor, equals(theme.colorScheme.surface));
      expect(appBar.foregroundColor, equals(theme.colorScheme.onSurface));
      expect(appBar.bottom, isNotNull);
      expect(appBar.bottom!.preferredSize.height, equals(1.0));
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('explicit chromeStyle brandNavy overrides auto-inference',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        child: const AppShell(
          title: 'Payment Prominent Screen',
          showBackButton: true,
          chromeStyle: AppShellChromeStyle.brandNavy,
          body: SizedBox.expand(),
        ),
      ));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, equals(AppColors.primary));
      expect(appBar.foregroundColor, equals(AppColors.onPrimary));
      expect(appBar.bottom, isNull);
    });

    testWidgets('explicit chromeStyle transparent overrides detail backButton',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        child: const AppShell(
          title: 'Transparent Detail Screen',
          showBackButton: true,
          chromeStyle: AppShellChromeStyle.transparent,
          body: SizedBox.expand(),
        ),
      ));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(appBar.backgroundColor, equals(Colors.transparent));
      expect(appBar.foregroundColor, equals(theme.colorScheme.onSurface));
      expect(appBar.bottom, isNull);
    });

    testWidgets(
        'dark theme surfaceElevated adapts surface and foreground colors',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(
        brightness: Brightness.dark,
        child: const AppShell(
          title: 'Dark Mode Detail Screen',
          showBackButton: true,
          body: SizedBox.expand(),
        ),
      ));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(appBar.backgroundColor, equals(theme.colorScheme.surface));
      expect(appBar.foregroundColor, equals(theme.colorScheme.onSurface));
      expect(appBar.backgroundColor, equals(const Color(0xFF0F172A)));
      expect(appBar.bottom, isNotNull);
    });
  });
}
