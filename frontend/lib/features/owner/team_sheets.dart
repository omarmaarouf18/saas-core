import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/error_messages.dart';
import '../../core/password_policy.dart';
import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';
import 'owner_rules.dart';
import 'owner_sheets.dart';

/// Freeze / unfreeze confirmation with the owner's password (the endpoint
/// re-checks it). The sheet is the confirm step: it says what happens and
/// asks for the password. Not dismissible by an outside tap; a failure
/// keeps it open with the reason. Returns true when the change went
/// through.
class OwnerPasswordSheet extends StatefulWidget {
  const OwnerPasswordSheet({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.destructive,
    required this.onConfirm,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final bool destructive;
  final Future<void> Function(String password) onConfirm;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required bool destructive,
    required Future<void> Function(String password) onConfirm,
  }) =>
      showOwnerSheet<bool>(
        context,
        dismissible: false,
        builder: (_) => OwnerPasswordSheet(
          title: title,
          body: body,
          confirmLabel: confirmLabel,
          destructive: destructive,
          onConfirm: onConfirm,
        ),
      );

  @override
  State<OwnerPasswordSheet> createState() => _OwnerPasswordSheetState();
}

class _OwnerPasswordSheetState extends State<OwnerPasswordSheet> {
  final _password = TextEditingController();
  bool _submitting = false;
  String? _fieldError;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final l10n = context.l10n;
    if (_submitting) return;
    if (_password.text.isEmpty) {
      setState(() => _fieldError = l10n.ownPasswordRequired);
      return;
    }
    setState(() {
      _submitting = true;
      _fieldError = _error = null;
    });
    try {
      await widget.onConfirm(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final kind = toggleFailureOf(e);
      setState(() {
        _submitting = false;
        if (kind == ToggleFailure.wrongPassword) {
          _password.clear();
          _fieldError = l10n.ownPasswordWrong;
        } else {
          _error = switch (kind) {
            ToggleFailure.kybNotApproved => l10n.ownToggleKybNeeded,
            ToggleFailure.paidPlanRequired => l10n.ownTogglePaidPlan,
            // SEC-07b: revocation failed, nothing changed — retry.
            ToggleFailure.unavailable => l10n.serviceTemporarilyUnavailable,
            ToggleFailure.tooManyTries =>
              e is ApiClientException ? e.message : friendlyErrorMessage(e),
            _ => friendlyErrorMessage(e),
          };
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return QdBottomSheet(
      key: const Key('own_password_sheet'),
      title: widget.title,
      subtitle: widget.body,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QdTextField(
              key: const Key('own_password_input'),
              label: l10n.ownYourPassword,
              controller: _password,
              obscure: true,
              ltr: true,
              enabled: !_submitting,
              errorText: _fieldError,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
            ),
            if (_error != null) ...[
              const SizedBox(height: QdSpace.x3),
              QdBanner(
                key: const Key('own_password_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: _error!,
              ),
            ],
            const SizedBox(height: QdSpace.x5),
            if (widget.destructive)
              QdButton.destructive(
                key: const Key('own_password_confirm'),
                label: widget.confirmLabel,
                fullWidth: true,
                loading: _submitting,
                onPressed: _confirm,
              )
            else
              QdButton(
                key: const Key('own_password_confirm'),
                label: widget.confirmLabel,
                fullWidth: true,
                loading: _submitting,
                onPressed: _confirm,
              ),
            const SizedBox(height: QdSpace.x1),
            QdButton.text(
              key: const Key('own_password_cancel'),
              label: l10n.ownNotNow,
              fullWidth: true,
              onPressed:
                  _submitting ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add a courier (O-Team sheet): username, email and a password under the
/// shared policy (SEC-03). The account is created with `/auth/signup`
/// (role employee, this owner). Returns the new username on success.
class AddEmployeeSheet extends StatefulWidget {
  const AddEmployeeSheet({super.key, required this.onSubmit});

  final Future<void> Function(String username, String email, String password)
      onSubmit;

  static Future<String?> show(BuildContext context,
          {required Future<void> Function(
                  String username, String email, String password)
              onSubmit}) =>
      showOwnerSheet<String>(
        context,
        dismissible: false,
        builder: (_) => AddEmployeeSheet(onSubmit: onSubmit),
      );

  @override
  State<AddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends State<AddEmployeeSheet> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _tried = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _usernameError(AppLocalizations l10n) =>
      switch (usernameProblem(_username.text)) {
        UsernameProblem.required => l10n.usernameRequired,
        UsernameProblem.tooShort => l10n.usernameTooShort,
        UsernameProblem.tooLong => l10n.usernameTooLong,
        UsernameProblem.invalidChars => l10n.usernameInvalidChars,
        null => null,
      };

  String? _emailError(AppLocalizations l10n) {
    if (_email.text.trim().isEmpty) return l10n.emailRequired;
    return isValidEmail(_email.text) ? null : l10n.invalidEmailFormat;
  }

  String? _passwordError(AppLocalizations l10n) => _password.text.isEmpty
      ? l10n.passwordRequired
      : validatePassword(l10n, _password.text);

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (_submitting) return;
    setState(() => _tried = true);
    if (_usernameError(l10n) != null ||
        _emailError(l10n) != null ||
        _passwordError(l10n) != null) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final username = _username.text.trim();
    try {
      await widget.onSubmit(username, _email.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop(username);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // SEC-03: a server weak_password rejection carries a machine
        // code; show the localized reason.
        _error = e is ApiClientException &&
                e.statusCode == 400 &&
                e.errorCode == 'weak_password'
            ? weakPasswordServerMessage(l10n, e.message)
            : friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return QdBottomSheet(
      key: const Key('own_add_sheet'),
      title: l10n.ownAddTitle,
      subtitle: l10n.ownAddBody,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QdTextField(
              key: const Key('own_add_username'),
              label: l10n.ownAddUsername,
              controller: _username,
              enabled: !_submitting,
              errorText: _tried ? _usernameError(l10n) : null,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: QdSpace.x3),
            QdTextField(
              key: const Key('own_add_email'),
              label: l10n.ownAddEmail,
              controller: _email,
              ltr: true,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              errorText: _tried ? _emailError(l10n) : null,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: QdSpace.x3),
            QdTextField(
              key: const Key('own_add_password'),
              label: l10n.ownAddPassword,
              controller: _password,
              obscure: true,
              ltr: true,
              enabled: !_submitting,
              helperText: l10n.ownAddPasswordHelp,
              errorText: _tried ? _passwordError(l10n) : null,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: QdSpace.x3),
              QdBanner(
                key: const Key('own_add_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: _error!,
              ),
            ],
            const SizedBox(height: QdSpace.x5),
            QdButton(
              key: const Key('own_add_submit'),
              label: l10n.ownAddSubmit,
              fullWidth: true,
              loading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: QdSpace.x1),
            QdButton.text(
              key: const Key('own_add_cancel'),
              label: l10n.ownNotNow,
              fullWidth: true,
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
