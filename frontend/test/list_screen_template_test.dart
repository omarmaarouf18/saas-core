import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/widgets/list_screen_template.dart';
import 'package:frontend/widgets/themed_empty_state.dart';
import 'package:frontend/widgets/themed_error_banner.dart';
import 'package:frontend/widgets/themed_loading_indicator.dart';

void main() {
  Widget buildTestListScreen<T>({
    String? title,
    required List<T>? items,
    bool isLoading = false,
    String? errorMessage,
    VoidCallback? onRetry,
    Future<void> Function()? onRefresh,
    Widget? header,
    Widget? footer,
    Widget Function(BuildContext context, T item, int index)? itemBuilder,
    String emptyTitle = 'No items found',
    String emptyDescription = 'There are no items to display at this time.',
    String? emptyActionText,
    VoidCallback? onEmptyActionPressed,
  }) {
    return MaterialApp(
      theme: quickDeliveryTheme,
      home: ListScreenTemplate<T>(
        title: title,
        items: items,
        isLoading: isLoading,
        errorMessage: errorMessage,
        onRetry: onRetry,
        onRefresh: onRefresh,
        header: header,
        footer: footer,
        itemBuilder: itemBuilder,
        emptyTitle: emptyTitle,
        emptyDescription: emptyDescription,
        emptyActionText: emptyActionText,
        onEmptyActionPressed: onEmptyActionPressed,
      ),
    );
  }

  group('ListScreenTemplate Standalone Tests', () {
    testWidgets('renders loaded state with fake items list and spacing',
        (WidgetTester tester) async {
      final fakeItems = ['Order #QD-101', 'Order #QD-102', 'Order #QD-103'];

      await tester.pumpWidget(
        buildTestListScreen<String>(
          title: 'All Shipments',
          items: fakeItems,
          itemBuilder: (context, item, index) => Container(
            key: Key('item_$index'),
            child: Text(item),
          ),
        ),
      );

      expect(find.text('All Shipments'), findsOneWidget);
      expect(find.text('Order #QD-101'), findsOneWidget);
      expect(find.text('Order #QD-102'), findsOneWidget);
      expect(find.text('Order #QD-103'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets(
        'renders loading state when isLoading is true and items is empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestListScreen<String>(
          title: 'Shipments Loading',
          items: const [],
          isLoading: true,
        ),
      );

      expect(find.byType(ThemedLoadingIndicator), findsOneWidget);
      expect(
          find.byKey(const ValueKey('list_template_loading')), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets(
        'renders error state with retry callback when errorMessage is present and items is empty',
        (WidgetTester tester) async {
      bool retryTriggered = false;

      await tester.pumpWidget(
        buildTestListScreen<String>(
          title: 'Shipments Error',
          items: const [],
          errorMessage: 'Failed to load shipments: Network error',
          onRetry: () => retryTriggered = true,
        ),
      );

      expect(find.byType(ThemedErrorBanner), findsOneWidget);
      expect(
        find.text('Failed to load shipments: Network error'),
        findsOneWidget,
      );

      final retryBtn = find.text('Retry');
      expect(retryBtn, findsOneWidget);
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();
      expect(retryTriggered, isTrue);
    });

    testWidgets('renders empty state when items list is empty and not loading',
        (WidgetTester tester) async {
      bool emptyActionTriggered = false;

      await tester.pumpWidget(
        buildTestListScreen<String>(
          title: 'Empty Screen',
          items: const [],
          emptyTitle: 'No Orders Found',
          emptyDescription: 'You do not have any past orders in your ledger.',
          emptyActionText: 'Create Order',
          onEmptyActionPressed: () => emptyActionTriggered = true,
        ),
      );

      expect(find.byType(ThemedEmptyState), findsOneWidget);
      expect(find.text('No Orders Found'), findsOneWidget);
      expect(
        find.text('You do not have any past orders in your ledger.'),
        findsOneWidget,
      );

      final actionBtn = find.text('Create Order');
      expect(actionBtn, findsOneWidget);
      await tester.tap(actionBtn);
      await tester.pumpAndSettle();
      expect(emptyActionTriggered, isTrue);
    });

    testWidgets('renders custom header and footer widgets alongside the list',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestListScreen<String>(
          title: 'Header & Footer List',
          header: const Text('Pinned Filter Bar', key: Key('pinned_header')),
          footer: const Text('Summary Footnote', key: Key('summary_footer')),
          items: const ['Single Item'],
          itemBuilder: (context, item, index) => Text(item),
        ),
      );

      expect(find.byKey(const Key('pinned_header')), findsOneWidget);
      expect(find.text('Single Item'), findsOneWidget);
      expect(find.byKey(const Key('summary_footer')), findsOneWidget);
    });

    testWidgets('wraps loaded list in RefreshIndicator when onRefresh provided',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestListScreen<String>(
          title: 'Refreshable List',
          items: const ['Item 1', 'Item 2'],
          onRefresh: () async {},
          itemBuilder: (context, item, index) => Text(item),
        ),
      );

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
    });
  });
}
