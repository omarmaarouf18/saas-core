import 'package:flutter/services.dart';

/// Text limits the services enforce, counted in Unicode code points
/// ("runes", Go's `len([]rune(s))`), never in UTF-8 bytes (USER-AUTH-BE
/// item 9). Arabic letters, diacritics and emoji count the same way on the
/// phone and on the server.

/// Address text of a place (`location.address`, saved address `address`).
const int kAddressTextMaxRunes = 250;

/// Landmark note of a place (`address_note`).
const int kAddressNoteMaxRunes = 500;

/// Recipient notes and package notes.
const int kNotesMaxRunes = 200;

/// Names: recipient name, saved-address label.
const int kNameMaxRunes = 100;

/// Characters as the server counts them.
int runeLength(String s) => s.runes.length;

/// Keeps at most [maxRunes] code points (cuts at a code point, never in
/// the middle of a surrogate pair). Flutter's own length limit counts
/// grapheme clusters, which lets a diacritic-heavy Arabic text through
/// that the server then refuses.
class RuneLimitingTextInputFormatter extends TextInputFormatter {
  const RuneLimitingTextInputFormatter(this.maxRunes);

  final int maxRunes;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (runeLength(newValue.text) <= maxRunes) return newValue;
    final cut = String.fromCharCodes(newValue.text.runes.take(maxRunes));
    return TextEditingValue(
      text: cut,
      selection: TextSelection.collapsed(
          offset: newValue.selection.end.clamp(0, cut.length)),
    );
  }
}
