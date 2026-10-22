import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../tokens.dart';

/// Redesign A text field: label above, hint inside, error below.
///
/// [obscure] turns it into a password field with a visibility toggle.
/// [ltr] forces left-to-right input (phone, email, OTP) inside an RTL
/// screen; the text still sits on the reading-start side like the mockups.
class QdTextField extends StatefulWidget {
  const QdTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.helperText,
    this.obscure = false,
    this.ltr = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.focusNode,
    this.maxLines = 1,
    this.suffixText,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final bool obscure;
  final bool ltr;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final FocusNode? focusNode;
  final int maxLines;

  /// Unit shown inside the field at its end ("km").
  final String? suffixText;

  @override
  State<QdTextField> createState() => _QdTextFieldState();
}

class _QdTextFieldState extends State<QdTextField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final l10n = context.l10n;
    final ambient = Directionality.of(context);
    final fieldDirection = widget.ltr ? TextDirection.ltr : ambient;
    // An LTR field inside RTL keeps its text on the right, like the mockup's
    // `dir="ltr"; text-align: right` email input.
    final align = widget.ltr && ambient == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.start;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(QdRadius.sm),
          borderSide: BorderSide(color: color, width: width),
        );

    final toggle = widget.obscure
        ? IconButton(
            onPressed: () => setState(() => _hidden = !_hidden),
            tooltip: _hidden ? l10n.showPassword : l10n.hidePassword,
            icon: Icon(
              _hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: c.textSecondary,
              size: QdSize.icon,
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The visible label is announced as the field's own label below.
        ExcludeSemantics(
          child: Text(
            widget.label,
            style: QdText.body.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: widget.label,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
            obscureText: widget.obscure && _hidden,
            enableSuggestions: !widget.obscure,
            autocorrect: !widget.obscure && !widget.ltr,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            inputFormatters: widget.inputFormatters,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            textDirection: fieldDirection,
            textAlign: align,
            cursorColor: c.textPrimary,
            style: QdText.body.copyWith(fontSize: 15, color: c.textPrimary),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintTextDirection: fieldDirection,
              hintStyle: QdText.body.copyWith(
                fontSize: 15,
                color: c.textSecondary,
              ),
              filled: true,
              fillColor: widget.enabled ? c.surface : c.fillSubtle,
              isDense: true,
              constraints: const BoxConstraints(minHeight: QdSize.fieldHeight),
              contentPadding: const EdgeInsetsDirectional.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
              suffixIcon: toggle,
              suffixText: widget.suffixText,
              suffixStyle:
                  QdText.body.copyWith(fontSize: 15, color: c.textSecondary),
              border: border(c.borderInput),
              enabledBorder: border(hasError ? c.danger : c.borderInput),
              disabledBorder: border(c.border),
              focusedBorder: border(hasError ? c.danger : c.textPrimary, 2),
            ),
          ),
        ),
        if (hasError || widget.helperText != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: hasError,
            child: Text(
              hasError ? widget.errorText! : widget.helperText!,
              style: QdText.caption.copyWith(
                color: hasError ? c.danger : c.textSecondary,
                fontWeight: hasError ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
