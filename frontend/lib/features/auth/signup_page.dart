import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import 'auth_forms.dart';
import 'otp_page.dart';
import 'widgets/auth_scaffold.dart';

/// Sign up (A-Signup): customer or business owner only. Couriers get their
/// accounts from their business owner, so they are not offered.
///
/// Behaviour kept from SignupScreen: name rules (3–30 letters, Latin or
/// Arabic, digits, spaces, `_`) with the field following the name's
/// direction, email check, SEC-03 password length rules, the server error
/// (localized for `weak_password`) as a banner with retry, then the code
/// screen with the development code when the server sent one.
class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  // The mockup preselects "customer" (the old screen preselected owner).
  String _role = 'user';
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate() {
    final l10n = context.l10n;
    setState(() {
      _nameError = validateName(l10n, _name.text);
      _emailError = validateEmail(l10n, _email.text);
      _passwordError = validateNewPassword(l10n, _password.text);
    });
    return _nameError == null && _emailError == null && _passwordError == null;
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) return;
    final auth = context.read<AuthProvider>();
    final email = _email.text.trim();
    setState(() => _submitting = true);
    final devOtp =
        await auth.signup(email, _name.text.trim(), _password.text, _role);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (auth.error != null) return; // shown in the banner
    await Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute(
      builder: (_) => OtpPage(email: email, devOtp: devOtp),
    ));
  }

  void _back() {
    context.read<AuthProvider>().clearError();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();
    final error = authErrorText(l10n, auth);
    final rtlName = startsRtl(_name.text);

    return AuthScaffold(
      onBack: _back,
      footer: AuthFooterLink(
        key: const Key('signup_to_login'),
        question: l10n.authHaveAccount,
        link: l10n.authSignInLink,
        onTap: _back,
      ),
      children: [
        const SizedBox(height: QdSpace.x3),
        AuthHeading(title: l10n.authSignupTitle),
        const SizedBox(height: QdSpace.x5),
        if (error != null) ...[
          QdBanner(
            key: const Key('signup_error'),
            tone: QdBannerTone.danger,
            icon: Icons.error_outline,
            message: error,
            actionLabel: l10n.retry,
            onAction: _submit,
          ),
          const SizedBox(height: QdSpace.x4),
        ],
        Builder(builder: (context) {
          final c = QdColors.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.authRoleQuestion,
                  style: QdText.body.copyWith(
                      color: c.textPrimary, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: QdSpace.x2),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: QdOptionCard(
                        key: const Key('signup_role_customer'),
                        title: l10n.authRoleCustomer,
                        subtitle: l10n.authRoleCustomerHint,
                        selected: _role == 'user',
                        onTap: () => setState(() => _role = 'user'),
                      ),
                    ),
                    const SizedBox(width: QdSpace.x2),
                    Expanded(
                      child: QdOptionCard(
                        key: const Key('signup_role_owner'),
                        title: l10n.authRoleOwner,
                        subtitle: l10n.authRoleOwnerHint,
                        selected: _role == 'owner',
                        onTap: () => setState(() => _role = 'owner'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: QdSpace.x2),
              Text(
                l10n.authCourierNote,
                key: const Key('signup_courier_note'),
                style: QdText.caption.copyWith(color: c.textSecondary),
              ),
            ],
          );
        }),
        const SizedBox(height: QdSpace.x4),
        QdTextField(
          key: const Key('signup_name'),
          label: l10n.authNameLabel,
          controller: _name,
          errorText: _nameError,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          // A Latin name is typed left to right even in Arabic.
          ltr: rtlName == false,
          onChanged: (_) => setState(() => _nameError = null),
        ),
        const SizedBox(height: QdSpace.x4),
        QdTextField(
          key: const Key('signup_email'),
          label: l10n.authEmailLabel,
          hint: l10n.authEmailHint,
          controller: _email,
          ltr: true,
          errorText: _emailError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
        ),
        const SizedBox(height: QdSpace.x4),
        QdTextField(
          key: const Key('signup_password'),
          label: l10n.authPasswordLabel,
          controller: _password,
          obscure: true,
          errorText: _passwordError,
          helperText: l10n.authPasswordHelp,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
        ),
        const SizedBox(height: QdSpace.x5),
        QdButton(
          key: const Key('signup_submit'),
          label: l10n.authCreateAccount,
          loading: _submitting,
          fullWidth: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}
