import 'package:flutter/material.dart';
import '../core/theme.dart';

class ThemedTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final bool obscureText;
  final bool isPasswordField;
  final TextInputType keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final int? maxLines;
  final TextDirection? textDirection;
  final int? maxLength;
  final TextAlign textAlign;
  final TextStyle? style;
  final String? counterText;

  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;

  const ThemedTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.obscureText = false,
    this.isPasswordField = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.maxLines = 1,
    this.textDirection,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.style,
    this.counterText,
    this.onFieldSubmitted,
    this.textInputAction,
  });

  @override
  State<ThemedTextField> createState() => _ThemedTextFieldState();
}

class _ThemedTextFieldState extends State<ThemedTextField> {
  late bool _obscureText;

  bool get _isPassword => widget.isPasswordField || widget.obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = _isPassword ? true : widget.obscureText;
  }

  @override
  void didUpdateWidget(ThemedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText ||
        oldWidget.isPasswordField != widget.isPasswordField) {
      if (!_isPassword) {
        _obscureText = widget.obscureText;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget? effectiveSuffixIcon = widget.suffixIcon;
    if (_isPassword && effectiveSuffixIcon == null) {
      effectiveSuffixIcon = IconButton(
        key: const Key('password_toggle_button'),
        icon: Icon(
          _obscureText
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: AppColors.onSurfaceVariant,
        ),
        tooltip: _obscureText ? 'Show password' : 'Hide password',
        onPressed: () {
          setState(() {
            _obscureText = !_obscureText;
          });
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.labelText != null) ...[
          Text(
            widget.labelText!,
            style: AppTypography.labelLg.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        TextFormField(
          controller: widget.controller,
          obscureText: _isPassword ? _obscureText : widget.obscureText,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          onChanged: widget.onChanged,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          textDirection: widget.textDirection,
          maxLength: widget.maxLength,
          textAlign: widget.textAlign,
          style: widget.style ??
              AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline),
            prefixIcon: widget.prefixIcon,
            suffixIcon: effectiveSuffixIcon,
            counterText: widget.counterText,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.defaultBorder,
              borderSide: const BorderSide(
                color: AppColors.outlineVariant,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.defaultBorder,
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: AppRadius.defaultBorder,
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: AppRadius.defaultBorder,
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 1.5,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.defaultBorder,
              borderSide: const BorderSide(
                color: AppColors.surfaceDim,
                width: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
