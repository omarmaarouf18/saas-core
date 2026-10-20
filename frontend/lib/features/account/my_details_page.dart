import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import 'account_nav.dart';
import 'account_page.dart';
import 'email_change_sheet.dart';

/// My details: name, phone, and the email (read-only, with "change" → the
/// two-step email change).
///
/// Behaviour kept from MyAccountScreen: fields prefilled from the profile,
/// the name is required, save PATCHes username + phone (addresses have
/// their own page now), the provider's error with retry, a notice and back
/// on success, and nothing can be changed while the account is suspended.
class MyDetailsPage extends StatefulWidget {
  const MyDetailsPage({super.key});

  @override
  State<MyDetailsPage> createState() => _MyDetailsPageState();
}

class _MyDetailsPageState extends State<MyDetailsPage> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  String? _nameError;
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _name = TextEditingController(text: user?.username ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = context.l10n;
    setState(() {
      _nameError = _name.text.trim().isEmpty ? l10n.authNameRequired : null;
      _saveError = null;
    });
    if (_nameError != null) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      await auth.updateOwnProfile(
        username: _name.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      showAccountNotice(context, l10n.acctSaved);
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      // PATCH /auth/user is an auth-path endpoint: the provider's stored
      // message first (same contract as the old screen).
      setState(() => _saveError = auth.error ?? friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final user = context.watch<AuthProvider>().user;
    final suspended = user?.isSuspended ?? false;

    return Scaffold(
      backgroundColor: c.surface,
      appBar: accountAppBar(context, l10n.acctMyDetails),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
        children: [
          if (suspended) ...[
            SuspendedBanner(user: user!),
            const SizedBox(height: QdSpace.x4),
          ],
          if (_saveError != null) ...[
            QdBanner(
              key: const Key('details_error'),
              tone: QdBannerTone.danger,
              icon: Icons.error_outline,
              message: _saveError!,
              actionLabel: l10n.retry,
              onAction: _save,
            ),
            const SizedBox(height: QdSpace.x4),
          ],
          QdTextField(
            key: const Key('details_name'),
            label: l10n.authNameLabel,
            controller: _name,
            enabled: !suspended,
            errorText: _nameError,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: QdSpace.x4),
          QdTextField(
            key: const Key('details_phone'),
            label: l10n.acctPhoneLabel,
            hint: l10n.acctPhoneHint,
            controller: _phone,
            enabled: !suspended,
            ltr: true,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
          const SizedBox(height: QdSpace.x4),
          Text(l10n.authEmailLabel,
              style: QdText.body
                  .copyWith(color: c.textPrimary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          QdCard(
            subtle: true,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: c.textSecondary),
                const SizedBox(width: QdSpace.x2),
                Expanded(
                  child: Text(
                    user?.email ?? '',
                    key: const Key('details_email'),
                    textDirection: TextDirection.ltr,
                    textAlign: Directionality.of(context) == TextDirection.rtl
                        ? TextAlign.right
                        : TextAlign.left,
                    style: QdText.body
                        .copyWith(fontSize: 15, color: c.textPrimary),
                  ),
                ),
                Semantics(
                  label: l10n.acctChangeEmailLabel,
                  excludeSemantics: true,
                  button: true,
                  enabled: !suspended,
                  child: QdButton.text(
                    key: const Key('details_change_email'),
                    label: l10n.acctChangeEmail,
                    small: true,
                    onPressed:
                        suspended ? null : () => EmailChangeSheet.show(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(l10n.acctEmailNote,
              style: QdText.caption.copyWith(color: c.textSecondary)),
          const SizedBox(height: QdSpace.x6),
          QdButton(
            key: const Key('details_save'),
            label: l10n.acctSave,
            loading: _saving,
            fullWidth: true,
            onPressed: suspended ? null : _save,
          ),
        ],
      ),
    );
  }
}
