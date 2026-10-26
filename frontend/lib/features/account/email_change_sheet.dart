import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import '../auth/auth_forms.dart';
import '../auth/widgets/otp_code_form.dart';
import 'account_nav.dart';

/// Email change in two steps: the new email (a code is sent there), then
/// the code on the A-OTP boxes.
///
/// Behaviour kept from EmailChangeDialog: an outside tap or drag never
/// closes it (the step-1 email would be lost), the close button is off
/// while a request runs, the development code is filled in with a banner,
/// errors show the provider's message, and success (which swaps the
/// session token in the provider) closes with a notice. New: resend after
/// the countdown (the same request again) and a check that the new email
/// differs from the current one.
class EmailChangeSheet extends StatefulWidget {
  const EmailChangeSheet({super.key});

  static Future<void> show(BuildContext context) {
    final c = QdColors.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: c.surface,
      barrierColor: c.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: const EmailChangeSheet(),
      ),
    );
  }

  @override
  State<EmailChangeSheet> createState() => _EmailChangeSheetState();
}

class _EmailChangeSheetState extends State<EmailChangeSheet> {
  final _email = TextEditingController();
  int _step = 1;
  String? _target;
  String? _devOtp;
  String? _emailError;
  String? _requestError;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_busy) return;
    final l10n = context.l10n;
    final auth = context.read<AuthProvider>();
    final value = _email.text.trim();
    var error = validateEmail(l10n, value);
    if (error == null &&
        value.toLowerCase() == (auth.user?.email ?? '').toLowerCase()) {
      error = l10n.acctSameEmail;
    }
    setState(() {
      _emailError = error;
      _requestError = null;
    });
    if (error != null) return;
    setState(() => _busy = true);
    try {
      final dev = await auth.requestEmailChange(value);
      if (!mounted) return;
      setState(() {
        _step = 2;
        _target = value;
        _devOtp = dev;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _requestError = auth.error ?? friendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<OtpOutcome> _confirm(String code) async {
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    try {
      await auth.confirmEmailChange(code);
      if (!mounted) return const OtpOutcome.success();
      showAccountNotice(context, context.l10n.acctEmailChanged);
      Navigator.of(context).pop();
      return const OtpOutcome.success();
    } catch (e) {
      return OtpOutcome.failure(auth.error ?? friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<OtpOutcome> _resend() async {
    final auth = context.read<AuthProvider>();
    try {
      final dev = await auth.requestEmailChange(_target!);
      return OtpOutcome.success(devOtp: dev);
    } catch (e) {
      return OtpOutcome.failure(auth.error ?? friendlyErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: QdSpace.x5),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.gutter, QdSpace.x3, QdSpace.x2, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      _step == 1
                          ? l10n.acctChangeEmailLabel
                          : l10n.authOtpTitle,
                      style: QdText.sheetTitle.copyWith(color: c.textPrimary),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('email_change_close'),
                  tooltip: l10n.acctClose,
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: c.textPrimary),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: QdSpace.x3),
              child: _step == 1 ? _stepOne(context) : _stepTwo(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepOne(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.acctEmailNote,
            style: QdText.body.copyWith(color: c.textSecondary)),
        const SizedBox(height: QdSpace.x4),
        if (_requestError != null) ...[
          QdBanner(
            key: const Key('email_change_error'),
            tone: QdBannerTone.danger,
            icon: Icons.error_outline,
            message: _requestError!,
            actionLabel: l10n.retry,
            onAction: _request,
          ),
          const SizedBox(height: QdSpace.x4),
        ],
        QdTextField(
          key: const Key('email_change_input'),
          label: l10n.acctNewEmailLabel,
          hint: l10n.authEmailHint,
          controller: _email,
          ltr: true,
          errorText: _emailError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _request(),
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
        ),
        const SizedBox(height: QdSpace.x5),
        QdButton(
          key: const Key('email_change_send'),
          label: l10n.resetSendCode,
          loading: _busy,
          fullWidth: true,
          onPressed: _request,
        ),
      ],
    );
  }

  Widget _stepTwo(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.authOtpSentTo,
            style: QdText.body.copyWith(color: c.textSecondary)),
        Text(
          _target ?? '',
          key: const Key('email_change_target'),
          textDirection: TextDirection.ltr,
          textAlign: Directionality.of(context) == TextDirection.rtl
              ? TextAlign.right
              : TextAlign.left,
          style: QdText.bodyStrong.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: QdSpace.x4),
        OtpCodeForm(
          key: const Key('email_change_code'),
          devOtp: _devOtp,
          onVerify: _confirm,
          onResend: _resend,
        ),
      ],
    );
  }
}
