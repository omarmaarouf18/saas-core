import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/screens/update_required_screen.dart';

void main() {
  testWidgets('UpdateRequiredScreen renders version info and update button',
      (WidgetTester tester) async {
    bool updateClicked = false;

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: MaterialApp(
          home: UpdateRequiredScreen(
            currentVersion: '1.0.0',
            minimumVersion: '1.2.0',
            latestVersion: '1.3.0',
            downloadUrl: 'https://example.com/app.apk',
            onUpdatePressed: () {
              updateClicked = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('App Update Required'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('1.2.0'), findsOneWidget);
    expect(find.text('1.3.0'), findsOneWidget);
    final updateBtn = find.byKey(const Key('update_now_button'));
    expect(updateBtn, findsOneWidget);
    await tester.ensureVisible(updateBtn);
    await tester.pumpAndSettle();
    await tester.tap(updateBtn);
    await tester.pump();

    expect(updateClicked, isTrue);
  });
}
