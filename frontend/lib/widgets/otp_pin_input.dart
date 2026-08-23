import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

/// A 6-digit discrete PIN input widget with auto-advance, backspace retreat,
/// paste support, and dev-mode auto-fill reactivity.
class OtpPinInput extends StatefulWidget {
  final int length;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;
  final bool autoFocus;

  const OtpPinInput({
    super.key,
    this.length = 6,
    this.controller,
    this.onChanged,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
    this.autoFocus = false,
  });

  @override
  State<OtpPinInput> createState() => _OtpPinInputState();
}

class _OtpPinInputState extends State<OtpPinInput> {
  late List<TextEditingController> _boxControllers;
  late List<FocusNode> _focusNodes;
  late List<FocusNode> _auxFocusNodes;
  late TextEditingController _internalController;
  bool _isSyncing = false;

  TextEditingController get _effectiveController =>
      widget.controller ?? _internalController;

  @override
  void initState() {
    super.initState();
    _internalController = TextEditingController();
    _boxControllers = List.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _focusNodes = List.generate(
      widget.length,
      (_) => FocusNode(),
    );
    // A6: auxiliary backspace-capture nodes must be owned for the widget's
    // lifetime, not allocated inline in _buildPinBox — the previous inline
    // `FocusNode()` allocated 6 fresh nodes on every rebuild (each keystroke)
    // that were never disposed.
    _auxFocusNodes = List.generate(
      widget.length,
      (_) => FocusNode(),
    );

    _effectiveController.addListener(_handleExternalControllerChange);
    _syncFromFullValue(_effectiveController.text);
  }

  @override
  void didUpdateWidget(OtpPinInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_handleExternalControllerChange);
      _effectiveController.addListener(_handleExternalControllerChange);
      _syncFromFullValue(_effectiveController.text);
    }
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_handleExternalControllerChange);
    if (widget.controller == null) {
      _internalController.dispose();
    }
    for (final c in _boxControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    for (final f in _auxFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _handleExternalControllerChange() {
    if (_isSyncing) return;
    final text = _effectiveController.text;
    final currentCombined = _boxControllers.map((c) => c.text).join();
    if (text != currentCombined) {
      _syncFromFullValue(text);
    }
  }

  void _syncFromFullValue(String fullValue) {
    _isSyncing = true;
    for (int i = 0; i < widget.length; i++) {
      if (i < fullValue.length) {
        _boxControllers[i].text = fullValue[i];
      } else {
        _boxControllers[i].text = '';
      }
    }
    _isSyncing = false;
  }

  void _onDigitChanged(int index, String value) {
    if (_isSyncing) return;

    // Handle multi-character paste into one box
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      _isSyncing = true;
      for (int i = 0; i < widget.length; i++) {
        final pasteIndex = index + i;
        if (pasteIndex < widget.length && i < digits.length) {
          _boxControllers[pasteIndex].text = digits[i];
        }
      }
      _isSyncing = false;
      _notifyChange();

      // Focus last filled or next empty
      final nextIndex = (index + digits.length).clamp(0, widget.length - 1);
      _focusNodes[nextIndex].requestFocus();
      return;
    }

    if (value.isNotEmpty) {
      // Auto-advance
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }

    _notifyChange();
  }

  void _notifyChange() {
    final code = _boxControllers.map((c) => c.text).join();
    _isSyncing = true;
    _effectiveController.text = code;
    _isSyncing = false;

    widget.onChanged?.call(code);
    if (code.length == widget.length) {
      widget.onCompleted?.call(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalWidth = constraints.maxWidth;
        const double spacing = AppSpacing.sm;
        final double totalSpacing = spacing * (widget.length - 1);
        final double boxWidth =
            ((totalWidth - totalSpacing) / widget.length).clamp(38.0, 52.0);
        final double boxHeight = boxWidth * 1.25;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(widget.length, (index) {
            return SizedBox(
              width: boxWidth,
              height: boxHeight,
              child: _buildPinBox(index),
            );
          }),
        );
      },
    );
  }

  Widget _buildPinBox(int index) {
    final isFocused = _focusNodes[index].hasFocus;
    Color borderColor = AppColors.outlineVariant;
    if (widget.hasError) {
      borderColor = AppColors.error;
    } else if (isFocused) {
      borderColor = AppColors.primary;
    }

    return KeyboardListener(
      focusNode: _auxFocusNodes[index], // auxiliary for backspace capture
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          if (_boxControllers[index].text.isEmpty && index > 0) {
            _boxControllers[index - 1].text = '';
            _focusNodes[index - 1].requestFocus();
            _notifyChange();
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: borderColor,
            width: isFocused || widget.hasError ? 2.0 : 1.5,
          ),
          boxShadow: isFocused ? AppElevation.shadowLevel1List : null,
        ),
        child: Center(
          child: TextField(
            key: Key('otp_box_$index'),
            controller: _boxControllers[index],
            focusNode: _focusNodes[index],
            enabled: widget.enabled,
            autofocus: widget.autoFocus && index == 0,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: AppTypography.headlineMd.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
            maxLength: 1,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (val) => _onDigitChanged(index, val),
          ),
        ),
      ),
    );
  }
}
