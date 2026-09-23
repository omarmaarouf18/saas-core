import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/otp_screen.dart';
import 'package:frontend/widgets/otp_pin_input.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';

/// Mock that pins the loading spinner off: the real [AuthProvider]
/// constructor fires `_tryAutoLogin()` (secure-storage read), which leaves
/// `isLoading == true` for the first frames and swaps both action buttons
/// for spinners. Pinning it off keeps button-label assertions deterministic
/// without touching any OTP-entry/resend/verify logic.
class _StillAuthProvider extends AuthProvider {
  _StillAuthProvider(super.apiClient);

  @override
  bool get isLoading => false;
}

/// Visual-redesign regression tests for [OtpScreen]:
/// - QD brand logo renders above the verification card.
/// - Non-interactive professional footer renders at the bottom.
/// - OTP-entry / resend / verify behavior is unchanged.
Widget _buildRedesignTestApp({
  required Widget child,
  Locale locale = const Locale('en'),
}) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _StillAuthProvider(apiClient),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: quickDeliveryTheme,
      home: child,
    ),
  );
}

void main() {
  group('OtpScreen Visual Redesign Tests', () {
    testWidgets('QD logo renders centered above the verification card',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildRedesignTestApp(
        child: const OtpScreen(email: 'test@example.com'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final logoFinder = find.byKey(const Key('otp_qd_logo'));
      expect(logoFinder, findsOneWidget);

      final logoWidget = tester.widget<SvgPicture>(logoFinder);
      expect(logoWidget.bytesLoader, isA<SvgAssetLoader>());
      expect(
        (logoWidget.bytesLoader as SvgAssetLoader).assetName,
        'assets/branding/qd_logo.svg',
      );

      // Logo must sit above the card headline in vertical order.
      final logoTop = tester.getTopLeft(logoFinder).dy;
      final titleTop =
          tester.getTopLeft(find.text('Two-Factor Verification')).dy;
      expect(logoTop, lessThan(titleTop));
    });

    testWidgets('Non-interactive footer renders brand + reassurance lines',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildRedesignTestApp(
        child: const OtpScreen(email: 'test@example.com'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('otp_screen_footer')), findsOneWidget);
      expect(find.text('Quick Delivery'), findsOneWidget);
      expect(
        find.text('Never share your verification code with anyone.'),
        findsOneWidget,
      );

      // Footer must sit below the action buttons.
      final footerTop =
          tester.getTopLeft(find.byKey(const Key('otp_screen_footer'))).dy;
      final resendTop =
          tester.getTopLeft(find.byKey(const Key('otp_resend_button'))).dy;
      expect(footerTop, greaterThan(resendTop));
    });

    testWidgets('Footer renders Egyptian Arabic copy under ar locale',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildRedesignTestApp(
        locale: const Locale('ar'),
        child: const OtpScreen(email: 'test@example.com'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('otp_screen_footer')), findsOneWidget);
      expect(
        find.text('متشاركش كود التحقق بتاعك مع أي حد.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'OTP-entry, resend and verify affordances are unchanged by redesign',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildRedesignTestApp(
        child: const OtpScreen(email: 'test@example.com'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Headline / instructions still present.
      expect(find.text('Two-Factor Verification'), findsOneWidget);
      expect(
        find.text('Enter the 6-digit code sent to your email'),
        findsOneWidget,
      );
      expect(find.text('test@example.com'), findsOneWidget);

      // 6 discrete PIN boxes still present.
      expect(find.byType(OtpPinInput), findsOneWidget);
      for (int i = 0; i < 6; i++) {
        expect(find.byKey(Key('otp_box_$i')), findsOneWidget);
      }

      // Verify + resend buttons still present with handlers attached.
      expect(find.text('VERIFY CODE'), findsOneWidget);
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
          isNotNull);
      final resendFinder = find.byKey(const Key('otp_resend_button'));
      expect(resendFinder, findsOneWidget);
      expect(tester.widget<SecondaryButton>(resendFinder).onPressed, isNotNull);
    });

    testWidgets('Verify with incomplete code still shows validation error',
        (WidgetTester tester) async {
      await tester.pumpWidget(_buildRedesignTestApp(
        child: const OtpScreen(email: 'test@example.com'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('VERIFY CODE'));
      await tester.pump();

      expect(find.text('OTP must be exactly 6 digits'), findsOneWidget);
    });
  });
}
