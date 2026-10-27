import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../ui/qd_ui.dart';
import 'auth_scaffold.dart';

/// Result of a verify or resend call made by an [OtpCodeForm] owner.
class OtpOutcome {
  const OtpOutcome.success({this.devOtp})
      : error = null,
        retryable = true,
        waitSeconds = null;
  const OtpOutcome.failure(String this.error,
      {this.retryable = true, this.waitSeconds})
      : devOtp = null;

  /// A lockout's wait (429 "try again in N seconds"): the resend countdown
  /// restarts with it, so "send again" comes back when the server allows.
  final int? waitSeconds;

  /// Failure text, null on success.
  final String? error;

  /// False for lockouts (429): retrying only extends them, so the error
  /// banner offers no retry.
  final bool retryable;

  /// Development code returned by a resend (`dev_otp`), when the server
  /// sends one.
  final String? devOtp;

  bool get ok => error == null;
}

/// Seconds before "send the code again" is offered. The server has no
/// resend cooldown of its own; this keeps people from hammering the email
/// dispatcher (and the per-email lockout) while the first code is on its
/// way.
const int kOtpResendCooldownSeconds = 60;

/// The A-OTP code entry, shared by the sign-in / sign-up code screen, the
/// password reset code step and the email change sheet: six boxes (paste
/// supported), the development code auto-filled with a banner when the
/// server returned one, a confirm button, and "send it again" after a
/// countdown.
///
/// A full code verifies on its own (like the old screens); a second
/// completion while a verify is in flight is ignored.
class OtpCodeForm extends StatefulWidget {
  const OtpCodeForm({
    super.key,
    required this.onVerify,
    required this.onResend,
    this.devOtp,
    this.confirmLabel,
    this.cooldownSeconds = kOtpResendCooldownSeconds,
  });

  /// Verifies the code. Success is followed by the owner's navigation; the
  /// form only shows failures.
  final Future<OtpOutcome> Function(String code) onVerify;
  final Future<OtpOutcome> Function() onResend;

  /// Development code from the call that sent the first code.
  final String? devOtp;
  final String? confirmLabel;
  final int cooldownSeconds;

  @override
  State<OtpCodeForm> createState() => _OtpCodeFormState();
}

class _OtpCodeFormState extends State<OtpCodeForm> {
  final _code = TextEditingController();
  Timer? _timer;
  late int _secondsLeft;
  String? _devOtp;
  bool _verifying = false;
  bool _resending = false;
  bool _showIncomplete = false;
  OtpOutcome? _failure;
  bool _failureFromResend = false;

  @override
  void initState() {
    super.initState();
    _devOtp = _clean(widget.devOtp);
    if (_devOtp != null) _code.text = _devOtp!;
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  static String? _clean(String? v) => v == null || v.isEmpty ? null : v;

  // Counted down in ticks (not wall-clock time) so tests can drive it.
  void _startCooldown([int? seconds]) {
    _timer?.cancel();
    _secondsLeft = seconds ?? widget.cooldownSeconds;
    if (_secondsLeft <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (_verifying || _resending) return;
    final code = _code.text;
    if (code.length != 6) {
      setState(() => _showIncomplete = true);
      return;
    }
    setState(() {
      _verifying = true;
      _showIncomplete = false;
      _failure = null;
    });
    final outcome = await widget.onVerify(code);
    if (!mounted) return;
    setState(() {
      _verifying = false;
      if (!outcome.ok) {
        _failure = outcome;
        _failureFromResend = false;
      }
    });
  }

  Future<void> _resend() async {
    if (_resending || _verifying) return;
    setState(() {
      _resending = true;
      _failure = null;
    });
    final outcome = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _resending = false;
      if (outcome.ok) {
        final dev = _clean(outcome.devOtp);
        _devOtp = dev;
        if (dev != null) _code.text = dev;
        _startCooldown();
      } else {
        _failure = outcome;
        _failureFromResend = true;
        final wait = outcome.waitSeconds;
        if (wait != null && wait > 0) _startCooldown(wait);
      }
    });
    if (outcome.ok && mounted) {
      showAuthNotice(context, context.l10n.authCodeResent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final failure = _failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null) ...[
          QdBanner(
            key: Key(failure.retryable
                ? (_failureFromResend ? 'otp_resend_error' : 'otp_error')
                : 'otp_lockout'),
            tone: QdBannerTone.danger,
            icon: Icons.error_outline,
            message: failure.error!,
            actionLabel: failure.retryable ? l10n.retry : null,
            onAction: failure.retryable
                ? (_failureFromResend ? _resend : _verify)
                : null,
          ),
          const SizedBox(height: QdSpace.x4),
        ],
        QdOtpInput(
          key: const Key('otp_boxes'),
          controller: _code,
          semanticLabel: l10n.authOtpLabel,
          hasError: (failure != null && !_failureFromResend) || _showIncomplete,
          onChanged: (_) {
            if (_showIncomplete || (failure != null && !_failureFromResend)) {
              setState(() {
                _showIncomplete = false;
                if (!_failureFromResend) _failure = null;
              });
            }
          },
          onCompleted: (_) => _verify(),
        ),
        if (_showIncomplete) ...[
          const SizedBox(height: QdSpace.x2),
          Text(
            l10n.authOtpIncomplete,
            key: const Key('otp_incomplete'),
            style: QdText.caption
                .copyWith(color: c.danger, fontWeight: FontWeight.w500),
          ),
        ],
        if (_devOtp != null) ...[
          const SizedBox(height: QdSpace.x4),
          QdBanner(
            key: const Key('otp_dev_banner'),
            tone: QdBannerTone.info,
            icon: Icons.bug_report_outlined,
            message: l10n.authDevOtp(_devOtp!),
          ),
        ],
        const SizedBox(height: QdSpace.x6),
        QdButton(
          key: const Key('otp_confirm'),
          label: widget.confirmLabel ?? l10n.authOtpConfirm,
          loading: _verifying,
          fullWidth: true,
          onPressed: _resending ? null : _verify,
        ),
        const SizedBox(height: QdSpace.x6),
        _resendLine(context),
      ],
    );
  }

  Widget _resendLine(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    if (_secondsLeft > 0) {
      final m = _secondsLeft ~/ 60;
      final s = (_secondsLeft % 60).toString().padLeft(2, '0');
      return Text.rich(
        key: const Key('otp_resend_wait'),
        TextSpan(children: [
          TextSpan(text: '${l10n.authResendWait} '),
          TextSpan(
            text: '\u2066$m:$s\u2069',
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
          ),
        ]),
        textAlign: TextAlign.center,
        style: QdText.body.copyWith(color: c.textSecondary),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(l10n.authResendPrompt,
            style: QdText.body.copyWith(color: c.textSecondary)),
        QdButton.text(
          key: const Key('otp_resend'),
          label: l10n.authResendNow,
          loading: _resending,
          small: true,
          onPressed: _verifying ? null : _resend,
        ),
      ],
    );
  }
}
