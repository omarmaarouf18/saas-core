import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import 'account_nav.dart';

/// Security: the 2-step verification switch.
///
/// Behaviour kept from SettingsScreen: turning it on is one PATCH with the
/// switch locked (and a spinner) for the whole round trip; turning it off
/// needs a confirmation and then the password, in a dialog that an outside
/// tap cannot close. In that dialog a 401 says the password is wrong, a
/// 429 shows the server's lockout text without retry, anything else the
/// provider's message; the typed password is cleared after use.
class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  bool _toggling = false;

  Future<void> _changed(bool on) async {
    final l10n = context.l10n;
    final auth = context.read<AuthProvider>();
    if (!on) {
      final confirmed = await _confirmOff(context);
      if (confirmed != true || !mounted) return;
      final off = await _PasswordDialog.show(context);
      if (off == true && mounted) {
        showAccountNotice(context, l10n.acctTwoFactorOffDone);
      }
      return;
    }
    setState(() => _toggling = true);
    try {
      await auth.toggleTwoFactor(true);
      if (mounted) showAccountNotice(context, l10n.acctTwoFactorOnDone);
    } catch (e) {
      if (mounted) showAccountNotice(context, friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<bool?> _confirmOff(BuildContext context) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Builder(builder: (ctx) {
        final c = QdColors.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(l10n.acctTwoFactorOffTitle,
              style: QdText.header.copyWith(color: c.textPrimary)),
          content: Text(l10n.acctTwoFactorOffBody,
              style: QdText.body.copyWith(color: c.textSecondary)),
          actions: [
            QdButton.text(
              key: const Key('two_factor_off_cancel'),
              label: l10n.acctCancel,
              small: true,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            QdButton.destructive(
              key: const Key('two_factor_off_confirm'),
              label: l10n.acctTwoFactorTurnOff,
              small: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final on = context.watch<AuthProvider>().user?.twoFactorEnabled ?? true;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: accountAppBar(context, l10n.acctSecurity),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
        children: [
          QdListGroup(children: [
            if (_toggling)
              QdListTile(
                key: const Key('two_factor_busy'),
                icon: Icons.verified_user_outlined,
                title: l10n.acctTwoFactor,
                subtitle: l10n.acctTwoFactorBody,
                badge: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              QdListTile(
                key: const Key('two_factor_switch'),
                icon: Icons.verified_user_outlined,
                title: l10n.acctTwoFactor,
                subtitle: l10n.acctTwoFactorBody,
                switchValue: on,
                onSwitchChanged: _changed,
              ),
          ]),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PasswordDialog(),
      );

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _fieldError;
  String? _error;
  bool _lockedOut = false;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = context.l10n;
    final auth = context.read<AuthProvider>();
    if (_password.text.trim().isEmpty) {
      setState(() => _fieldError = l10n.authPasswordRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });
    try {
      await auth.toggleTwoFactor(false, password: _password.text);
      _password.clear();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final status = auth.lastErrorStatusCode;
      setState(() {
        _busy = false;
        _lockedOut = status == 429;
        _error = status == 401
            ? l10n.acctWrongPassword
            : (auth.error ?? l10n.acctWrongPassword);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(l10n.acctPasswordTitle,
          style: QdText.header.copyWith(color: c.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.acctPasswordBody,
                style: QdText.body.copyWith(color: c.textSecondary)),
            if (_error != null) ...[
              const SizedBox(height: QdSpace.x3),
              QdBanner(
                key: Key(_lockedOut
                    ? 'two_factor_lockout'
                    : 'two_factor_password_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: _error!,
              ),
            ],
            const SizedBox(height: QdSpace.x4),
            QdTextField(
              key: const Key('two_factor_password'),
              label: l10n.authPasswordLabel,
              controller: _password,
              obscure: true,
              enabled: !_busy,
              errorText: _fieldError,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        QdButton.text(
          key: const Key('two_factor_password_cancel'),
          label: l10n.acctCancel,
          small: true,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        QdButton.destructive(
          key: const Key('two_factor_password_confirm'),
          label: l10n.acctTwoFactorTurnOff,
          small: true,
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
