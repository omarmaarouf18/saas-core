import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import 'auth_forms.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/otp_code_form.dart';

/// Password reset (ADR-0026, two-phase), one page in three steps on the
/// sign-in components: email → code → new password.
///
/// Behaviour kept from ForgotPassword / ResetPasswordOtp / ResetPasswordNew:
/// the code request (forgotPassword) with the development code filled in,
/// code verification (verifyResetCode) that arms the single-use reset
/// token, resend through the same request, a 429 lockout shown without
/// retry, the new password checked locally (SEC-03 length, both fields
/// equal), a missing or expired token (401) explained with a way back to
/// step 1, the server's `weak_password` reason localized, and on success a
/// notice and back to sign in. The page completes with the email so sign
/// in can prefill it.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  int _step = 0;
  String? _devOtp;

  /// New code form per code request, so a restart starts clean.
  int _codeRound = 0;
  bool _busy = false;
  bool _missingToken = false;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _emailValue => _email.text.trim();

  void _goTo(int step) {
    context.read<AuthProvider>().clearError();
    setState(() {
      _step = step;
      _missingToken = false;
      _passwordError = null;
      _confirmError = null;
    });
  }

  void _back() {
    if (_step == 0) {
      context.read<AuthProvider>().clearError();
      Navigator.of(context).maybePop();
    } else {
      // Step 3 goes back to the code like the old screens did.
      _goTo(_step - 1);
    }
  }

  Future<void> _requestCode() async {
    if (_busy) return;
    final error = validateEmail(context.l10n, _email.text);
    setState(() => _emailError = error);
    if (error != null) return;
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    final dev = await auth.forgotPassword(_emailValue);
    if (!mounted) return;
    setState(() => _busy = false);
    if (auth.error != null) return; // banner
    showAuthNotice(context, context.l10n.resetCodeSent);
    setState(() {
      _devOtp = dev;
      _codeRound++;
      _step = 1;
    });
  }

  Future<OtpOutcome> _verify(String code) async {
    final auth = context.read<AuthProvider>();
    final token = await auth.verifyResetCode(_emailValue, code);
    if (!mounted) return const OtpOutcome.success();
    if (token == null || token.isEmpty || auth.error != null) {
      return OtpOutcome.failure(
        authErrorText(context.l10n, auth) ?? ErrorMessages.genericFallback,
        // A lockout's text carries the wait; retrying extends it.
        retryable: auth.lastErrorStatusCode != 429,
      );
    }
    _goTo(2);
    return const OtpOutcome.success();
  }

  Future<OtpOutcome> _resend() async {
    final auth = context.read<AuthProvider>();
    final dev = await auth.forgotPassword(_emailValue);
    if (auth.error != null) {
      return OtpOutcome.failure(
          (mounted ? authErrorText(context.l10n, auth) : null) ?? auth.error!);
    }
    return OtpOutcome.success(devOtp: dev);
  }

  Future<void> _save() async {
    if (_busy) return;
    final l10n = context.l10n;
    final auth = context.read<AuthProvider>();
    setState(() {
      _passwordError = validateNewPassword(l10n, _password.text);
      _confirmError = _confirm.text.isEmpty
          ? l10n.authPasswordRequired
          : (_confirm.text != _password.text ? l10n.resetMismatch : null);
    });
    if (_passwordError != null || _confirmError != null) return;
    auth.clearError();
    final token = auth.resetToken;
    if (token == null || token.isEmpty) {
      setState(() => _missingToken = true);
      return;
    }
    setState(() {
      _missingToken = false;
      _busy = true;
    });
    final ok = await auth.resetPassword(_emailValue, token, _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok || auth.error != null) return; // banner
    showAuthNotice(context, l10n.resetDone);
    Navigator.of(context).pop(_emailValue);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AuthScaffold(
        onBack: _back,
        children: [
          const SizedBox(height: QdSpace.x3),
          _StepLabel(step: _step),
          const SizedBox(height: QdSpace.x5),
          ...switch (_step) {
            0 => _emailStep(context),
            1 => _codeStep(context),
            _ => _passwordStep(context),
          },
        ],
      ),
    );
  }

  List<Widget> _emailStep(BuildContext context) {
    final l10n = context.l10n;
    final error = authErrorText(l10n, context.watch<AuthProvider>());
    return [
      AuthHeading(title: l10n.resetTitle, subtitle: l10n.resetEmailBody),
      const SizedBox(height: 28),
      if (error != null) ...[
        QdBanner(
          key: const Key('reset_email_error'),
          tone: QdBannerTone.danger,
          icon: Icons.error_outline,
          message: error,
          actionLabel: l10n.retry,
          onAction: _requestCode,
        ),
        const SizedBox(height: QdSpace.x4),
      ],
      QdTextField(
        key: const Key('reset_email'),
        label: l10n.authEmailLabel,
        hint: l10n.authEmailHint,
        controller: _email,
        ltr: true,
        errorText: _emailError,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _requestCode(),
        onChanged: (_) {
          if (_emailError != null) setState(() => _emailError = null);
        },
      ),
      const SizedBox(height: QdSpace.x6),
      QdButton(
        key: const Key('reset_send_code'),
        label: l10n.resetSendCode,
        loading: _busy,
        fullWidth: true,
        onPressed: _requestCode,
      ),
    ];
  }

  List<Widget> _codeStep(BuildContext context) {
    final l10n = context.l10n;
    return [
      AuthHeading(
        title: l10n.authOtpTitle,
        subtitle: l10n.authOtpSentTo,
        emphasis: _emailValue,
      ),
      const SizedBox(height: QdSpace.x6),
      OtpCodeForm(
        key: ValueKey('reset_code_$_codeRound'),
        devOtp: _devOtp,
        onVerify: _verify,
        onResend: _resend,
      ),
    ];
  }

  List<Widget> _passwordStep(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();
    // A 401 means the held token is dead (or was never armed): explain
    // the restart instead of retrying.
    final expired = _missingToken || auth.lastErrorStatusCode == 401;
    final error = expired ? l10n.resetExpired : authErrorText(l10n, auth);
    return [
      AuthHeading(title: l10n.resetNewTitle, subtitle: l10n.resetNewBody),
      const SizedBox(height: 28),
      if (error != null) ...[
        QdBanner(
          key: Key(expired ? 'reset_expired' : 'reset_save_error'),
          tone: QdBannerTone.danger,
          icon: Icons.error_outline,
          message: error,
          actionLabel: expired ? l10n.resetStartAgain : l10n.retry,
          onAction: expired ? () => _goTo(0) : _save,
        ),
        const SizedBox(height: QdSpace.x4),
      ],
      QdTextField(
        key: const Key('reset_new_password'),
        label: l10n.resetNewLabel,
        controller: _password,
        obscure: true,
        errorText: _passwordError,
        helperText: l10n.authPasswordHelp,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.newPassword],
        onChanged: (_) {
          if (_passwordError != null) setState(() => _passwordError = null);
        },
      ),
      const SizedBox(height: QdSpace.x4),
      QdTextField(
        key: const Key('reset_confirm_password'),
        label: l10n.resetConfirmLabel,
        controller: _confirm,
        obscure: true,
        errorText: _confirmError,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        onChanged: (_) {
          if (_confirmError != null) setState(() => _confirmError = null);
        },
      ),
      const SizedBox(height: QdSpace.x6),
      QdButton(
        key: const Key('reset_save'),
        label: l10n.resetSave,
        loading: _busy,
        fullWidth: true,
        onPressed: _save,
      ),
    ];
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.resetStep(step + 1, 3),
          key: const Key('reset_step'),
          style: QdText.caption.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: QdSpace.x2),
        ExcludeSemantics(child: QdStepProgress(total: 3, current: step)),
      ],
    );
  }
}
