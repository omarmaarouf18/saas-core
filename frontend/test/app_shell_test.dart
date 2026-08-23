import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/widgets/app_shell.dart';

void main() {
  Widget buildTestWidget({
    String? title,
    String? subtitle,
    Widget? titleWidget,
    Widget? leading,
    bool? showBackButton,
    VoidCallback? onBackPressed,
    List<Widget>? actions,
    required Widget body,
    PreferredSizeWidget? customAppBar,
    PreferredSizeWidget? bottom,
    Widget? bottomNavigationBar,
    Widget? floatingActionButton,
    bool isEmbeddedInTab = false,
    bool useSafeArea = true,
    EdgeInsetsGeometry? padding,
    ThemeData? theme,
  }) {
    return MaterialApp(
      theme: theme ?? quickDeliveryTheme,
      home: AppShell(
        title: title,
        subtitle: subtitle,
        titleWidget: titleWidget,
        leading: leading,
        showBackButton: showBackButton,
        onBackPressed: onBackPressed,
        actions: actions,
        body: body,
        customAppBar: customAppBar,
        bottom: bottom,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
        isEmbeddedInTab: isEmbeddedInTab,
        useSafeArea: useSafeArea,
        padding: padding,
      ),
    );
  }

  group('AppShell Standalone Widget Tests', () {
    testWidgets('renders title, subtitle, and body without error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          title: 'Dashboard Overview',
          subtitle: 'Operational Status: Active',
          body: const Text('Dashboard Body Content'),
        ),
      );

      expect(find.text('Dashboard Overview'), findsOneWidget);
      expect(find.text('Operational Status: Active'), findsOneWidget);
      expect(find.text('Dashboard Body Content'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Dashboard Body Content'),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders back button and triggers callback on tap',
        (WidgetTester tester) async {
      bool backPressed = false;
      await tester.pumpWidget(
        buildTestWidget(
          title: 'Details Screen',
          showBackButton: true,
          onBackPressed: () => backPressed = true,
          body: const Text('Details Content'),
        ),
      );

      final backBtn = find.byIcon(Icons.arrow_back);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();
      expect(backPressed, isTrue);
    });

    testWidgets('renders custom leading widget and actions',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          title: 'Menu Screen',
          leading: const Icon(Icons.menu, key: Key('custom_leading_icon')),
          actions: [
            IconButton(
              key: const Key('action_search'),
              icon: const Icon(Icons.search),
              onPressed: () {},
            ),
            IconButton(
              key: const Key('action_settings'),
              icon: const Icon(Icons.settings),
              onPressed: () {},
            ),
          ],
          body: const Text('Menu Content'),
        ),
      );

      expect(find.byKey(const Key('custom_leading_icon')), findsOneWidget);
      expect(find.byKey(const Key('action_search')), findsOneWidget);
      expect(find.byKey(const Key('action_settings')), findsOneWidget);
    });

    testWidgets('isEmbeddedInTab omits top AppBar and bottom navigation chrome',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          title: 'Embedded Tab Screen',
          isEmbeddedInTab: true,
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
          body: const Text('Embedded Tab Content'),
        ),
      );

      expect(find.text('Embedded Tab Content'), findsOneWidget);
      expect(find.text('Embedded Tab Screen'), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('renders TabBar inside AppBar bottom slot',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: quickDeliveryTheme,
          home: const DefaultTabController(
            length: 3,
            child: AppShell(
              title: 'Tabbed View',
              bottom: TabBar(
                tabs: [
                  Tab(text: 'Activity'),
                  Tab(text: 'Orders'),
                  Tab(text: 'Ledger'),
                ],
              ),
              body: TabBarView(
                children: [
                  Text('Activity Content'),
                  Text('Orders Content'),
                  Text('Ledger Content'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('Activity Content'), findsOneWidget);
    });

    testWidgets('renders floatingActionButton and bottomNavigationBar',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          title: 'Main Navigation',
          floatingActionButton: FloatingActionButton(
            key: const Key('add_fab'),
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
          bottomNavigationBar: NavigationBar(
            key: const Key('app_bottom_bar'),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
          body: const Text('Nav Content'),
        ),
      );

      expect(find.byKey(const Key('add_fab')), findsOneWidget);
      expect(find.byKey(const Key('app_bottom_bar')), findsOneWidget);
    });

    testWidgets(
        'applies standard AppSpacing padding and SafeArea when requested',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          title: 'Padded Screen',
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.marginMobile,
            vertical: AppSpacing.lg,
          ),
          useSafeArea: true,
          body: const Text('Padded Content'),
        ),
      );

      final paddingWidget = tester.widget<Padding>(
        find
            .ancestor(
              of: find.text('Padded Content'),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(
        paddingWidget.padding,
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.marginMobile,
          vertical: AppSpacing.lg,
        ),
      );
      expect(
        find.ancestor(
          of: find.text('Padded Content'),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
    });
  });
}
