import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../ui/qd_ui.dart';

/// Page frame of the signed-out screens (A-Login, A-Signup, A-OTP): white
/// page, 24 dp sides, an optional back button
/// and header actions on one row, the content, and a footer pinned to the
/// bottom when the content is short (scrolls with it when long).
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.onBack,
    this.actions = const [],
    this.footer,
  });

  final List<Widget> children;

  /// Shows the back button when set.
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) {
      final c = QdColors.of(context);
      final header = onBack == null && actions.isEmpty
          ? null
          : Row(
              children: [
                if (onBack != null)
                  // The mockups start the back button 12 dp into the
                  // gutter so its glyph lines up with the text below.
                  Transform.translate(
                    offset: Offset(
                        Directionality.of(context) == TextDirection.rtl
                            ? 12
                            : -12,
                        0),
                    child: IconButton(
                      key: const Key('auth_back'),
                      onPressed: onBack,
                      tooltip: context.l10n.authBack,
                      icon: Icon(Icons.arrow_back, color: c.textPrimary),
                    ),
                  ),
                const Spacer(),
                ...actions,
              ],
            );
      return Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  // 440 dp of content plus the 24 dp sides.
                  constraints: BoxConstraints(
                    maxWidth: 488,
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          QdSpace.x6, QdSpace.x5, QdSpace.x6, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (header != null) header,
                          ...children,
                          if (footer != null) ...[
                            const Spacer(),
                            const SizedBox(height: QdSpace.x6),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// "Question? Link" footer line (A-Login, A-Signup).
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.question,
    required this.link,
    required this.onTap,
  });

  final String question;
  final String link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: QdText.body.copyWith(color: c.textSecondary)),
        const SizedBox(width: QdSpace.x1),
        _InlineLink(label: link, onTap: onTap),
      ],
    );
  }
}

class _InlineLink extends StatelessWidget {
  const _InlineLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(QdRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: QdSize.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: QdSpace.x1),
            child: Align(
              widthFactor: 1,
              child: Text(
                label,
                style: QdText.bodyStrong.copyWith(
                  color: c.textPrimary,
                  decoration: TextDecoration.underline,
                  decorationColor: c.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A link-styled text button at the reading start (A-Login "forgot your
/// password?"). 48 dp tall.
class AuthTextLink extends StatelessWidget {
  const AuthTextLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: _InlineLink(label: label, onTap: onTap),
    );
  }
}

/// Title + subtitle block of an auth screen.
class AuthHeading extends StatelessWidget {
  const AuthHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.emphasis,
    this.large = false,
  });

  final String title;
  final String? subtitle;

  /// Bold left-to-right line under the subtitle (the email a code went to).
  final String? emphasis;

  /// 28 sp (sign in) instead of 26.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: (large ? QdText.screenTitleLg : QdText.screenTitle)
                .copyWith(color: c.textPrimary),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: QdText.body
                .copyWith(fontSize: 15, color: c.textSecondary, height: 1.6),
          ),
        ],
        if (emphasis != null)
          Text(
            emphasis!,
            textDirection: TextDirection.ltr,
            style: QdText.body.copyWith(
              fontSize: 15,
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          ),
      ],
    );
  }
}

/// Shows [message] as a floating notice (success / info), like the order
/// pages' notices.
void showAuthNotice(BuildContext context, String message,
    {VoidCallback? onRetry}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: onRetry == null
          ? null
          : SnackBarAction(label: context.l10n.retry, onPressed: onRetry),
    ));
}
