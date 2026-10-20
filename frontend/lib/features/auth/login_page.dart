import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../../ui/qd_ui.dart';
import 'auth_forms.dart';
import 'auth_nav.dart';
import 'otp_page.dart';
import 'signup_page.dart';
import 'widgets/auth_scaffold.dart';

/// Sign in (A-Login).
///
/// Behaviour kept from LoginScreen: email + password validation, the
/// provider error as a persistent banner with retry, accounts without 2FA
/// (and employees) go straight home, others get the code screen with the
/// development code when the server sent one, language and theme switches,
/// links to password reset and sign-up (with a double-tap guard).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  bool _submitting = false;
  bool _navigating = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate() {
    final l10n = context.l10n;
    setState(() {
      _emailError = validateEmail(l10n, _email.text);
      _passwordError =
          _password.text.isEmpty ? l10n.authPasswordRequired : null;
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) return;
    final auth = context.read<AuthProvider>();
    final email = _email.text.trim();
    setState(() => _submitting = true);
    final devOtp = await auth.login(email, _password.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (auth.error != null) return; // shown in the banner
    if (auth.isAuthenticated) {
      // No second step for this account (2FA off, or an employee).
      await AuthNavScope.of(context).goHome(context);
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => OtpPage(email: email, devOtp: devOtp),
    ));
  }

  // One push at a time: a double tap must not stack two pages.
  Future<void> _open(Future<String?> Function() push) async {
    if (_navigating) return;
    _navigating = true;
    context.read<AuthProvider>().clearError();
    final result = await push();
    _navigating = false;
    // The reset flow hands back the email it ended with.
    if (result != null && mounted) _email.text = result;
  }

  void _toggleLanguage() {
    final locale = context.read<LocaleProvider>();
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    locale.setLocale(Locale(isAr ? 'en' : 'ar'));
  }

  // Same cycle as the old sign-in screen: light → dark → system → light.
  void _cycleTheme() {
    final theme = context.read<ThemeProvider>();
    final next = switch (theme.themeMode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    theme.setThemeMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();
    final themeMode = context.watch<ThemeProvider>().themeMode;
    final error = authErrorText(l10n, auth);

    return AuthScaffold(
      actions: [
        Builder(builder: (context) {
          final c = QdColors.of(context);
          return IconButton(
            key: const Key('login_theme'),
            tooltip: l10n.authThemeLabel,
            onPressed: _cycleTheme,
            icon: Icon(
              switch (themeMode) {
                ThemeMode.dark => Icons.dark_mode_outlined,
                ThemeMode.light => Icons.light_mode_outlined,
                ThemeMode.system => Icons.brightness_auto_outlined,
              },
              color: c.textPrimary,
            ),
          );
        }),
        const SizedBox(width: QdSpace.x1),
        _LanguagePill(
          label: l10n.authSwitchLanguage,
          semanticLabel: l10n.authSwitchLanguageLabel,
          onTap: _toggleLanguage,
        ),
      ],
      footer: AuthFooterLink(
        key: const Key('login_to_signup'),
        question: l10n.authNoAccount,
        link: l10n.authCreateAccountLink,
        onTap: () => _open(() => Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const SignupPage()))),
      ),
      children: [
        const SizedBox(height: 48),
        const _BrandTile(),
        const SizedBox(height: QdSpace.x5),
        AuthHeading(
          title: l10n.authLoginTitle,
          subtitle: l10n.authLoginSubtitle,
          large: true,
        ),
        const SizedBox(height: 36),
        if (error != null) ...[
          QdBanner(
            key: const Key('login_error'),
            tone: QdBannerTone.danger,
            icon: Icons.error_outline,
            message: error,
            actionLabel: l10n.retry,
            onAction: _submit,
          ),
          const SizedBox(height: QdSpace.x4),
        ],
        QdTextField(
          key: const Key('login_email'),
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
          key: const Key('login_password'),
          label: l10n.authPasswordLabel,
          controller: _password,
          obscure: true,
          errorText: _passwordError,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
        ),
        const SizedBox(height: QdSpace.x2),
        AuthTextLink(
          key: const Key('login_forgot'),
          label: l10n.authForgotPassword,
          onTap: () => _open(() => AuthNavScope.of(context).openPasswordReset(
                context,
                email: _email.text.trim().isEmpty ? null : _email.text.trim(),
              )),
        ),
        const SizedBox(height: QdSpace.x2),
        QdButton(
          key: const Key('login_submit'),
          label: l10n.authSignIn,
          loading: _submitting,
          fullWidth: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Navy 56 dp tile with the gold box mark (A-Login).
class _BrandTile extends StatelessWidget {
  const _BrandTile();

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ExcludeSemantics(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: QdColors.light.navy,
            borderRadius: BorderRadius.circular(QdRadius.card),
            border: Theme.of(context).brightness == Brightness.dark
                ? Border.all(color: c.border)
                : null,
          ),
          child: Icon(Icons.inventory_2_outlined,
              size: 28, color: QdColors.light.gold),
        ),
      ),
    );
  }
}

/// "English" / "العربية" pill (A-Login header).
class _LanguagePill extends StatelessWidget {
  const _LanguagePill({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(QdRadius.pill),
      side: BorderSide(color: c.border),
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        key: const Key('login_language'),
        color: c.surface,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: QdSize.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: QdSpace.x3),
              child: Center(
                widthFactor: 1,
                child: Text(label,
                    style: QdText.body.copyWith(color: c.textPrimary)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
