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
