import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// A-OTP code boxes: [length] digit boxes, always left to right (even in
/// Arabic), filled from one hidden text field. Typing advances, backspace
/// goes back, and a pasted code (spaces or dashes included) fills every box
/// at once. [onCompleted] fires when the last digit arrives.
///
/// Box states follow the mockup: filled boxes have a 2 dp navy border, the
/// next box to type in is gold on the gold tint, empty ones are grey. With
/// [hasError] every box border is the danger color.
class QdOtpInput extends StatefulWidget {
  const QdOtpInput({
    super.key,
    required this.semanticLabel,
    this.controller,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
    this.autofocus = false,
  });

  /// Accessible name of the field ("Verification code").
  final String semanticLabel;
  final TextEditingController? controller;
  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;
  final bool autofocus;

  /// Keeps the digits of [raw], at most [length] of them.
  static String digitsOf(String raw, int length) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > length ? digits.substring(0, length) : digits;
  }

  @override
  State<QdOtpInput> createState() => _QdOtpInputState();
}

class _QdOtpInputState extends State<QdOtpInput> {
  late TextEditingController _controller =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
    _focus.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(QdOtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onText);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // A value set from outside (dev code auto-fill, a reset) can carry
  // anything: keep it to the digits so the boxes and the callbacks agree.
  void _onText() {
    final clean = QdOtpInput.digitsOf(_controller.text, widget.length);
    if (clean != _controller.text) {
      _controller.value = TextEditingValue(
        text: clean,
        selection: TextSelection.collapsed(offset: clean.length),
      );
      return;
    }
    _rebuild();
  }

  void _changed(String value) {
    widget.onChanged?.call(value);
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final text = _controller.text;
    final focused = _focus.hasFocus && widget.enabled;

    Widget box(int i) {
      final filled = i < text.length;
      final active = focused && i == text.length;
      final Color borderColor;
      final double borderWidth;
      if (widget.hasError) {
        borderColor = c.danger;
        borderWidth = 2;
      } else if (active) {
        borderColor = c.gold;
        borderWidth = 2;
      } else if (filled) {
        borderColor = c.navy;
        borderWidth = 2;
      } else {
        borderColor = c.borderInput;
        borderWidth = 1;
      }
      return Expanded(
        child: Container(
          height: 56,
          margin: EdgeInsetsDirectional.only(
            start: i == 0 ? 0 : QdSpace.x1,
            end: i == widget.length - 1 ? 0 : QdSpace.x1,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? c.goldTint
                : (widget.enabled ? c.surface : c.fillSubtle),
            borderRadius: BorderRadius.circular(QdRadius.sm),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Text(
            filled ? text[i] : '',
            style: QdText.sheetTitle.copyWith(color: c.textPrimary),
          ),
        ),
      );
    }

    // Digits read left to right in both languages, like the mockup's
    // `dir="ltr"` grid.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          ExcludeSemantics(
            child: Row(
              children: [for (var i = 0; i < widget.length; i++) box(i)],
            ),
          ),
          // The real input: invisible, on top of the boxes, so a tap
          // anywhere focuses it and a long press offers paste.
          Positioned.fill(
            child: Semantics(
              label: widget.semanticLabel,
              child: TextField(
                key: const Key('qd_otp_field'),
                controller: _controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [_DigitsFormatter(widget.length)],
                onChanged: _changed,
                showCursor: false,
                enableSuggestions: false,
                autocorrect: false,
                cursorColor: Colors.transparent,
                style: const TextStyle(color: Colors.transparent, height: 1),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps only digits, truncated to the code length, so a pasted
/// "123 456" or "123-456" fills the boxes.
class _DigitsFormatter extends TextInputFormatter {
  const _DigitsFormatter(this.length);

  final int length;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final clean = QdOtpInput.digitsOf(newValue.text, length);
    return TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: clean.length),
    );
  }
}
