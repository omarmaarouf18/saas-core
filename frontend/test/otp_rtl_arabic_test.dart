import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/otp_screen.dart';
import 'package:frontend/widgets/otp_pin_input.dart';

class _MockAuthProvider extends AuthProvider {
  _MockAuthProvider(super.apiClient);
  @override
  String? get token => 'test-token';
  @override
  UserProfile? get user => UserProfile(
        id: 'u-rtl',
        email: 'arabic.user@example.com',
        username: 'ArabicUser',
        role: 'user',
      );
}

void main() {
  group('OTP Arabic RTL Directionality & Rendering Tests', () {
    testWidgets(
        'OTP digit boxes render in strict LTR visual order under Arabic RTL locale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: quickDeliveryTheme,
          home: Scaffold(
            body: OtpPinInput(
              length: 6,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify that all 6 boxes are strictly ordered Left-to-Right by X coordinate
      final xCoords = <double>[];
      for (int i = 0; i < 6; i++) {
        final boxFinder = find.byKey(Key('otp_box_$i'));
        expect(boxFinder, findsOneWidget);
        final topLeft = tester.getTopLeft(boxFinder);
        xCoords.add(topLeft.dx);
      }

      for (int i = 0; i < 5; i++) {
        expect(
          xCoords[i],
          lessThan(xCoords[i + 1]),
          reason:
              'Box $i (x=${xCoords[i]}) must be to the left of Box ${i + 1} (x=${xCoords[i + 1]})',
        );
      }
    });

    testWidgets(
        'OTP typing in Arabic locale enters leftmost box and auto-advances rightward',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String enteredOtp = '';
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: quickDeliveryTheme,
          home: Scaffold(
            body: OtpPinInput(
              length: 6,
              autoFocus: true,
              onChanged: (val) => enteredOtp = val,
            ),
          ),
        ),
      );
      await tester.pump();

      // Enter digit 1 into box 0
      await tester.enterText(find.byKey(const Key('otp_box_0')), '1');
      await tester.pump();

      expect(enteredOtp, equals('1'));

      // Auto-advance should focus box 1 (to the right of box 0)
      final box1Widget =
          tester.widget<TextField>(find.byKey(const Key('otp_box_1')));
      expect(box1Widget.focusNode?.hasFocus, isTrue);

      // Enter digit 2 into box 1
      await tester.enterText(find.byKey(const Key('otp_box_1')), '2');
      await tester.pump();

      expect(enteredOtp, equals('12'));
    });

    testWidgets(
        'OtpScreen renders email with LTR text direction under Arabic locale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = ApiClient();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
                value: _MockAuthProvider(api)),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: quickDeliveryTheme,
            home: const OtpScreen(email: 'arabic.user@example.com'),
          ),
        ),
      );
      await tester.pump();

      final emailFinder = find.text('arabic.user@example.com');
      expect(emailFinder, findsOneWidget);
      final emailText = tester.widget<Text>(emailFinder);
      expect(emailText.textDirection, equals(TextDirection.ltr));
    });

    testWidgets(
        'OtpPinInput uses theme primary color in dark mode (contrast fix)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: quickDeliveryTheme,
          darkTheme: quickDeliveryDarkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: OtpPinInput(
              length: 6,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final box0Widget =
          tester.widget<TextField>(find.byKey(const Key('otp_box_0')));
      // In dark mode, colorScheme.primary is Amber Gold 0xFFFFC107 (not static Navy #0D1321)
      expect(box0Widget.style?.color,
          equals(quickDeliveryDarkTheme.colorScheme.primary));
    });
  });
}
