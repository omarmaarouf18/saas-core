import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import 'auth_forms.dart';
import 'auth_nav.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/otp_code_form.dart';

/// Code entry after sign-in (2FA) or sign-up (A-OTP).
///
/// Behaviour kept from OtpScreen: the development code is filled in with a
/// banner when the server returned one (also after a resend), a full code
/// verifies on its own, verify and resend failures each get their own
/// retry, a resend success says so, and success replaces the stack with
/// the home screen. New: a 60 s countdown before resend is offered.
///
/// The same page serves the 2FA sign-in challenge (from the login page)
/// and sign-up; "send it again" calls `POST /auth/resend-otp`, which since
/// USER-AUTH-BE item 6 resends the login challenge code too (it said "no
/// pending registration" before). A 429 shows the wait in the app
/// language and restarts the countdown with it (FE-BE-GAPS).
/// The seconds of a lockout message ("... try again in 60 seconds."), or
/// null when it has none.
int? lockoutSeconds(String message) {
  final m = RegExp(r'(\d+)\s*seconds?').firstMatch(message);
  return m == null ? null : int.tryParse(m.group(1)!);
}

class OtpPage extends StatelessWidget {
  const OtpPage({super.key, required this.email, this.devOtp});

  final String email;
  final String? devOtp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.read<AuthProvider>();
    final nav = AuthNavScope.of(context);

    Future<OtpOutcome> verify(String code) async {
      final ok = await auth.verifyOtp(email, code);
      if (ok && context.mounted) {
        await nav.goHome(context);
        return const OtpOutcome.success();
      }
      return OtpOutcome.failure(
        (context.mounted ? authErrorText(context.l10n, auth) : null) ??
            ErrorMessages.genericFallback,
      );
    }

    Future<OtpOutcome> resend() async {
      final dev = await auth.resendOtp(email);
      if (auth.error != null) {
        if (auth.lastErrorStatusCode == 429) {
          // Too many sends for this email or device: no retry button (it
          // only extends the lockout); the countdown waits it out.
          final wait = lockoutSeconds(auth.lastErrorReason ?? auth.error!);
          return OtpOutcome.failure(
              context.mounted
                  ? (wait == null
                      ? context.l10n.authResendTooManyNoTime
                      : context.l10n.authResendTooMany(wait))
                  : auth.error!,
              retryable: false,
              waitSeconds: wait);
        }
        return OtpOutcome.failure(
            (context.mounted ? authErrorText(context.l10n, auth) : null) ??
                auth.error!);
      }
      return OtpOutcome.success(devOtp: dev);
    }

    return AuthScaffold(
      onBack: () {
        auth.clearError();
        Navigator.of(context).maybePop();
      },
      children: [
        const SizedBox(height: QdSpace.x6),
        AuthHeading(
          title: l10n.authOtpTitle,
          subtitle: l10n.authOtpSentTo,
          emphasis: email,
        ),
        const SizedBox(height: QdSpace.x6),
        OtpCodeForm(
          key: const Key('otp_form'),
          devOtp: devOtp,
          onVerify: verify,
          onResend: resend,
        ),
      ],
    );
  }
}
