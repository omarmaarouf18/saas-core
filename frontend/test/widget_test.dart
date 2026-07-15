import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/main.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/auth_provider.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(apiClient)),
        ],
        child: const MyApp(),
      ),
    );

    // Verify that the login screen elements render correctly.
    expect(find.text('Quick Delivery'), findsOneWidget);
    expect(find.text('Log in to manage your services'), findsOneWidget);
  });
}
