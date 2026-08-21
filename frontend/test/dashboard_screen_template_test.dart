import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/dashboard_screen_template.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders brand logo leading chrome with app_header_logo key',
      (tester) async {
    await tester.pumpWidget(_host(DashboardScreenTemplate(
      title: 'Dashboard',
      currentIndex: 0,
      onDestinationSelected: (_) {},
      tabs: const [Text('Tab0')],
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.work), label: 'Work'),
      ],
    )));

    expect(find.byKey(const Key('app_header_logo')), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('renders custom leading widget when provided', (tester) async {
    await tester.pumpWidget(_host(DashboardScreenTemplate(
      title: 'Dashboard',
      leading: const Icon(Icons.person),
      currentIndex: 0,
      onDestinationSelected: (_) {},
      tabs: const [Text('Tab0')],
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.work), label: 'Work'),
      ],
    )));

    expect(find.byKey(const Key('app_header_logo')), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('IndexedStack shows only selected tab and preserves others',
      (tester) async {
    await tester.pumpWidget(_host(DashboardScreenTemplate(
      title: 'Dashboard',
      currentIndex: 1,
      onDestinationSelected: (_) {},
      tabs: const [Text('Tab0'), Text('Tab1')],
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.work), label: 'Work'),
      ],
    )));

    expect(find.text('Tab1'), findsOneWidget);
    final indexedStack =
        tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(indexedStack.index, 1);
    expect(indexedStack.children.length, 2);
  });

  testWidgets('NavigationBar selection and callback wiring', (tester) async {
    int selected = 0;
    late StateSetter setter;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) {
        setter = setState;
        return DashboardScreenTemplate(
          title: 'Dashboard',
          currentIndex: selected,
          onDestinationSelected: (i) => setter(() => selected = i),
          navigationBarKey: const Key('test_nav_bar'),
          tabs: const [Text('Tab0'), Text('Tab1')],
          destinations: const [
            NavigationDestination(
                key: Key('tab_home'), icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
                key: Key('tab_work'), icon: Icon(Icons.work), label: 'Work'),
          ],
        );
      },
    )));

    expect(find.byKey(const Key('test_nav_bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab_work')));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('Tab1'), findsOneWidget);
  });
}
